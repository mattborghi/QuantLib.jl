struct Payer <: SwapType end
struct Receiver <: SwapType end

struct Buyer <: CDSProtectionSide end
struct Seller <: CDSProtectionSide end

mutable struct SwapResults <: Results
  legNPV::Vector{Float64}
  legBPS::Vector{Float64}
  npvDateDiscount::Float64
  startDiscounts::Vector{Float64}
  endDiscounts::Vector{Float64}
  fairRate::Float64
  value::Float64

  function SwapResults(n::Int)
    legNPV = zeros(n)
    legBPS = zeros(n)
    startDiscounts = zeros(n)
    endDiscounts = zeros(n)

    new(legNPV, legBPS, 0.0, startDiscounts, endDiscounts, -1.0, 0.0)
  end
end

mutable struct VanillaSwapArgs
  fixedResetDates::Vector{Date}
  fixedPayDates::Vector{Date}
  floatingResetDates::Vector{Date}
  floatingPayDates::Vector{Date}
  floatingAccrualTimes::Vector{Float64}
  floatingSpreads::Vector{Float64}
  fixedCoupons::Vector{Float64}
  floatingCoupons::Vector{Float64}
end

function VanillaSwapArgs(legs::Vector{L}) where {L <: Leg}
  fixedCoups = legs[1].coupons
  floatingCoups = legs[2].coupons
  fixedCoupons = [amount(coup) for coup in fixedCoups]
  # floatingCoupons = [amount(coup) for coup in floatingCoups]
  floatingCoupons = zeros(length(floatingCoups))
  floatingAccrualTimes = [accrual_period(coup) for coup in floatingCoups]
  floatingSpreads = [coup.spread for coup in floatingCoups]
  return VanillaSwapArgs(get_reset_dates(fixedCoups), get_pay_dates(fixedCoups), get_reset_dates(floatingCoups), get_pay_dates(floatingCoups), floatingAccrualTimes, floatingSpreads, fixedCoupons, floatingCoupons)
end

function reset!(sr::SwapResults)
  n = length(sr.legNPV)
  sr.legNPV = zeros(n)
  sr.legBPS = zeros(n)
  sr.npvDateDiscount = 0.0
  sr.startDiscounts = zeros(n)
  sr.endDiscounts = zeros(n)
  sr.value = 0.0
  sr.fairRate = 0.0

  return sr
end

mutable struct NonstandardSwapArgs
  vSwapArgs::VanillaSwapArgs
  fixedIsRedemptionFlow::Vector{Bool}
  floatingIsRedemptionFlow::Vector{Bool}
  floatingGearings::Vector{Float64}
end

function NonstandardSwapArgs(legs::Vector{L}) where {L <: Leg}
  vSwapArgs = VanillaSwapArgs(legs)
  fixedIsRedemptionFlow = Bool[!check_coupon(cf) for cf in legs[1].coupons]
  floatingIsRedemptionFlow = Bool[!check_coupon(cf) for cf in legs[2].coupons]
  floatingGearings = get_gearings(legs[2].coupons)

  return NonstandardSwapArgs(vSwapArgs, fixedIsRedemptionFlow, floatingIsRedemptionFlow, floatingGearings)
end

mutable struct CDSResults
  upfrontNPV::Float64
  couponLegNPV::Float64
  defaultLegNPV::Float64
  fairSpread::Float64
  fairUpfront::Float64
  couponLegBPS::Float64
  upfrontBPS::Float64
  value::Float64
end

CDSResults() = CDSResults(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)

function reset!(cr::CDSResults)
  cr.upfrontNPV = 0.0
  cr.couponLegNPV = 0.0
  cr.defaultLegNPV = 0.0
  cr.fairSpread = 0.0
  cr.fairUpfront = 0.0
  cr.couponLegBPS = 0.0
  cr.upfrontBPS = 0.0
  cr.value = 0.0

  return cr
end

mutable struct VanillaSwap{ST <: SwapType, DC_fix <: DayCount, DC_float <: DayCount, B <: BusinessDayConvention, L <: Leg, P <: PricingEngine, II <: IborIndex} <: Swap
  lazyMixin::LazyMixin
  swapT::ST
  nominal::Float64
  fixedSchedule::Schedule
  fixedRate::Float64
  fixedDayCount::DC_fix
  iborIndex::II
  spread::Float64
  floatSchedule::Schedule
  floatDayCount::DC_float
  paymentConvention::B
  legs::Vector{L}
  payer::Vector{Float64}
  pricingEngine::P
  results::SwapResults
  args::VanillaSwapArgs
