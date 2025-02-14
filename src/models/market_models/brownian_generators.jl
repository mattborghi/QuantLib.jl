struct SobolDiagonalOrdering <: SobolOrdering end
struct SobolStepsOrdering <: SobolOrdering end
struct SobolFactorsOrdering <: SobolOrdering end

mutable struct SobolBrownianGenerator{O <: SobolOrdering} <: BrownianGenerator
  factors::Int
  steps::Int
  ordering::O
  generator::SobolInverseCumulativeRSG
  bridge::BrownianBridge
  lastStep::Int
  orderedIndices::Vector{Vector{Int}}
  bridgedVariates::Vector{Vector{Float64}}
end

function SobolBrownianGenerator(factors::Int, steps::Int, ordering::S, ::Int) where {S <: SobolOrdering}
  generator = SobolInverseCumulativeRSG(factors * steps)
  bridge = BrownianBridge(steps)
  orderedIndices = Vector{Int}[Vector{Int}(undef, steps) for _ = 1:factors]
  bridgedVariates = Vector{Float64}[Vector{Float64}(undef, steps) for _ = 1:factors]

  fill_by_ordering!(ordering, orderedIndices, factors, steps)

  return SobolBrownianGenerator{S}(factors, steps, ordering, generator, bridge, 0, orderedIndices, bridgedVariates)
end

function fill_by_ordering!(::SobolDiagonalOrdering, M::Vector{Vector{Int}}, factors::Int, steps::Int)
  # starting position of current diagonal
  i1 = j1 = 1

  # current position
  i = j = 1
  counter = 1
  while counter <= factors * steps
    M[i][j] = counter
    counter += 1
    if i == 1 || j == steps
      # we have completed a diagonal and have to start a new one
      if i1 < factors
        # we have to start path of the next factor
        i1 += 1
        j1 = 1
      else
        # we have to move along the path of the last factor
        i1 = factors
        j1 += 1
      end
      i = i1
      j = j1
    else
      # we move along the diagonal
      i = i - 1
      j = j + 1
    end
  end

  return M
end

function next_path!(sob::SobolBrownianGenerator)
  vals, wgt = next_sequence!(sob.generator)
  @simd for i = 1:sob.factors
    @inbounds transform!(sob.bridge, vals[sob.orderedIndices[i]], sob.bridgedVariates[i])
  end

  sob.lastStep = 1

  return wgt
end

function next_step!(sob::SobolBrownianGenerator, output::Vector{Float64})
  @simd for i = 1:sob.factors
    @inbounds output[i] = sob.bridgedVariates[i][sob.lastStep]
  end
  sob.lastStep += 1

  return 1.0
end

struct SobolBrownianGeneratorFactory{O <: SobolOrdering} <: BrownianGeneratorFactory
  ordering::O
  seed::Int
end

create(sob::SobolBrownianGeneratorFactory, factors::Int, steps::Int) = SobolBrownianGenerator(factors, steps, sob.ordering, sob.seed)

# Clone #
clone(sob::SobolBrownianGenerator) = SobolBrownianGenerator{typeof(sob.ordering)}(sob.factors, sob.steps, sob.ordering, sob.generator,
                                                          sob.bridge, sob.lastStep, deepcopy(sob.orderedIndices), deepcopy(sob.bridgedVariates))
