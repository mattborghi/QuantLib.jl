struct VolatilityBumpInstrumentJacobianSwaption
  startIndex::Int
  endIndex::Int
end

struct VolatilityBumpInstrumentJacobianCap
  startIndex::Int
  endIndex::Int
  strike::Float64
end

mutable struct VolatilityBumpInstrumentJacobian
  bumps::VegaBumpCollection
  swaptions::Vector{VolatilityBumpInstrumentJacobianSwaption}
  caps::Vector{VolatilityBumpInstrumentJacobianCap}
  computed::BitArray{1}
  allComputed::Bool
  derivatives::Vector{Vector{Float64}}
  onePercentBumps::Vector{Vector{Float64}}
  bumpMatrix::Matrix{Float64}
end

function VolatilityBumpInstrumentJacobian(bumps::VegaBumpCollection,
                                          swaptions::Vector{VolatilityBumpInstrumentJacobianSwaption},
                                          caps::Vector{VolatilityBumpInstrumentJacobianCap})

  swaptionsPlusCaps = length(swaptions) + length(caps)
  computed = falses(swaptionsPlusCaps)
  derivatives = [zeros(number_of_bumps(bumps)) for _ = 1:swaptionsPlusCaps]
  bumpMatrix = zeros(swaptionsPlusCaps, number_of_bumps(bumps))

  onePercentBumps = deepcopy(derivatives)
  allComputed = false

  return VolatilityBumpInstrumentJacobian(bumps, swaptions, caps, computed, allComputed, derivatives, onePercentBumps, bumpMatrix)
end

get_input_bumps(voljacobian::VolatilityBumpInstrumentJacobian) = voljacobian.bumps

function derivatives_volatility!(voljacobian::VolatilityBumpInstrumentJacobian, j::Int)
  j <= length(voljacobian.swaptions) + length(voljacobian.caps) || error("too high index passed to derivatives_volatility")

  if voljacobian.computed[j]
    return voljacobian.derivatives[j]
  end

  resize!(voljacobian.derivatives[j], number_of_bumps(voljacobian.bumps))
  resize!(voljacobian.onePercentBumps[j], number_of_bumps(voljacobian.bumps))

  sizesq = 0.0
  voljacobian.computed[j] = true

  initj = j

  if j <= length(voljacobian.swaptions)
    # it's a swaption
    thisPseudo = SwaptionPseudoDerivative(associated_model(voljacobian.bumps), voljacobian.swaptions[j].startIndex, voljacobian.swaptions[j].endIndex)

    @inbounds @simd for k = 1:number_of_bumps(voljacobian.bumps)
      v = 0.0
      for i = voljacobian.bumps.allBumps[k].stepBegin:voljacobian.bumps.allBumps[k].stepEnd
        fullDerivative = thisPseudo.volatilityDerivatives[i]
        for f = voljacobian.bumps.allBumps[k].factorBegin:voljacobian.bumps.allBumps[k].factorEnd, r = voljacobian.bumps.allBumps[k].rateBegin:voljacobian.bumps.allBumps[k].rateEnd
          v += fullDerivative[r, f]
        end
      end

      voljacobian.derivatives[j][k] = v
      sizesq += v * v
    end
  else
    # it's a cap
    j -= length(voljacobian.swaptions) # need to get back to index 1

    thisPseudo = CapPseudoDerivative(associated_model(voljacobian.bumps), voljacobian.caps[j].strike, voljacobian.caps[j].startIndex, voljacobian.caps[j].endIndex, 1.0)

    @inbounds @simd for k = 1:number_of_bumps(voljacobian.bumps)
      v = 0.0
      for i = voljacobian.bumps.allBumps[k].stepBegin:voljacobian.bumps.allBumps[k].stepEnd
        fullDerivative = thisPseudo.volatilityDerivatives[i]
        for f = voljacobian.bumps.allBumps[k].factorBegin:voljacobian.bumps.allBumps[k].factorEnd, r = voljacobian.bumps.allBumps[k].rateBegin:voljacobian.bumps.allBumps[k].rateEnd
          v += fullDerivative[r, f]
        end
      end

      sizesq += v * v
      voljacobian.derivatives[initj][k] = v
    end
  end

  @simd for k = 1:number_of_bumps(voljacobian.bumps)
    @inbounds voljacobian.bumpMatrix[initj, k] = voljacobian.onePercentBumps[initj][k] = 0.01 * voljacobian.derivatives[initj][k] / sizesq
  end

  return voljacobian.derivatives[initj]
end

function get_all_one_percent_bumps!(voljacobian::VolatilityBumpInstrumentJacobian)
  if ~voljacobian.allComputed
    @simd for i = 1:length(voljacobian.swaptions) + length(voljacobian.caps)
      @inbounds derivatives_volatility!(voljacobian, i)
    end
  end

  voljacobian.allComputed = true

  return voljacobian.bumpMatrix
end


mutable struct OrthogonalizedBumpFinder
  derivativesProducer::VolatilityBumpInstrumentJacobian
  multiplierCutoff::Float64
  tolerance::Float64
end

OrthogonalizedBumpFinder(bumps::VegaBumpCollection,
                        swaptions::Vector{VolatilityBumpInstrumentJacobianSwaption},
                        caps::Vector{VolatilityBumpInstrumentJacobianCap},
                        multiplierCutoff::Float64,
                        tolerance::Float64) = OrthogonalizedBumpFinder(VolatilityBumpInstrumentJacobian(bumps, swaptions, caps), multiplierCutoff, tolerance)


function get_vega_bumps!(obf::OrthogonalizedBumpFinder, theBumps::Vector{Vector{Matrix{Float64}}})
 # todo

  projector = OrthogonalProjection(get_all_one_percent_bumps!(obf.derivativesProducer), obf.multiplierCutoff, obf.tolerance)
  numberRestrictedBumps = projector.numberValidVectors
  marketmodel = associated_model(get_input_bumps(obf.derivativesProducer))
  evolution = marketmodel.evolution

  numberSteps = number_of_steps(evolution)
  numberRates = evolution.numberOfRates
  factors = marketmodel.numberOfFactors

  resize!(theBumps, numberSteps)

  modelMatrix = zeros(numberRates, factors)

  @simd for i in eachindex(theBumps)
    @inbounds theBumps[i] = Matrix[copy(modelMatrix) for i = 1:numberRestrictedBumps]
  end

  # for i = 1:numberSteps, j = 1:numberRestrictedBumps
  #   theBumps[i][j] = copy(modelMatrix)
  # end

  bumpClusters = get_input_bumps(obf.derivativesProducer).allBumps

  bumpIndex = 1
  @inbounds @simd for inst in eachindex(projector.validVectors)
    if projector.validVectors[inst]
      for cluster in eachindex(bumpClusters)
        magnitude = get_vector(projector, inst)[cluster]
        for s = bumpClusters[cluster].stepBegin:bumpClusters[cluster].stepEnd, r = bumpClusters[cluster].rateBegin:bumpClusters[cluster].rateEnd, factor = bumpClusters[cluster].factorBegin:bumpClusters[cluster].factorEnd
          theBumps[s][bumpIndex][r, factor] = magnitude
        end
      end
      bumpIndex += 1
    end
  end
  return theBumps
end