end

# Constructors
function VanillaSwap(swapT::ST,
                    nominal::Float64,
                    fixedSchedule::Schedule,
                    fixedRate::Float64,
                    fixedDayCount::DC_fix,
                    iborIndex::II,
                    spread::Float64,
                    floatSchedule::Schedule,
                    floatDayCount::DC_float,
                    pricingEngine::P = NullPricingEngine(),
                    paymentConvention::B = floatSchedule.convention) where {ST <: SwapType, DC_fix <: DayCount, DC_float <: DayCount, B <: BusinessDayConvention, P <: PricingEngine, II <: IborIndex}
  # build swap cashflows
  legs = Vector{Leg}(undef, 2)
  # first leg is fixed
  legs[1] = FixedRateLeg(fixedSchedule, nominal, fixedRate, fixedSchedule.cal, paymentConvention, fixedDayCount; add_redemption=false)
  # second leg is floating
  legs[2] = IborLeg(floatSchedule, nominal, iborIndex, floatDayCount, paymentConvention; add_redemption=false)

  payer = _build_payer(swapT)

  results = SwapResults(2)

  return VanillaSwap{ST, DC_fix, DC_float, B, Leg, P, II}(LazyMixin(), swapT, nominal, fixedSchedule, fixedRate, fixedDayCount, iborIndex, spread,
                      floatSchedule, floatDayCount, paymentConvention, legs, payer, pricingEngine, results, VanillaSwapArgs(legs))
end

# accessor methods #
get_fixed_reset_dates(swap::VanillaSwap) = swap.args.fixedResetDates
get_fixed_pay_dates(swap::VanillaSwap) = swap.args.fixedPayDates
get_floating_reset_dates(swap::VanillaSwap) = swap.args.floatingResetDates
get_floating_pay_dates(swap::VanillaSwap) = swap.args.floatingPayDates
get_floating_accrual_times(swap::VanillaSwap) = swap.args.floatingAccrualTimes
get_floating_spreads(swap::VanillaSwap) = swap.args.floatingSpreads
get_fixed_coupons(swap::VanillaSwap) = swap.args.fixedCoupons
get_floating_coupons(swap::VanillaSwap) = swap.args.floatingCoupons

mutable struct NonstandardSwap{ST <: SwapType, DC_fix <: DayCount, DC_float <: DayCount, B <: BusinessDayConvention, L <: Leg, P <: PricingEngine, II <: IborIndex} <: Swap
  lazyMixin::LazyMixin
  swapT::ST
  fixedNominal::Vector{Float64}
  floatingNominal::Vector{Float64}
  fixedSchedule::Schedule
  fixedRate::Vector{Float64}
  fixedDayCount::DC_fix
  iborIndex::II
  spread::Float64
  gearing::Float64
  floatSchedule::Schedule
  floatDayCount::DC_float
  paymentConvention::B
  intermediateCapitalExchange::Bool
  finalCapitalExchange::Bool
  legs::Vector{L}
  payer::Vector{Float64}
  pricingEngine::P
  results::SwapResults
  args::NonstandardSwapArgs
end

# Constructor #
function NonstandardSwap(vs::VanillaSwap{ST, DC_fix, DC_float, B, Leg, P, II}) where {ST <: SwapType, DC_fix <: DayCount, DC_float <: DayCount, B <: BusinessDayConvention, P <: PricingEngine, II <: IborIndex}
  # build swap cashflows
  legs = Vector{Leg}(undef, 2)
  # first leg is fixed
  legs[1] = FixedRateLeg(vs.fixedSchedule, vs.nominal, vs.fixedRate, vs.fixedSchedule.cal, vs.paymentConvention, vs.fixedDayCount; add_redemption=false)
  # second leg is floating
  legs[2] = IborLeg(vs.floatSchedule, vs.nominal, vs.iborIndex, vs.floatDayCount, vs.paymentConvention; add_redemption=false)

  payer = _build_payer(vs.swapT)

  results = SwapResults(2)

  fixedSize = length(vs.legs[1].coupons)
  floatSize = length(vs.legs[2].coupons)

  return NonstandardSwap{ST, DC_fix, DC_float, B, Leg, P, II}(LazyMixin(), vs.swapT, fill(vs.nominal, fixedSize), fill(vs.nominal, floatSize), vs.fixedSchedule, fill(vs.fixedRate, fixedSize),
                        vs.fixedDayCount, vs.iborIndex, vs.spread, 1.0, vs.floatSchedule, vs.floatDayCount, vs.paymentConvention, false, false, legs,
                        payer, vs.pricingEngine, results, NonstandardSwapArgs(legs))
