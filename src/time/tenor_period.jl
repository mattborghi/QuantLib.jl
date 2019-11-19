using Dates

# TenorPeriod struct # ==============
# Constructed using a period
# and a frequency
# some examples are
# ---> For Frequency inputs
# QuantLib.Time.TenorPeriod{Month}(6 months, QuantLib.Time.Semiannual())
# QuantLib.Time.TenorPeriod{Year}(1 year, QuantLib.Time.Annual())
# QuantLib.Time.TenorPeriod{Day}(0 days, QuantLib.Time.NoFrequency())
# QuantLib.Time.TenorPeriod{Week}(2 weeks, QuantLib.Time.Biweekly())
# QuantLib.Time.TenorPeriod{Day}(1 day, QuantLib.Time.Daily())
# QuantLib.Time.TenorPeriod{Day}(0 days, QuantLib.Time.NoFrequency())
# ---> For Date.Years inputs
# Dates.Year(1) -> QuantLib.Time.TenorPeriod{Year}(1 year, QuantLib.Time.Annual())
# Dates.Year(5) -> QuantLib.Time.TenorPeriod{Year}(5 years, QuantLib.Time.Annual())
# ---> For Date.Months inputs
# Dates.Month(5) -> QuantLib.Time.TenorPeriod{Month}(5 months, QuantLib.Time.Monthly())
# ---> For Date.Week inputs
# Dates.Week(5) -> QuantLib.Time.TenorPeriod{Week}(5 weeks, QuantLib.Time.Weekly())
struct TenorPeriod{P <: Dates.Period}
  period::P
  freq::Frequency
end

# Constructors
"""
TenorPeriod -> set the period given the frequency
"""
function TenorPeriod(f::Frequency)
  freq = value(f)
  if freq < 0
    # NoFrequency or nothing
    period = Dates.Day(0)
  elseif freq <= 1
    # once or annual
    period = Dates.Year(freq)
  elseif freq <= 12
    period = Dates.Month(12 / freq)
  elseif freq <= 52
    period = Dates.Week(52/freq)
  else
    period = Dates.Day(1)
  end

  return TenorPeriod(period, f)
end

TenorPeriod(p::Dates.Year) = TenorPeriod(p, Annual())

function TenorPeriod(p::Dates.Month)
  x = Dates.value(p)
  if x == 6
    return TenorPeriod(p, Semiannual())
  elseif x == 3
    return TenorPeriod(p, Quarterly())
  elseif x == 4
    return TenorPeriod(p, EveryFourthMonth())
  elseif x == 2
    return TenorPeriod(p, Bimonthly())
  else
    return TenorPeriod(p, Monthly())
  end
end

function TenorPeriod(p::Dates.Week)
  x = Dates.value(p)
  if x == 26
    return TenorPeriod(p, Biweekly())
  elseif x == 13
    return TenorPeriod(p, EveryFourthWeek())
  else
    return TenorPeriod(p, Weekly())
  end
end
