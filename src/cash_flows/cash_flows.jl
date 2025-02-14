# cash_flows.jl
# module CF

using QuantLib.Time, QuantLib.Math

# BlackIborCouponPricer() = BlackIborCouponPricer(0.0, 0.0, false)

mutable struct CouponMixin{DC <: DayCount}
  accrualStartDate::Date
  accrualEndDate::Date
  refPeriodStart::Date
  refPeriodEnd::Date
  dc::DC
  accrualPeriod::Float64
end

accrual_start_date(coup::Coupon) = coup.couponMixin.accrualStartDate
accrual_end_date(coup::Coupon) = coup.couponMixin.accrualEndDate
ref_period_start(coup::Coupon) = coup.couponMixin.refPeriodStart
ref_period_end(coup::Coupon) = coup.couponMixin.refPeriodEnd
get_dc(coup::Coupon) = coup.couponMixin.dc

# accural_period{C <: Coupon}(coup::C) = coup.couponMixin.accrualPeriod
accrual_period!(coup::Coupon, val::Float64) = coup.couponMixin.accrualPeriod = val
function accrual_period(coup::Coupon)
  if coup.couponMixin.accrualPeriod == -1.0
    p = year_fraction(get_dc(coup), accrual_start_date(coup), accrual_end_date(coup), ref_period_start(coup), ref_period_end(coup))
    accrual_period!(coup, p)
  end

  return coup.couponMixin.accrualPeriod
end

## types of cash flows ##
struct SimpleCashFlow <: CashFlow
  amount::Float64
  date::Date
end

amount(cf::SimpleCashFlow) = cf.amount
date(cf::SimpleCashFlow) = cf.date
date_accrual_end(cf::SimpleCashFlow) = cf.date

date(coup::Coupon) = coup.paymentDate
date_accrual_end(coup::Coupon) = accrual_end_date(coup)

struct Dividend <: CashFlow
  amount::Float64
  date::Date
end

amount(div::Dividend) = div.amount
date(div::Dividend) = div.date
date_accrual_end(div::Dividend) = div.date

# legs to build cash flows

struct ZeroCouponLeg <: Leg
  redemption::SimpleCashFlow
end

## Function wrapper for solvers ##
mutable struct IRRFinder{L <: Leg, DC <: DayCount, C <: CompoundingType, F <: Frequency} <: Function
  leg::L
  npv::Float64
  dc::DC
  comp::C
  freq::F
  includeSettlementDateFlows::Bool
  settlementDate::Date
  npvDate::Date
end

function (finder::IRRFinder)(y::Float64)
  yld = InterestRate(y, finder.dc, finder.comp, finder.freq)
  # @code_warntype npv(finder.leg, yld, finder.includeSettlementDateFlows, finder.settlementDate, finder.npvDate)
  NPV = npv(finder.leg, yld, finder.includeSettlementDateFlows, finder.settlementDate, finder.npvDate)
  return finder.npv - NPV
end

function (finder::IRRFinder)(y::Float64, ::Derivative)
  yld = InterestRate(y, finder.dc, finder.comp, finder.freq)
  return duration(ModifiedDuration(), finder.leg, yld, finder.dc, finder.includeSettlementDateFlows, finder.settlementDate, finder.npvDate)
end

## this function can pass itself or its derivative ##
function operator(finder::IRRFinder)
  function _inner(y::Float64)
    yld = InterestRate(y, finder.dc, finder.comp, finder.freq)
    NPV = npv(finder.leg, yld, finder.includeSettlementDateFlows, finder.settlementDate, finder.npvDate)
    return finder.npv - NPV
  end

  # derivative
  function _inner(y::Float64, ::Derivative)
    yld = InterestRate(y, finder.dc, finder.comp, finder.freq)
    return duration(ModifiedDuration(), finder.leg, yld, finder.dc, finder.includeSettlementDateFlows, finder.settlementDate, finder.npvDate)
  end

  return _inner
end

get_latest_coupon(leg::Leg) = get_latest_coupon(leg, leg.coupons[end])
get_latest_coupon(leg::Leg, simp::SimpleCashFlow) = leg.coupons[end - 1]
get_latest_coupon(leg::Leg, coup::Coupon) = coup

check_coupon(x::CashFlow) = isa(x, Coupon)

