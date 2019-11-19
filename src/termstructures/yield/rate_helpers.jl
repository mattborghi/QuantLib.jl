using Dates

mutable struct SwapRateHelper{PrT <: Dates.Period, PrS <: Dates.Period} <: RateHelper
  rate::Quote
  tenor::PrT
  fwdStart::PrS
  swap::VanillaSwap
end

function SwapRateHelper(rate::Float64, tenor::PrT, cal::C, fixedFrequency::F, fixedConvention::B, fixedDayCount::DC, iborIndex::IborIndex, spread::Float64, fwdStart::PrS,
                    pricingEngine::P = DiscountingSwapEngine(), settlementDays::Int = iborIndex.fixingDays, nominal::Float64 = 1.0, swapT::ST = Payer(), 
                    fixedRate::Float64 = 0.0) where {PrT <: Dates.Period, C <: BusinessCalendar, F <: Frequency, B <: BusinessDayConvention, DC <: DayCount, PrS <: Dates.Period, P <: PricingEngine, ST <: SwapType}
  # do stuff
  fixedCal = cal
  floatingCal = cal
  floatTenor = iborIndex.tenor
  fixedTenor = QuantLib.Time.TenorPeriod(fixedFrequency)
  fixedTermConvention = fixedConvention
  floatConvention = iborIndex.convention
  floatTermConvention = iborIndex.convention
  fixedRule = DateGenerationBackwards()
  floatRule = DateGenerationBackwards()
  floatDayCount = iborIndex.dc
  # fixed_rate = 0.0

  ref_date = adjust(floatingCal, floatConvention, settings.evaluation_date)
  spot_date = advance(Dates.Day(settlementDays), floatingCal, ref_date, floatConvention)
  start_date = adjust(floatingCal, floatConvention, spot_date + fwdStart)
  ## TODO Float end of month (defaults to false)
  end_date = start_date + tenor

  # build schedules
  fixed_schedule = Schedule(start_date, end_date, fixedTenor, fixedConvention, fixedTermConvention, fixedRule, false, fixedCal)
  float_schedule = Schedule(start_date, end_date, floatTenor, floatConvention, floatTermConvention, floatRule, false, floatingCal)


  swap = VanillaSwap(swapT, nominal, fixed_schedule, fixedRate, fixedDayCount, iborIndex, spread, float_schedule, floatDayCount, pricingEngine, fixedConvention)

  return SwapRateHelper{PrT, PrS}(Quote(rate), tenor, fwdStart, swap)
end

maturity_date(sh::SwapRateHelper) = maturity_date(sh.swap)

struct DepositRateHelper{B <: BusinessCalendar, C <: BusinessDayConvention, DC <: DayCount} <: RateHelper
  rate::Quote
  tenor::TenorPeriod
  fixingDays::Int
  calendar::B
  convention::C
  endOfMonth::Bool
  dc::DC
  iborIndex::IborIndex
  evaluationDate::Date
  referenceDate::Date
  earliestDate::Date
  maturityDate::Date
  fixingDate::Date
end

function DepositRateHelper(rate::Quote, tenor::TenorPeriod, fixingDays::Integer, calendar::B, convention::C, endOfMonth::Bool, dc::DC) where {B <: BusinessCalendar, C <: BusinessDayConvention, DC <: DayCount}
  ibor_index = IborIndex("no-fix", tenor, fixingDays, NullCurrency(), calendar, convention, endOfMonth, dc)
  evaluation_date = settings.evaluation_date
  reference_date = adjust(calendar, convention, evaluation_date)
  earliest_date = advance(Dates.Day(fixingDays), calendar, reference_date, convention)
  maturity_d = maturity_date(ibor_index, earliest_date)
  fix_date = fixing_date(ibor_index, earliest_date)
  return DepositRateHelper{B, C, DC}(rate, tenor, fixingDays, calendar, convention, endOfMonth, dc, ibor_index, evaluation_date, reference_date, earliest_date, maturity_d, fix_date)
