# Day Count (adapted from Ito.jl and InterestRates.jl)
using Dates

# ==============================================================================================================================================================
# ==============================================================================================================================================================
# ============================================================= DAY COUNTS =====================================================================================
# ==============================================================================================================================================================
# ==============================================================================================================================================================
#
# METHODS RETURNED:
# ----------------
# day_count(c::DayCount, d_start::Date, d_end::Date)
# Returns the number of days between the two dates based off of the day counter method
#
# year_fraction(c::DayCount, d_start::Date, d_end::Date)
# Returns the fraction of year between the two dates based off of the day counter method
# ==============================================================================================================================================================
# These types provide methods for determining the length of a time period according to given market convention, both as a number of days and as a year fraction.
#
#
# ------|---------------------------|-----------------
#     Date 1                      Date 2
#
# The length of this time period (Date 2 - Date 1) depends on
# * Calendar used: UK, USA, OrthodoxCalendar, etc.
# * Business Day Convention: Actual/360, ACT/ACT, etc.
# These impacts in both:
# * number of days in between
# * year fraction

# ========================
# ========================
# DayCount Type Structure
# ========================
# ========================
# All Day Counters inherit from this abstract type:
abstract type DayCount end
# Actual360 - Actual / 360 day count convention
# Actual365 - Actual/365 (Fixed) day count convention
struct Actual360 <: DayCount ; end
struct Actual365 <: DayCount ; end

# 30/360 Day Counters
abstract type Thirty360 <:DayCount end
# USAThirty360 - 30/360 (Bond Basis)
# EuroThirty360 - 30E/360 (Eurobond basis)
# ItalianThirty360 - 30/360 (Italian)
struct BondThirty360 <: Thirty360; end
struct EuroBondThirty360 <: Thirty360; end
struct ItalianThirty360 <: Thirty360; end
# Aliases
const USAThirty360 = BondThirty360
const EuroThirty360 = EuroBondThirty360

abstract type ActualActual <: DayCount end
# ISMAActualActual - the ISMA and US Treasury convention, also known as “Actual/Actual (Bond)”
# ISDAActualActual - the ISDA convention, also known as “Actual/Actual (Historical)”, “Actual/Actual”, “Act/Act”, and according to ISDA also “Actual/365”, “Act/365”, and “A/365”
# AFBActualActual - the AFB convention, also known as “Actual/Actual (Euro)”
struct ISMAActualActual <: ActualActual; end
struct ISDAActualActual <: ActualActual; end
struct AFBActualActual <: ActualActual; end
# Aliases
const ActualActualBond = ISMAActualActual

# SimpleDayCount - Simple day counter for reproducing theoretical calculations.
struct SimpleDayCount <: DayCount end

# Day Counting
# default day count method

# assuming moneths are 30 days long and year with 360 days long.
function day_count(c::BondThirty360, d_start::Date, d_end::Date)
  dd1 = day(d_start)
  dd2 = day(d_end)

  mm1 = month(d_start)
  mm2 = month(d_end)

  yy1 = year(d_start)
  yy2 = year(d_end)

  if dd2 == 31 && dd1 < 30
    dd2 = 1
    mm2 += 1
  end

  return 360.0 * (yy2 - yy1) + 30.0 * (mm2 - mm1 - 1) + max(0, 30 - dd1) + min(30, dd2)
end

function day_count(c::EuroBondThirty360, d_start::Date, d_end::Date)
  dd1 = day(d_start)
  dd2 = day(d_end)

  mm1 = month(d_start)
  mm2 = month(d_end)

  yy1 = year(d_start)
  yy2 = year(d_end)

  return 360.0 * (yy2 - yy1) + 30.0 * (mm2 - mm1 - 1) + max(0, 30 - dd1) + min(30, dd2)
end

day_count(c::DayCount, d_start::Date, d_end::Date) = Dates.value(d_end - d_start) # Int(d_end - d_start)