get_pay_dates(coups::Vector{C}) where {C <: Coupon} = Date[date(coup) for coup in coups]

get_reset_dates(coups::Vector{C}) where {C <: Coupon} = Date[accrual_start_date(coup) for coup in coups]

## NPV METHODS ##
function _npv_reduce(coup::Coupon, yts::YieldTermStructure, settlement_date::Date)
  if has_occurred(coup, settlement_date)
    return 0.0
  end
  return amount(coup) * discount(yts, date(coup))
end

function npv(leg::Leg, yts::YieldTermStructure, settlement_date::Date, npv_date::Date)
  # stuff
  if length(leg.coupons) == 0
    return 0.0
  end

  totalNPV = mapreduce(x -> _npv_reduce(x, yts, settlement_date), +, leg)

  # redemption
  if leg.redemption != nothing
    totalNPV += amount(leg.redemption) * discount(yts, date(leg.redemption))
  end
  return totalNPV / discount(yts, npv_date)
end

function npv(leg::Leg, y::InterestRate, include_settlement_cf::Bool, settlement_date::Date, npv_date::Date)
  if length(leg.coupons) == 0
    return 0.0
  end

  totalNPV = 0.0
  discount_ = 1.0
  last_date = npv_date

  for cp in leg
    if has_occurred(cp, settlement_date)
      continue
    end
    coupon_date = date(cp)
    amount_ = amount(cp)

    ref_start_date = ref_period_start(cp)
    ref_end_date = ref_period_end(cp)

    b = discount_factor(y, last_date, coupon_date, ref_start_date, ref_end_date)

    discount_ *= b
    last_date = coupon_date

    totalNPV += amount_ * discount_
  end

  # redemption
  if leg.redemption != nothing
    if ~has_occurred(leg.redemption, settlement_date)
      redempt_date = date(leg.redemption)
      if last_date == npv_date
        ref_start_date = redempt_date - Dates.Year(1)
      else
        ref_start_date = last_date
      end
      ref_end_date = redempt_date

      amount_ = amount(leg.redemption)
      b = discount_factor(y, last_date, redempt_date, ref_start_date, ref_end_date)
      discount_ *= b
      totalNPV += amount_ * discount_
    end
  end
  # now we return total npv
  # println(totalNPV)
  return totalNPV
end

function npv(leg::ZeroCouponLeg, yts::YieldTermStructure, settlement_date::Date, npv_date::Date)
  if amount(leg.redemption) == 0.0
    return 0.0
  end

  totalNPV = amount(leg.redemption) * discount(yts, date(leg.redemption))
  return totalNPV / discount(yts, npv_date)
end

function npv(leg::ZeroCouponLeg, y::InterestRate, include_settlement_cf::Bool, settlement_date::Date, npv_date::Date)
  if amount(leg.redemption) == 0.0
    return 0.0
  end

  redempt_date = date(leg.redemption)

  ref_start_date = redempt_date - Dates.Year(1)
  ref_end_date = redempt_date

  discount_ = discount_factor(y, npv_date, redempt_date, ref_start_date, ref_end_date)

  totalNPV = amount(leg.redemption) * discount_

  return totalNPV
end

function npvbps(leg::L, yts::YieldTermStructure, settlement_date::Date, npv_date::Date, includeSettlementDateFlows::Bool = true) where {L <: Leg}
  npv = 0.0
  bps = 0.0


  for cp in leg
    if has_occurred(cp, settlement_date, includeSettlementDateFlows)
      continue
    end

    df = discount(yts, date(cp))
    npv += amount(cp) * df
    # if isa(cp, Coupon)
    bps += cp.nominal * accrual_period(cp) * df
    # end
  end
  # redemption is present
  if leg.redemption != nothing
    if ~has_occurred(leg.redemption, settlement_date, includeSettlementDateFlows)
      df = discount(yts, date(leg.redemption))
      npv += amount(leg.redemption) * df
    end
  end
  d = discount(yts, npv_date)
  npv /= d
  bps = BASIS_POINT * bps / d

  return npv, bps
end

