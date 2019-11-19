using Dates

# helper methods
function next_twentieth(d::Date)
  res = Date(year(d), month(d), 20)
  if res < d
    res += Month(1)
  end

  # add logic for certain rules passed in
  m = month(res)
  if m % 3 != 0 # not a main IMM month
    skip_ = 3 - m%3
    res += skip_ * Month(1)
  end

  return res
end

# ===============================================================================================================================================================================================
# ===============================================================================================================================================================================================
# These conventions specify the rule used to generate dates in a Schedule.
#
# ----|-------------------------------------|--------------
#   Effective Date                      Termination Date
#
abstract type DateGenerationRule end
# DateGenerationBackwards - Backward from termination date to effective date.
# DateGenerationForwards - Forward from effective date to termination date.
# DateGenerationTwentieth - All dates but the effective date are taken to be the twentieth of their month (used for CDS schedules in emerging markets.) The termination date is also modified.

# Both the effective and the termination dates are preserved.
struct DateGenerationBackwards <: DateGenerationRule end
# Both the effective and the termination dates are preserved.
struct DateGenerationForwards <: DateGenerationRule end
# The effective date is preserved, the subsequent dates are all 20th.
struct DateGenerationTwentieth <: DateGenerationRule end
# ===============================================================================================================================================================================================
# ===============================================================================================================================================================================================

# ==============================================================================================================================================================
# ==============================================================================================================================================================
# ============================================================= SCHEDULE =======================================================================================
# ==============================================================================================================================================================
# ==============================================================================================================================================================

# Payment schedule data structure
struct Schedule{B <: BusinessDayConvention, B1 <: BusinessDayConvention, D <: DateGenerationRule, C <: BusinessCalendar}
  # date of start
  effectiveDate::Date
  # date of termination
  terminationDate::Date
  # the 'frequency'
  tenor::TenorPeriod
  # what happens if day is a holiday?
  convention::B
  # idem but with termination date
  termDateConvention::B1
  # how are we building the schedules?
  rule::D
  #
  endOfMonth::Bool
  # the array of dates
  dates::Vector{Date}
  # what business calendar do we use?
  cal::C

  function Schedule{B, B1, D, C}(effectiveDate::Date,
                                terminationDate::Date,
                                tenor::TenorPeriod,
                                convention::B,
                                termDateConvention::B1,
                                rule::D,
                                endOfMonth::Bool,
                                dates::Vector{Date},
                                cal::C = TargetCalendar()) where {B, B1, D, C}
    # adjust end date if necessary using the termDateConvention
    dates[end] = adjust(cal, termDateConvention, dates[end])

    new{B, B1, D, C}(effectiveDate, terminationDate, tenor, convention, termDateConvention, rule, endOfMonth, dates, cal)
  end
end

# =============================#
# Three types of Schedule rules:
# DateGenerationForwards
# DateGenerationBackwards
# DateGenerationTwentieth
# =============================#

# -----------------------
# DateGenerationForwards
# -----------------------
function Schedule(effectiveDate::Date,
                  terminationDate::Date,
                  tenor::TenorPeriod,
                  convention::B,
                  termDateConvention::B1,
                  rule::DateGenerationForwards,
                  endOfMonth::Bool,
                  cal::C = TargetCalendar()) where {B <: BusinessDayConvention, B1 <: BusinessDayConvention, C <: BusinessCalendar}
  # dt = effectiveDate
  # num_dates = 1
  #
  # while dt < terminationDate
  #   dt += tenor.period
  #   num_dates += 1
  # end
  #
  # dates = Vector{Date}(num_dates)
  #
  # dates[1] = effectiveDate
  # dates[end] = terminationDate
  #
  # dt = effectiveDate + tenor.period
  # i = 2
  # while dt < terminationDate
  #   dates[i] = dt
  #   dt += tenor.period
  #   i += 1
  # end

  # this way is about 5-10 microseconds faster for semiannual freq over 25 years
  dates = Vector{Date}()
  dt = effectiveDate
  # push the effective date according to the convention and calendar used
  push!(dates, adjust(cal, convention, dt))
  dt += tenor.period
  # push subsequent dates adjusted
  while dt < terminationDate
    # dates are completed forwards
    push!(dates, adjust(cal, convention, dt))
    dt += tenor.period
  end
  # push the date if it's equal to the termination date
  if dates[end] != terminationDate
    push!(dates, terminationDate)
  end

  return Schedule{B, B1, DateGenerationForwards, C}(effectiveDate, terminationDate, tenor, convention, termDateConvention, rule, endOfMonth, dates, cal)
