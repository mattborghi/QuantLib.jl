mutable struct BootstrapError{T <: BootstrapHelper, Y <: TermStructure} <: Function
  i::Int
  inst::T
  ts::Y
end

function (be::BootstrapError)(g::Float64)
  update_guess!(be.ts.trait, be.i, be.ts, g)
  QuantLib.Math.update!(be.ts.interp, be.i, g)

  return quote_error(be.inst)
end

quote_error(inst::BondHelper) = QuantLib.value(inst) - implied_quote(inst) # recalculate
quote_error(rate::RateHelper) = QuantLib.value(rate) - implied_quote(rate)
quote_error(rate::AbstractCDSHelper) = QuantLib.value(rate) - implied_quote(rate)

get_pricing_engine(::Discount, yts::YieldTermStructure) = DiscountingBondEngine(yts)

function apply_termstructure(rate::RateHelper, ts::TermStructure)
  newRate = update_termstructure(rate, ts)

  return newRate
end

apply_termstructure(b::BondHelper, ts::TermStructure) = update_termstructure(b, ts)
function apply_termstructure(s::SwapRateHelper, ts::TermStructure)
  newSwapHelper = update_termstructure(s, ts)

  return newSwapHelper
end

function apply_termstructure(cds::AbstractCDSHelper, ts::TermStructure)
  # have to clone
  newCDS = clone(cds, ts)
  reset_engine!(newCDS)

  return newCDS
end

# BOOTSTRAPPING
mutable struct IterativeBootstrap <: Bootstrap
  firstSolver::BrentSolver
  solver::FiniteDifferenceNewtonSafe

  IterativeBootstrap() = new(BrentSolver(), FiniteDifferenceNewtonSafe())
end

# returns initial bootstrap state to Term Structure
function initialize(::IterativeBootstrap, ts::TermStructure)
  # get the intial data based on trait
  data_initial = initial_value(ts.trait)
  n = length(ts.instruments) + 1

  # get a new pricing engine based on type
  # pe = get_pricing_engine(ts.trait, ts)

  # initialize data
  if data_initial == 1.0
    ts.data = ones(n)
  elseif data_initial == 0.0
    ts.data = zeros(n)
  else
    ts.data = fill(data_initial, n)
  end

  # build times and error vectors (which have the functions for the solver)
  ts.times[1] = time_from_reference(ts, ts.referenceDate)
  ts.dates[1] = ts.referenceDate
  @simd for i = 2:n
    @inbounds ts.times[i] = time_from_reference(ts, maturity_date(ts.instruments[i - 1]))
    @inbounds ts.dates[i] = maturity_date(ts.instruments[i - 1])
    # set yield term Structure
    @inbounds ts.instruments[i - 1] = apply_termstructure(ts.instruments[i - 1], ts)
    # set error function
    @inbounds ts.errors[i] = BootstrapError(i, ts.instruments[i - 1], ts)
  end

  # initialize interpolation
  QuantLib.Math.initialize!(ts.interp, ts.times, ts.data)
end

function _calculate!(boot::IterativeBootstrap, ts::TermStructure)
  max_iter = max_iterations(ts.trait)
  valid_data = ts.validCurve

  iterations = 0
  # if we get through this loop, we haven't converged
  while iterations < max_iter
    prev_data = copy(ts.data) # need actual copy, not pointer, to check later for convergence
    for i = 2:length(ts.data)

      # bracket root and calculate guess
      min = min_value_after(ts.trait, i, ts, valid_data)
      max = max_value_after(ts.trait, i, ts, valid_data)
      g = guess(ts.trait, i, ts, valid_data)

      # adjust if needed
      if g >= max
        g = max - (max - min) / 5.0
      elseif (g <= min)
        g = min + (max - min) / 5.0
      end

      if !valid_data
        update_idx = i == length(ts.data) ? 1 : i + 1
        QuantLib.Math.update!(ts.interp, update_idx, ts.data[1])
      end

      # put this in a try / catch
      if !valid_data
        # use first solver
        root = solve(boot.firstSolver, ts.errors[i], ts.accuracy, g, min, max)
      else
        root = solve(boot.solver, ts.errors[i], ts.accuracy, g, min, max)
      end
    end

    # let's check for convergence
    change = abs(ts.data[2] - prev_data[2])
    for i=3:length(ts.data)
      change = max(change, abs(ts.data[i] - prev_data[i]))
    end
    if change <= ts.accuracy
      break # bye
    end

    iterations += 1

    valid_data = true
  end
  ts.validCurve = true

  return ts
end

function bootstrap_error(i::Int, inst::BootstrapHelper, ts::TermStructure)
  function bootstrap_error_inner(g::Float64)
    # update trait
    update_guess!(ts.trait, i, ts, g)
    QuantLib.Math.update!(ts.interp, i, g)
    # qe =
    # if i > 7
    #   println("GUESS: $i : $g")
    #   println("QUOTE ERROR ", qe)
    # end
    return quote_error(inst)
  end

  return bootstrap_error_inner
end