## Duration Calculations ##
modified_duration_calc(::SimpleCompounding, c::Float64, B::Float64, t::Float64, ::Float64, ::Frequency) = c * B * B * t
modified_duration_calc(::CompoundedCompounding, c::Float64, B::Float64, t::Float64, r::Float64, N::Frequency) = c * t * B / (1 + r / QuantLib.Time.value(N))
modified_duration_calc(::ContinuousCompounding, c::Float64, B::Float64, t::Float64, ::Float64, ::Frequency) = c * B * t
modified_duration_calc(::SimpleThenCompounded, c::Float64, B::Float64, t::Float64, r::Float64, N::Frequency) =
  t <= 1.0 / N ? modified_duration_calc(Simple(), c, B, t, r, N) : modified_duration_calc(CompoundedCompounding(), c, B, t, r, N)

function duration(::ModifiedDuration, leg::Leg, y::InterestRate, dc::DayCount, include_settlement_cf::Bool, settlement_date::Date, npv_date::Date = Date(0))
  if (length(leg.coupons) == 0 && (leg.redemption == nothing)) # TODO make this applicable to redemption too
    return 0.0
  end

  if npv_date == Date(0)
    npv_date = settlement_date
  end

  P = 0.0
  t = 0.0
  dPdy = 0.0
  r = y.rate
  N = y.freq
  last_date = npv_date

  for cp in leg
    if has_occurred(cp, settlement_date)
      continue
    end

    c = amount(cp)
    coupon_date = date(cp)
    ref_start_date = ref_period_start(cp)
    ref_end_date = ref_period_end(cp)
    t += year_fraction(dc, last_date, coupon_date, ref_start_date, ref_end_date)

    B = discount_factor(y, t)
    P += c * B

    dPdy -= modified_duration_calc(y.comp, c, B, t, r, N)

    last_date = coupon_date
  end

  if leg.redemption != nothing
    if ~has_occurred(leg.redemption, settlement_date)
      c = amount(leg.redemption)
      coupon_date = date(leg.redemption)
      if last_date == npv_date
        ref_start_date = coupon_date - Dates.Year(1)
      else
        ref_start_date = last_date
      end
      ref_end_date = coupon_date

      t += year_fraction(dc, last_date, coupon_date, ref_start_date, ref_end_date)

      B = discount_factor(y, t)
      P += c * B

      dPdy -= modified_duration_calc(y.comp, c, B, t, r, N)
    end
  end

  if P == 0.0
    return 0.0 # no cashflows
  end

  return -dPdy / P # reverse derivative sign
end

function duration(::ModifiedDuration, leg::ZeroCouponLeg, y::InterestRate, dc::DayCount, include_settlement_cf::Bool, settlement_date::Date, npv_date::Date = Date(0))
  if amount(leg.redemption) == 0.0 || has_occurred(leg.redemption, settlement_date)
    return 0.0
  end

  redempt_date = date(leg.redemption)

  if npv_date == Date(0)
    npv_date = settlement_date
  end

  r = y.rate
  N = y.freq
  c = amount(leg.redemption)

  ref_start_date = redempt_date - Dates.Year(1)
  ref_end_date = redempt_date

  t = year_fraction(dc, npv_date, redempt_date, ref_start_date, ref_end_date)

  B = discount_factor(y, t)
  P = c * B

  dPdy = modified_duration_calc(y.comp, c, B, t, r, N)

  if P == 0.0
    return 0.0
  end

  return -dPdy / P # reverse derivative sign
end

function aggregate_rate(cf::Leg, _first::Int, _last::Int)
  if cf.coupons[_first] == cf.coupons[_last]
    return 0.0
  end

  _next_cf = cf.coupons[_first]
  paymentDate = date(_next_cf)
  result = 0.0
  i = _first
  while i < length(cf.coupons) && date(_next_cf) == paymentDate
    # if isa(_next_cf, Coupon)
    result += calc_rate(_next_cf)
    # end

    i += 1
    _next_cf = cf.coupons[i]
  end

  return result
end


# functions for sorting and finding
sort_cashflow(cf::Coupon) = accrual_end_date(cf) #cf.couponMixin.accrualEndDate
sort_cashflow(simp::SimpleCashFlow) = simp.date

prev_cf(cf::Coupon, d::Date) = d > cf.paymentDate
prev_cf(simp::SimpleCashFlow, d::Date) = d > simp.date

next_cf(cf::Coupon, d::Date) = d < cf.paymentDate
next_cf(simp::SimpleCashFlow, d::Date) = d < simp.date