end

# accessor methods #
get_fixed_reset_dates(swap::NonstandardSwap) = swap.args.vSwapArgs.fixedResetDates
get_fixed_pay_dates(swap::NonstandardSwap) = swap.args.vSwapArgs.fixedPayDates
get_floating_reset_dates(swap::NonstandardSwap) = swap.args.vSwapArgs.floatingResetDates
get_floating_pay_dates(swap::NonstandardSwap) = swap.args.vSwapArgs.floatingPayDates
get_floating_accrual_times(swap::NonstandardSwap) = swap.args.vSwapArgs.floatingAccrualTimes
get_floating_spreads(swap::NonstandardSwap) = swap.args.vSwapArgs.floatingSpreads
get_fixed_coupons(swap::NonstandardSwap) = swap.args.vSwapArgs.fixedCoupons
get_floating_coupons(swap::NonstandardSwap) = swap.args.vSwapArgs.floatingCoupons

# CDS #
mutable struct CreditDefaultSwap{S <: CDSProtectionSide, B <: BusinessDayConvention, DC <: DayCount, P <: PricingEngine, C <: CompoundingType, F <: Frequency} <: Swap
  lazyMixin::LazyMixin
  side::S
  notional::Float64
  spread::Float64
  schedule::Schedule
  convention::B
  dc::DC
  leg::FixedRateLeg{FixedRateCoupon{DC, InterestRate{DC, C, F}}}
  upfrontPayment::SimpleCashFlow
  settlesAccrual::Bool
  paysAtDefaultTime::Bool
  protectionStart::Date
  pricingEngine::P
  claim::FaceValueClaim
  results::CDSResults

  CreditDefaultSwap{S, B, DC, P, C, F}(lazyMixin::LazyMixin,
                    side::S,
                    notional::Float64,
                    spread::Float64,
                    schedule::Schedule,
                    convention::B,
                    dc::DC,
                    leg::FixedRateLeg{FixedRateCoupon{DC, InterestRate{DC, C, F}}},
                    upfrontPayment::SimpleCashFlow,
                    settlesAccrual::Bool,
                    paysAtDefaultTime::Bool,
                    protectionStart::Date,
                    pricingEngine::P) where {S, B, DC, P, C, F} =
                                            new{S, B, DC, P, C, F}(lazyMixin, side, notional, spread, schedule, convention, dc, leg, upfrontPayment, settlesAccrual,
                                            paysAtDefaultTime, protectionStart, pricingEngine, FaceValueClaim(), CDSResults())
end

function CreditDefaultSwap(side::S,
                          notional::Float64,
                          spread::Float64,
                          schedule::Schedule,
                          convention::B,
                          dc::DC,
                          settlesAccrual::Bool,
                          paysAtDefaultTime::Bool,
                          protectionStart::Date,
                          pricingEngine::P) where {S <: CDSProtectionSide, B <: BusinessDayConvention, DC <: DayCount, P <: PricingEngine}
  # build leg
  leg = FixedRateLeg(schedule, notional, spread, schedule.cal, convention, dc; add_redemption = false)

  # build upfront payment
  upfrontPayment = SimpleCashFlow(0.0, schedule.dates[1])
  return CreditDefaultSwap{S, B, DC, P, SimpleCompounding, typeof(schedule.tenor.freq)}(LazyMixin(), side, notional, spread, schedule, convention, dc, leg, upfrontPayment, settlesAccrual, paysAtDefaultTime, protectionStart, pricingEngine)
end

# Swap Helper methods
function _build_payer(swapT::Payer)
  x = ones(2)
  x[1] = -1.0
  return x
end

function _build_payer(swapT::Receiver)
  x = ones(2)
  x[2] = -1.0
  return x
end

# Swap methods #
function maturity_date(swap::Swap)
  d = maturity_date(swap.legs[1])
  for i = 2:length(swap.legs)
    d = max(d, maturity_date(swap.legs[i]))
  end

  return d