# days per year
days_per_year(::Union{Actual360, Thirty360}) = 360.0
days_per_year(::Actual365) = 365.0

# year fractions
# default
year_fraction(c::SimpleDayCount, d_start::Date, d_end::Date) = year_fraction(c, d_start, d_end, Date(0), Date(0))

year_fraction(c::DayCount, d_start::Date, d_end::Date) = day_count(c, d_start, d_end) / days_per_year(c)

# add'l methods
# year_fraction(c::Union{Actual360, Thirty360, Actual365}, d_start::Date, d_end::Date) = year_fraction(c, d_start, d_end, Date(), Date())
year_fraction(c::Union{Actual360, Thirty360, Actual365}, d_start::Date, d_end::Date, ::Date, ::Date) = year_fraction(c, d_start, d_end)

function year_fraction(::SimpleDayCount, d_start::Date, d_end::Date, ::Date, ::Date)
  dm_start = Dates.Day(d_start)
  dm_end = Dates.Day(d_end)

  if dm_start == dm_end || (dm_start > dm_end && Dates.lastdayofmonth(d_end) == d_end) || (dm_start < dm_end && Dates.lastdayofmonth(d_start) == d_start)
    return (Dates.Year(d_end) - Dates.Year(d_start)).value + (Dates.Month(d_end) - Dates.Month(d_start)).value / 12.0
  else
    return year_fraction(BondThirty360(), d_start, d_end)
  end
end

function year_fraction(dc::ISDAActualActual, d1::Date, d2::Date, ::Date = Date(0), ::Date = Date(0))
  if d1 == d2
    return 0.0
  end

  if d1 > d2
    return -year_fraction(dc, d2, d1, Date(0), Date(0))
  end

  y1 = year(d1)
  y2 = year(d2)

  dib1 = daysinyear(d1)
  dib2 = daysinyear(d2)
  # println(y1)
  # println(y2)
  # println(dib1)
  # println(dib2)

  sum = y2 - y1 - 1

  sum += day_count(dc, d1, Date(y1+1, 1, 1)) / dib1
  # println(d2)
  # println(day_count(dc, Date(y2, 1, 1), d2))
  sum += day_count(dc, Date(y2, 1, 1), d2) / dib2
  return sum
end

function year_fraction(dc::ISMAActualActual, d1::Date, d2::Date, d3::Date = Date(0), d4::Date = Date(0))
  if d1 == d2
    return 0.0
  end

  if d1 > d2
    return -year_fraction(dc, d2, d1, d3, d4)
  end

  ref_period_start = d3 != Date(0) ? d3 : d1
  ref_period_end = d4 != Date(0) ? d4 : d2

  months = floor(Int, 0.5 + 12 * Dates.value(ref_period_end - ref_period_start) / 365)

  if months == 0
    ref_period_start = d1
    ref_period_end = d1 + Year(1)
    months = 12
  end

  period = months / 12.0

  if d2 <= ref_period_end
    if d1 >= ref_period_start
      return period * day_count(dc, d1, d2) / day_count(dc, ref_period_start, ref_period_end)
    else
      previous_ref = ref_period_start - Month(months)
      if d2 > ref_period_start
        return year_fraction(dc, d1, ref_period_start, previous_ref, ref_period_end) + year_fraction(dc, d1, d2, previous_ref, ref_period_start)
      else
        return year_fraction(dc, d1, d2, previous_ref, ref_period_start)
      end
    end
  else
    sum = year_fraction(dc, d1, ref_period_end, ref_period_start, ref_period_end)
    i = 0
    new_ref_start = new_ref_end = Date(0)
    while true
      new_ref_start = ref_period_end + Month(i * months)
      new_ref_end = ref_period_end + Month((i + 1) * months)
      if d2 < new_ref_end
        break
      else
        sum += period
        i += 1
      end
    end
    sum += year_fraction(dc, new_ref_start, d2, new_ref_start, new_ref_end)
    return sum
  end
end
