## ONE FACTOR MODELS ##
mutable struct OneFactorShortRateTree{S <: ShortRateDynamics, T <: TrinomialTree} <: ShortRateTree
  tree::T
  dynamics::S
  tg::TimeGrid
  treeLattice::TreeLattice1D{OneFactorShortRateTree{S, T}}

  function OneFactorShortRateTree{S, T}(tree::T, dynamics::S, tg::TimeGrid) where {S, T}
    oneFactorTree = new{S, T}(tree, dynamics, tg)
    oneFactorTree.treeLattice = TreeLattice1D(tg, get_size(tree, 2), oneFactorTree)

    return oneFactorTree
  end
end

function rebuild_lattice!(lattice::OneFactorShortRateTree, tg::TimeGrid)
  println(lattice.tg)
  rebuild_tree!(lattice.tree, tg)
  lattice.tg = tg

  # update treeLattice
  lattice.treeLattice = TreeLattice1D(tg, get_size(lattice.tree, 2), lattice)
  return lattice
end

get_size(tr::OneFactorShortRateTree, i::Int) = get_size(tr.tree, i)

function discount(tr::OneFactorShortRateTree, i::Int, idx::Int)
  x = get_underlying(tr.tree, i, idx)
  # r = 1.0
  # try
  r = short_rate(tr.dynamics, tr.tg.times[i], x)
  # catch e
  #   println(e)
  #   println(i)
  #   println(tr.dynamics.fitting.values)
  #   error("DIE")
  # end
  return exp(-r * tr.tg.dt[i])
end

descendant(tr::OneFactorShortRateTree, i::Int, idx::Int, branch::Int) = descendant(tr.tree, i, idx, branch)
probability(tr::OneFactorShortRateTree, i::Int, idx::Int, branch::Int) = probability(tr.tree, i, idx, branch)

get_params(m::OneFactorModel) = Float64[get_a(m), get_sigma(m)]

struct RStarFinder{M <: ShortRateModel} <: Function
  model::M
  strike::Float64
  maturity::Float64
  valueTime::Float64
  fixedPayTimes::Vector{Float64}
  amounts::Vector{Float64}
end

function (rsf::RStarFinder)(x::Float64)
  _value = rsf.strike
  _B = discount_bond(rsf.model, rsf.maturity, rsf.valueTime, x)
  sz = length(rsf.fixedPayTimes)
  @simd for i = 1:sz
    @inbounds dbVal = discount_bond(rsf.model, rsf.maturity, rsf.fixedPayTimes[i], x) / _B
    @inbounds _value -= rsf.amounts[i] * dbVal
  end

  return _value
end

# function operator(rsf::RStarFinder)
#   function _inner(x::Float64)
#     _value = rsf.strike
#     _B = discount_bond(rsf.model, rsf.maturity, rsf.valueTime, x)
#     sz = length(rsf.fixedPayTimes)
#     for i = 1:sz
#       dbVal = discount_bond(rsf.model, rsf.maturity, rsf.fixedPayTimes[i], x) / _B
#       _value -= rsf.amounts[i] * dbVal
#     end
#
#     return _value
#   end
#
#   return _inner
# end

discount_bond(model::OneFactorModel, tNow::Float64, maturity::Float64, factors::Vector{Float64}) = discount_bond(model, tNow, maturity, factors[1])
discount_bond(model::OneFactorModel, tNow::Float64, maturity::Float64, _rate::Float64) = A(model, tNow, maturity) * exp(-B(model, tNow, maturity) * _rate)