end

# Calculation method #
function perform_calculations!(swap::VanillaSwap)
  reset!(swap.results) # reset - TODO this will be expanded
  swap.args.floatingCoupons = [amount(coup) for coup in swap.legs[2].coupons]
  _calculate!(swap.pricingEngine, swap)

  return swap
end

function perform_calculations!(cds::CreditDefaultSwap)
  reset!(cds.results)
  _calculate!(cds.pricingEngine, cds)

  return cds
end

floating_leg_NPV(swap::VanillaSwap) = swap.results.legNPV[2]
floating_leg_BPS(swap::VanillaSwap) = swap.results.legBPS[2]

fixed_leg_BPS(swap::VanillaSwap) = swap.results.legBPS[1]

function fair_rate(swap::VanillaSwap)
  calculate!(swap)

  return swap.results.fairRate
end

# some helper methods #
# function clone(swap::VanillaSwap, pe::PricingEngine = swap.pricingEngine)
#   lazyMixin, res, args = pe == swap.pricingEngine ? (swap.lazyMixin, swap.results, swap.args) : (LazyMixin(), SwapResults(2), VanillaSwapArgs(swap.legs))
#   # args = VanillaSwapArgs(swap.legs)
#   # res = SwapResults(2)
#
#   return VanillaSwap(lazyMixin, swap.swapT, swap.nominal, swap.fixedSchedule, swap.fixedRate, swap.fixedDayCount, swap.iborIndex, swap.spread,
#                     swap.floatSchedule, swap.floatDayCount, swap.paymentConvention, swap.legs, swap.payer, pe, res, args)
# end

function clone(swap::VanillaSwap{ST, DC_fix, DC_float, B, L, P, II}, pe::PricingEngine = swap.pricingEngine, 
              ts::TermStructure = swap.iborIndex.ts) where {ST, DC_fix, DC_float, B, L, P, II}
  # is_new = pe != swap.pricingEngine || ts != swap.iborIndex.ts

  lazyMixin, res, args = pe == swap.pricingEngine ? (swap.lazyMixin, swap.results, swap.args) : (LazyMixin(), SwapResults(2), VanillaSwapArgs(swap.legs))

  # we need a new ibor and to rebuild floating rate coupons
  if ts != swap.iborIndex.ts
    newIbor = clone(swap.iborIndex, ts)
    newLegs = Vector{Leg}(undef, 2)
    newLegs[1] = swap.legs[1]
    newLegs[2] = IborLeg(swap.floatSchedule, swap.nominal, newIbor, swap.floatDayCount, swap.paymentConvention; add_redemption=false)
  else
    newIbor = swap.iborIndex
    newLegs = swap.legs
  end

  return VanillaSwap{ST, DC_fix, DC_float, B, L, typeof(pe), typeof(newIbor)}(lazyMixin,
                    swap.swapT, swap.nominal, swap.fixedSchedule, swap.fixedRate, swap.fixedDayCount, newIbor, swap.spread,
                    swap.floatSchedule, swap.floatDayCount, swap.paymentConvention, newLegs, swap.payer, pe, res, args)
end

get_pricing_engine_type(::VanillaSwap{ST, DC_fix, DC_float, B, L, P, II}) where {ST, DC_fix, DC_float, B, L, P, II} = P

function update_ts_idx!(swap::VanillaSwap, ts::TermStructure)
  typeof(ts) == typeof(swap.iborIndex.ts) || error("Term Structure mismatch for swap between ts and index ts")
  newIborIdx = clone(swap.iborIndex, ts)
  swap.iborIndex = newIborIdx

  # update legs
  for coup in swap.legs[2].coupons
    coup.iborIndex = newIborIdx
  end

  swap.lazyMixin.calculated = false

  return swap
end

function update_ts_pe!(swap::VanillaSwap, ts::TermStructure)
  typeof(ts) == typeof(swap.pricingEngine.yts) || error("Term Structure mismatch for swap between ts and pric engine ts")
  newpe = clone(swap.pricingEngine, ts)
  swap.pricingEngine = newpe

  swap.lazyMixin.calculated = false

  return swap
end

function update_all_ts!(swap::VanillaSwap, ts::TermStructure)
  # this will update the ts of the pricing engine and ibor index
  update_ts_idx!(swap, ts)
  update_ts_pe!(swap, ts)

  return swap
end