end

# -----------------------
# DateGenerationBackwards
# -----------------------
function Schedule(effectiveDate::Date,
                  terminationDate::Date,
                  tenor::TenorPeriod,
                  convention::B,
                  termDateConvention::B1,
                  rule::DateGenerationBackwards,
                  endOfMonth::Bool,
                  cal::C = TargetCalendar()) where {B <: BusinessDayConvention, B1 <: BusinessDayConvention, C <: BusinessCalendar}

  size = get_size(tenor.period, effectiveDate, terminationDate)
  dates = Vector{Date}(undef, size)
  # hardcode effective and termination dates
  dates[1] = effectiveDate
  dates[end] = terminationDate

  period = 1
  # For an explanation on why @simd and @inbounds are used see this
  # https://docs.julialang.org/en/v1/manual/performance-tips/index.html
  @simd for i = size - 1:-1:2
    # times are completed backwards! -> terminationDate - period * tenor.period
    @inbounds dates[i] = adjust(cal, convention, terminationDate - period * tenor.period)
    period += 1
  end
  # dt = effectiveDate
  # last_date = terminationDate
  # insert!(dates, 1, terminationDate)
  # period = 1
  # while true
  #   temp = last_date - period * tenor.period
  #   if temp < dt
  #     break
  #   end
  #   insert!(dates, 1, temp)
  #   period += 1
  # end
  #
  # insert!(dates, 1, effectiveDate)

  return Schedule{B, B1, DateGenerationBackwards, C}(effectiveDate, terminationDate, tenor, convention, termDateConvention, rule, endOfMonth, dates, cal)
end

# -----------------------
# DateGenerationTwentieth
# -----------------------
function Schedule(effectiveDate::Date,
                  terminationDate::Date,
                  tenor::TenorPeriod,
                  convention::B,
                  termDateConvention::B1,
                  rule::DateGenerationTwentieth,
                  endOfMonth::Bool,
                  cal::C = TargetCalendar()) where {B <: BusinessDayConvention, B1 <: BusinessDayConvention, C <: BusinessCalendar}

  dates = Vector{Date}()
  dt = effectiveDate
  # push the adjusted effective date
  push!(dates, adjust(cal, convention, dt))
  seed = effectiveDate

  # next 20th
  next20th = next_twentieth(effectiveDate)
  # push the subsequent dates falling on the 20th
  if next20th != effectiveDate
    push!(dates, next20th)
    seed = next20th
  end

  seed += tenor.period
  while seed < terminationDate
    push!(dates, adjust(cal, convention, seed))
    seed += tenor.period
  end

  if dates[end] != adjust(cal, convention, terminationDate)
    push!(dates, next_twentieth(terminationDate))
  else
    push!(dates, terminationDate)
  end

  return Schedule{B, B1, DateGenerationTwentieth, C}(effectiveDate, terminationDate, tenor, convention, termDateConvention, rule, endOfMonth, dates, cal)
end

# helpers
function get_size(p::Dates.Month, ed::Date, td::Date)
  return Int(ceil(ceil(Dates.value(td - ed) / 30) / Dates.value(p)))
end

function get_size(p::Dates.Year, ed::Date, td::Date)
  # ed_day, ed_month = monthday(ed)
  # td_day, td_month = monthday(td)
  if monthday(ed) == monthday(td)
    return Int(round(Dates.value(td - ed) / 365) + 1)
  else
    return Int(ceil(Dates.value(td - ed) / 365) + 1)
  end
end
