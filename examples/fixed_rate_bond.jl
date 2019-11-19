using QuantLib
using Dates

settlement_date = Date(2008, 9, 18) # construct settlement date
# settings is a global singleton that contains global settings
# Defined in QuantLib.jl, here we set its evaluation date attribute
set_eval_date!(settings, settlement_date - Dates.Day(3))

# settings that we will need to construct the yield curve

# Define the frequency as Semiannual
freq = QuantLib.Time.Semiannual()
# Define the tenor given a certain frequency
tenor = QuantLib.Time.TenorPeriod(freq)
conv = QuantLib.Time.Unadjusted()
conv_depo = QuantLib.Time.ModifiedFollowing()
rule = QuantLib.Time.DateGenerationBackwards()
calendar = QuantLib.Time.USGovernmentBondCalendar()
dc_depo = QuantLib.Time.Actual365()
dc = QuantLib.Time.ISDAActualActual()
dc_bond = QuantLib.Time.ISMAActualActual()
fixing_days = 3

# build depos
depo_rates = [0.0096, 0.0145, 0.0194]
depo_tens = [Dates.Month(3), Dates.Month(6), Dates.Month(12)]

# build bonds
issue_dates = [Date(2005, 3, 15), Date(2005, 6, 15), Date(2006, 6, 30), Date(2002, 11, 15),
              Date(1987, 5, 15)]
mat_dates = [Date(2010, 8, 31), Date(2011, 8, 31), Date(2013, 8, 31), Date(2018, 8, 15),
            Date(2038, 5, 15)]

coupon_rates = [0.02375, 0.04625, 0.03125, 0.04000, 0.04500]
market_quotes = [100.390625, 106.21875, 100.59375, 101.6875, 102.140625]

# construct the deposit and fixed rate bond helpers
insts = Vector{BootstrapHelper}(undef, length(depo_rates) + length(issue_dates))
for i = 1:length(depo_rates)
  depo_quote = Quote(depo_rates[i])
  depo_tenor = QuantLib.Time.TenorPeriod(depo_tens[i])
  depo = DepositRateHelper(depo_quote, depo_tenor, fixing_days, calendar, conv_depo, true, dc_depo)
  insts[i] = depo
end

for i =1:length(coupon_rates)
  term_date = mat_dates[i]
  rate = coupon_rates[i]
  issue_date = issue_dates[i]
  market_quote = market_quotes[i]
  sched = QuantLib.Time.Schedule(issue_date, term_date, tenor, conv, conv, rule, true)
  bond = FixedRateBondHelper(Quote(market_quote), FixedRateBond(3, 100.0, sched, rate, dc_bond, conv,
                            100.0, issue_date, calendar, DiscountingBondEngine()))
  insts[i + length(depo_rates)] = bond
end

# Construct the Yield Curve
interp = QuantLib.Math.LogLinear()
trait = Discount()
bootstrap = IterativeBootstrap()
yts = PiecewiseYieldCurve(settlement_date, insts, dc, interp, trait, 0.00000000001, bootstrap)

# Build it
calculate!(yts)

# Build our Fixed Rate Bond
settlement_days = 3
face_amount = 100.0

fixed_schedule = QuantLib.Time.Schedule(Date(2007, 5, 15), Date(2017, 5, 15),
                QuantLib.Time.TenorPeriod(QuantLib.Time.Semiannual()), QuantLib.Time.Unadjusted(),
                QuantLib.Time.Unadjusted(), QuantLib.Time.DateGenerationBackwards(), false,
                QuantLib.Time.USGovernmentBondCalendar())

pe = DiscountingBondEngine(yts)

fixedrate_bond = FixedRateBond(settlement_days, face_amount, fixed_schedule, 0.045,
                  QuantLib.Time.ISMAActualActual(), QuantLib.Time.ModifiedFollowing(), 100.0,
                  Date(2007, 5, 15), fixed_schedule.cal, pe)

# Calculate NPV
npv(fixedrate_bond) # 107.66828913260542
