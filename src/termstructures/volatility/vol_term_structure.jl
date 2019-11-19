using Dates

struct NullOptionletVolatilityStructure <: OptionletVolatilityStructure end

struct ShiftedLognormalVolType <: VolatilityType end
struct NormalVolType <: VolatilityType end

mutable struct FlatSmileSection{DC <: DayCount, V <: VolatilityType} <: AbstractSmileSection
  exerciseDate::Date
  exerciseTime::Float64
  vol::Float64
  dc::DC
  referenceDate::Date
  atmLevel::Float64
  shift::Float64
  volType::V
  isFloating::Bool
end

function FlatSmileSection(d::Date, vol::Float64, dc::DC, referenceDate::Date = Date(0), atmLevel::Float64 = -1.0, shift::Float64 = 0.0) where {DC <: DayCount}
  d >= referenceDate || error("Exercise Date must be greater than reference date")
  exerciseTime = year_fraction(dc, referenceDate, d)
  isFloating = referenceDate == Date(0)
  return FlatSmileSection{DC, ShiftedLognormalVolType}(d, exerciseTime, vol, dc, referenceDate, atmLevel, shift, ShiftedLognormalVolType(), isFloating)
end

volatility_impl(smile::FlatSmileSection, ::Float64) = smile.vol
volatility(smile::AbstractSmileSection, rate::Float64) = volatility_impl(smile, rate)

mutable struct ConstantOptionVolatility{B <: BusinessCalendar, C <: BusinessDayConvention, DC <: DayCount} <: OptionletVolatilityStructure
  settlementDays::Int
  referenceDate::Date
  calendar::B
  bdc::C
  volatility::Float64
  dc::DC
end

function ConstantOptionVolatility(settlementDays::Int, calendar::B, bdc::C, volatility::Float64, dc::DC) where {B <: BusinessCalendar, C <: BusinessDayConvention, DC <: DayCount}
  today = settings.evaluation_date
  ref_date = advance(Dates.Day(settlementDays), calendar, today, bdc)
  ConstantOptionVolatility{B, C, DC}(settlementDays, ref_date, calendar, bdc, volatility, dc)
end

# Swaption Volatility structures
mutable struct ConstantSwaptionVolatility{B <: BusinessCalendar, C <: BusinessDayConvention, DC <: DayCount} <: SwaptionVolatilityStructure
  settlementDays::Int
  referenceDate::Date
  calendar::B
  bdc::C
  volatility::Quote
  dc::DC
end

# floating reference date, floating market data
ConstantSwaptionVolatility(settlementDays::Int, cal::B, bdc::C, volatility::Quote, dc::DC) where {B <: BusinessCalendar, C <: BusinessDayConvention, DC <: DayCount} =
                          ConstantSwaptionVolatility{B, C, DC}(settlementDays, Date(0), cal, bdc, volatility, dc)

# Local Vol Term Structure #
mutable struct LocalConstantVol{DC <: DayCount} <: LocalVolTermStructure
  referenceDate::Date
  settlementDays::Int
  volatility::Quote
  dc::DC
end

LocalConstantVol(refDate::Date, volatility::Float64, dc::DayCount) = LocalConstantVol(refDate, 0, Quote(volatility), dc)

local_vol_impl(volTS::LocalConstantVol, ::Float64, ::Float64) = volTS.volatility.value

function local_vol(volTS::LocalVolTermStructure, t::Float64, underlyingLevel::Float64)
  # TODO check stuff
  return local_vol_impl(volTS, t, underlyingLevel)
end

function black_variance(ovs::OptionletVolatilityStructure, option_date::Date, strike::Float64)
  v = calc_volatility(ovs, option_date, strike)
  t = time_from_reference(ovs, option_date)
  return v * v * t
end

function calc_volatility(ovs::OptionletVolatilityStructure, option_date::Date, strike::Float64)
  # TODO checks - see optionletvolatilitystructure.hpp, volatility
  return volatility_impl(ovs, option_date, strike)
end

volatility_impl(ovs::OptionletVolatilityStructure, option_date::Date, strike::Float64) =
              volatility_impl(ovs, time_from_reference(ovs, option_date), strike)

volatility_impl(const_opt_vol::ConstantOptionVolatility, ::Float64, ::Float64) = const_opt_vol.volatility

# Swaption Volatility methods
function swap_length(swapVol::SwaptionVolatilityStructure, _start::Date, _end::Date)
  result = round(float(Dates.value(_end - _start)) / 365.25 * 12.0) # month unit
  result /= 12.0 # year unit
  return result
end

function calc_volatility(swapVol::SwaptionVolatilityStructure, optionDate::Date, swapLength::Float64, strike::Float64)
  # TODO add checks
  optionTime = time_from_reference(swapVol, optionDate)
  return volatility_impl(swapVol, optionTime, swapLength, strike)
end

volatility_impl(swapVol::ConstantSwaptionVolatility, ::Float64, ::Float64, ::Float64) = swapVol.volatility.value

function black_variance(swapVol::SwaptionVolatilityStructure, optionDate::Date, swapLength::Float64, strike::Float64)
  v = calc_volatility(swapVol, optionDate, swapLength, strike)
  optionTime = time_from_reference(swapVol, optionDate)
  return v * v * optionTime
end

function smile_section_impl(swapVol::ConstantSwaptionVolatility, optionDate::Date, ::Dates.Period)
  atmVol = swapVol.volatility.value
  return FlatSmileSection(optionDate, atmVol, swapVol.dc, reference_date(swapVol))
end

smile_section(swapVol::SwaptionVolatilityStructure, optionDate::Date, swapTenor::Dates.Period) = smile_section_impl(swapVol, optionDate, swapTenor)