end

maturity_date(rate::RateHelper) = rate.maturityDate

value(rate::RateHelper) = rate.rate.value

function implied_quote(swap_helper::SwapRateHelper)
  swap = swap_helper.swap
  recalculate!(swap)
  #
  # println("Floating Leg NPV ", floating_leg_NPV(swap))
  # println("Floating Leg BPS ", floating_leg_BPS(swap))
  # println("Fixed Leg BPS ", fixed_leg_BPS(swap))
  # println("Swap spread ", swap.spread)

  floatingLegNPV = floating_leg_NPV(swap)
  spread = swap.spread
  spreadNPV = floating_leg_BPS(swap) / basisPoint * spread
  totNPV = -(floatingLegNPV + spreadNPV)

  return totNPV / (fixed_leg_BPS(swap) / basisPoint)
end

function implied_quote(rh::RateHelper)
  return fixing(rh.iborIndex, rh.iborIndex.ts, rh.fixingDate, true)
end

struct FraRateHelper{D <: Dates.Period, II <: IborIndex} <: RateHelper
  rate::Quote
  evaluationDate::Date
  periodToStart::D
  iborIndex::II
  fixingDate::Date
  earliestDate::Date
  latestDate::Date
end

function FraRateHelper(rate::Quote, monthsToStart::Int, monthsToEnd::Int, fixingDays::Int, calendar::BusinessCalendar, convention::BusinessDayConvention, endOfMonth::Bool, dc::DayCount)
  periodToStart = Dates.Month(monthsToStart)
  iborIndex = IborIndex("no-fix", TenorPeriod(Dates.Month(monthsToEnd - monthsToStart)), fixingDays, NullCurrency(), calendar, convention, endOfMonth, dc)
  evaluationDate = settings.evaluation_date

  # initialize dates
  refDate = adjust(iborIndex.fixingCalendar, evaluationDate)
  spotDate = advance(Dates.Day(iborIndex.fixingDays), calendar, refDate)
  earliestDate = advance(periodToStart, calendar, spotDate, convention)
  latestDate = maturity_date(iborIndex, earliestDate)
  fixingDate = fixing_date(iborIndex, earliestDate)

  return FraRateHelper{Dates.Month, typeof(iborIndex)}(rate, evaluationDate, periodToStart, iborIndex, fixingDate, earliestDate, latestDate)
end

maturity_date(fra::FraRateHelper) = fra.latestDate

# Clone functions #
function clone(depo::DepositRateHelper, ts::TermStructure = depo.iborIndex.ts)
  # first we have to clone a new index
  newIdx = clone(depo.iborIndex, ts)
  #now we build a new depo helper
  return DepositRateHelper(depo.rate, depo.tenor, depo.fixingDays, depo.calendar, depo.convention, depo.endOfMonth, depo.dc, newIdx, depo.evaluationDate, depo.referenceDate,
                          depo.earliestDate, depo.maturityDate, depo.fixingDate)
end

function clone(fra::FraRateHelper, ts::TermStructure = fra.iborIndex.ts)
  # clone new index
  newIdx = clone(fra.iborIndex, ts)

  # build new fra helper
  return FraRateHelper(fra.rate, fra.evaluationDate, fra.periodToStart, newIdx, fra.fixingDate, fra.earliestDate, fra.latestDate)
end

function clone(swapHelper::SwapRateHelper, ts::TermStructure = swapHelper.swap.iborIndex.ts)
  # first we need a new PE for the swap
  newPE = clone(swapHelper.swap.pricingEngine, ts)
  # then we have to clone the swap
  newSwap = clone(swapHelper.swap, newPE, ts)

  # now we can clone the helper
  return SwapRateHelper(swapHelper.rate, swapHelper.tenor, swapHelper.fwdStart, newSwap)
end

update_termstructure(rateHelper::RateHelper, ts::TermStructure) = clone(rateHelper, ts)