function previous_cashflow_date(cf::Leg, settlement_date::Date)
  # right now we can assume cashflows are sorted by date because of schedule
  prev_cashflow_idx = findprev(prev_cf, cf.coupons, length(cf.coupons), settlement_date)

  return prev_cashflow_idx == 0 ? 0 : cf.coupons[prev_cashflow_idx].paymentDate
end

function accrual_days(cf::CashFlows, dc::DayCount, settlement_date::Date)
  last_payment = previous_cashflow_date(cf, settlement_date)

  if last_payment == 0
    return 0.0
  else
    return day_count(dc, last_payment, settlement_date)
  end
end

function next_cashflow(cf::Leg, settlement_date::Date)
  if settlement_date > date(cf.coupons[end])
    return length(cf.coupons)
  end

  return findnext(next_cf, cf.coupons, 1, settlement_date)
end

function next_coupon_rate(cf::Leg, settlement_date::Date)
  next_cf_idx = next_cashflow(cf, settlement_date)
  return aggregate_rate(cf, next_cf_idx, length(cf.coupons))
end

function accrued_amount(cf::Leg, settlement_date::Date, include_settlement_cf::Bool = false)
  next_cf_idx = next_cashflow(cf, settlement_date)
  if cf.coupons[next_cf_idx] == length(cf.coupons)
    return 0.0
  end

  _next_cf = cf.coupons[next_cf_idx]
  paymentDate = date(_next_cf)
  result = 0.0
  i = next_cf_idx
  while i < length(cf.coupons) && date(_next_cf) == paymentDate
    result += accrued_amount(_next_cf, settlement_date)
    i += 1
    _next_cf = cf.coupons[i]
  end

  return result
end

accrued_amount(cf::ZeroCouponLeg, ::Date, ::Bool= false) = 0.0
accrued_amount(simp::SimpleCashFlow, ::Date, ::Bool = false) = 0.0

# accrual_period!{C <: Coupon}(coup::C, p::Float64) = coup.accrualPeriod = p
# function accrual_period{C <: Coupon}(coup::C)
#   if accrual_period(coup) == -1.0
#     p = year_fraction(get_dc(coup), accrual_start_date(coup), accrual_end_date(coup), ref_period_start(coup), ref_period_end(coup))
#     accrual_period!(coup, p)
#   end
#
#   return p
# end

function has_occurred(cf::CashFlow, ref_date::Date, include_settlement_cf::Bool = true)
  # will need to expand this
  if ref_date < date(cf) || (ref_date == date(cf) && include_settlement_cf)
    return false
  else
    return true
  end
end

function maturity_date(leg::Leg)
  # sort cashflows
  if leg.redemption != nothing
    return date_accrual_end(leg.redemption)
  else
    sorted_cf = sort(leg.coupons, by=sort_cashflow)
    return date_accrual_end(sorted_cf[end])
  end
end

# Yield Calculations ##
function yield(leg::Leg, npv::Float64, dc::DayCount, compounding::CompoundingType, freq::Frequency, include_settlement_cf::Bool, settlement_date::Date,
              npv_date::Date, accuracy::Float64, max_iter::Int, guess::Float64)
  solver = NewtonSolver(max_iter)
  obj_fun = IRRFinder(leg, npv, dc, compounding, freq, include_settlement_cf, settlement_date, npv_date)
  return solve(solver, obj_fun, accuracy, guess, guess / 10.0)
end

## ITERATORS ##
# this is to iterate through cash flows and redemption
# Base.start(f::FixedRateLeg) = 1
# function Base.next(f::FixedRateLeg, state)
#   if state > length(f.coupons)
#     f.redemption, state + 1
#   else
#     f.coupons[state], state + 1
#   end
# end
#
# Base.done(f::FixedRateLeg, state) = length(f.coupons) + 1 < state

# Base.start(f::Leg) = 1
# Base.next(f::Leg, state) = f.coupons[state], state + 1
# Base.done(f::Leg, state) = length(f.coupons) == state - 1

function Base.iterate(f::Leg, state=1)
  if length(f.coupons) == state - 1
      return nothing
  end

  return f.coupons[state], state + 1
end

Base.getindex(f::Leg, i::Int) = f.coupons[i]
Base.lastindex(f::Leg) = lastindex(f.coupons)
# end
