## TOP LEVEL CALCULATION METHODS - KEEPING TRACK OF CALCULATION STATE ##
function update_pricing_engine(inst::Instrument, pe::PricingEngine)
  T = get_pricing_engine_type(inst)
  if typeof(pe) <: T
    inst.pricingEngine = pe
    inst.lazyMixin.calculated = false
  else
    # we have to clone
    inst = clone(inst, pe)
  end

  return inst
end

function npv(inst::Instrument)
  calculate!(inst)

  return inst.results.value
end

function perform_calculations!(inst::Instrument)
  reset!(inst.results)
  _calculate!(inst.pricingEngine, inst)

  return inst
end

## MISC TYPES ##
struct LongPosition <: PositionType end
struct ShortPosition <: PositionType end
