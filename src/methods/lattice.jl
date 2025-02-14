using LinearAlgebra

struct NullLattice <: Lattice end

mutable struct Branching
  k::Vector{Int}
  probs::Vector{Vector{Float64}}
  kMin::Int
  jMin::Int
  kMax::Int
  jMax::Int
end

function Branching()
  probs = Vector{Vector{Float64}}(undef, 3)
  probs[1] = zeros(0)
  probs[2] = zeros(0)
  probs[3] = zeros(0)
  return Branching(zeros(Int, 0), probs, typemax(Int), typemax(Int), typemin(Int), typemin(Int))
end

mutable struct TrinomialTree{S <: StochasticProcess} <: AbstractTree
  process::S
  timeGrid::TimeGrid
  dx::Vector{Float64}
  branchings::Vector{Branching}
  isPositive::Bool
end

function TrinomialTree(process::S, timeGrid::TimeGrid, isPositive::Bool = false) where {S <: StochasticProcess}
  x0 = process.x0
  dx = zeros(length(timeGrid.times))
  nTimeSteps = length(timeGrid.times) - 1
  jMin = 0
  jMax = 0
  branchings = Vector{Branching}(undef, nTimeSteps)

  for i = 1:nTimeSteps
    t = timeGrid.times[i]
    dt = timeGrid.dt[i]

    # Variance must be independent of x
    v2 = variance(process, t, 0.0, dt)
    v = sqrt(v2)
    dx[i+1] = v * sqrt(3.0)

    branching = Branching()

    @simd for j =jMin:jMax
      @inbounds x = x0 + j * dx[i]
      m = expectation(process, t, x, dt)
      @inbounds temp = round(Int, floor((m - x0) / dx[i+1] + 0.5))

      if isPositive
        @inbounds while (x0 + (temp - 1) * dx[i + 1] <= 0)
          temp += 1
        end
      end

      @inbounds e = m - (x0 + temp * dx[i + 1])
      e2 = e * e
      e3 = e * sqrt(3.0)

      p1 = (1.0 + e2 / v2 - e3 / v) / 6.0
      p2 = (2.0 - e2 / v2) / 3.0
      p3 = (1.0 + e2 / v2 + e3 / v) / 6.0

      add!(branching, temp, p1, p2, p3)
    end

    @inbounds branchings[i] = branching # check if we need copy

    jMin = branching.jMin
    jMax = branching.jMax
  end

  return TrinomialTree{S}(process, timeGrid, dx, branchings, isPositive)
end

function rebuild_tree!(tt::TrinomialTree, timeGrid::TimeGrid)
  x0 = tt.process.x0
  dx = zeros(length(timeGrid.times))
  nTimeSteps = length(timeGrid.times) - 1
  jMin = 0
  jMax = 0
  branchings = Vector{Branching}(undef, nTimeSteps)

  for i = 1:nTimeSteps
    t = timeGrid.times[i]
    dt = timeGrid.dt[i]

    # Variance must be independent of x
    v2 = variance(tt.process, t, 0.0, dt)
    v = sqrt(v2)
    dx[i+1] = v * sqrt(3.0)

    branching = Branching()

    @simd for j =jMin:jMax
      @inbounds x = x0 + j * dx[i]
      m = expectation(tt.process, t, x, dt)
      @inbounds temp = round(Int, floor((m - x0) / dx[i+1] + 0.5))

      if tt.isPositive
        @inbounds while (x0 + (temp - 1) * dx[i + 1] <= 0)
          temp += 1
        end
      end

      @inbounds e = m - (x0 + temp * dx[i + 1])
      e2 = e * e
      e3 = e * sqrt(3.0)

      p1 = (1.0 + e2 / v2 - e3 / v) / 6.0
      p2 = (2.0 - e2 / v2) / 3.0
      p3 = (1.0 + e2 / v2 + e3 / v) / 6.0

      add!(branching, temp, p1, p2, p3)
    end

    @inbounds branchings[i] = branching # check if we need copy

    jMin = branching.jMin
    jMax = branching.jMax
  end
  tt.dx = dx
  tt.timeGrid = timeGrid
  tt.branchings = branchings

  return tt
end

mutable struct TreeLattice1D{T <: TreeLattice} <: TreeLattice
  tg::TimeGrid
  impl::T
  statePrices::Vector{Vector{Float64}}
  n::Int
  statePricesLimit::Int
end

function TreeLattice1D(tg::TimeGrid, n::Int, impl::T) where {T <: TreeLattice}
  statePrices = Vector{Vector{Float64}}(undef, 1)
  statePrices[1] = ones(1)

  statePricesLimit = 1

  return TreeLattice1D{T}(tg, impl, statePrices, n, statePricesLimit)
end

function get_grid(lat::TreeLattice1D, t::Float64)
  i = return_index(lat.tg, t)
  grid = zeros(get_size(lat.impl, i))

  @simd for j in eachindex(grid)
    @inbounds grid[j] = get_underlying(lat.impl, i, j)
  end

  return grid
end

mutable struct TreeLattice2D{T <: TreeLattice} <: TreeLattice
  tg::TimeGrid
  impl::T
  statePrices::Vector{Vector{Float64}}
  n::Int
  statePricesLimit::Int
  tree1::TrinomialTree
  tree2::TrinomialTree
  m::Matrix{Float64}
  rho::Float64
end

function TreeLattice2D(tree1::TrinomialTree, tree2::TrinomialTree, correlation::Float64, impl::T) where {T <: TreeLattice}
  tg = tree1.timeGrid
  statePrices = Vector{Vector{Float64}}(undef, 1)
  statePrices[1] = ones(1)

  statePricesLimit = 1
  branch_num = branches(TrinomialTree)
  n = branch_num ^ 2
  m = zeros(branch_num, branch_num)
  rho = abs(correlation)

  if correlation < 0.0 && branch_num == 3
    m[1,1] = -1.0
    m[2,1] = -4.0
    m[3,1] =  5.0
    m[1,2] = -4.0
    m[2,2] =  8.0
    m[3,2] = -4.0
    m[1,3] =  5.0
    m[2,3] = -4.0
    m[3,3] = -1.0
  else
    m[1,1] =  5.0
    m[2,1] = -4.0
    m[3,1] = -1.0
    m[1,2] = -4.0
    m[2,2] =  8.0
    m[3,2] = -4.0
    m[1,3] = -1.0
    m[2,3] = -4.0
    m[3,3] =  5.0
  end

  return TreeLattice2D{T}(tg, impl, statePrices, n, statePricesLimit, tree1, tree2, m, rho)
end

get_size(tr::TreeLattice2D, i::Int) = get_size(tr.tree1, i) * get_size(tr.tree2, i)

function descendant(tr::TreeLattice2D, i::Int, idx::Int, branch::Int)
  modulo = get_size(tr.tree1, i)
  new_idx = idx - 1
  new_branch = branch - 1

  index1 = (new_idx % modulo) + 1
  index2 = (round(Int, floor(new_idx / modulo))) + 1

  branch1 = (new_branch % branches(TrinomialTree)) + 1
  branch2 = (round(Int, floor(new_branch / branches(TrinomialTree)))) + 1

  modulo = get_size(tr.tree1, i + 1)
  return ((descendant(tr.tree1, i, index1, branch1) - 1) + (descendant(tr.tree2, i, index2, branch2) - 1) * modulo) + 1
end

function probability(tr::TreeLattice2D, i::Int, idx::Int, branch::Int)
  modulo = get_size(tr.tree1, i)
  new_idx = idx - 1
  new_branch = branch - 1

  index1 = (new_idx % modulo) + 1
  index2 = (round(Int, floor(new_idx / modulo))) + 1

  branch1 = (new_branch % branches(TrinomialTree)) + 1
  branch2 = (round(Int, floor(new_branch / branches(TrinomialTree)))) + 1

  # println("$(index1) $(index2) $(branch1) $(branch2) $(idx) $(branch) $(modulo)")

  prob1 = probability(tr.tree1, i, index1, branch1)
  prob2 = probability(tr.tree2, i, index2, branch2)

  # println("$(prob1) $(prob2)")

  return prob1 * prob2 + tr.rho * tr.m[branch2,branch1] / 36.0 # this 36 could depend on the branches(TrinomialTree)
end

function get_state_prices!(t::TreeLattice, i::Int)
  if i > t.statePricesLimit
    compute_state_prices!(t, i)
  end

  return t.statePrices[i]
end

function compute_state_prices!(t::TreeLattice, until::Int)
  @inbounds @simd for i = t.statePricesLimit:until - 1
    push!(t.statePrices, zeros(get_size(t.impl, i + 1)))
    for j = 1:get_size(t.impl, i)
      disc = discount(t.impl, i, j)
      statePrice = t.statePrices[i][j]
      for l = 1:t.n
        t.statePrices[i + 1][descendant(t.impl, i, j, l)] += statePrice * disc * probability(t.impl, i, j, l)
      end
    end
  end

  t.statePricesLimit = until

  return t
end

function initialize!(lattice::TreeLattice, asset::DiscretizedAsset, t::Float64)
  #i = findfirst(lattice.tg.times .>= t)
  i = return_index(lattice.tg, t)
  set_time!(asset, t)
  reset!(asset, get_size(lattice.impl, i))
end

function rollback!(lattice::TreeLattice, asset::DiscretizedAsset, t::Float64)
  partial_rollback!(lattice, asset, t)
  adjust_values!(asset)

  return asset
end

function partial_rollback!(lattice::TreeLattice, asset::DiscretizedAsset, t::Float64)
  from = asset.common.time

  if QuantLib.Math.is_close(from, t)
    return
  end

  # iFrom = findfirst(lattice.tg.times .>= from)
  # iTo = findfirst(lattice.tg.times .>= t)
  iFrom = return_index(lattice.tg, from)
  iTo = return_index(lattice.tg, t)

  @simd for i = iFrom-1:-1:iTo
    newVals = zeros(get_size(lattice.impl, i))
    step_back!(lattice, i, asset.common.values, newVals)
    @inbounds asset.common.time = lattice.tg.times[i]
    asset.common.values = newVals
    # println("newVals before: ", newVals)
    if i != iTo
      adjust_values!(asset)
    end
    # println("newVals after: ", newVals)
  end

  return asset
end

function present_value(lattice::TreeLattice, asset::DiscretizedAsset)
  i = findfirst(lattice.tg.times .>= asset.common.time)
  return dot(asset.common.values, get_state_prices!(lattice, i))
end

function step_back!(lattice::TreeLattice, i::Int, vals::Vector{Float64}, newVals::Vector{Float64})
  # pragma omp parallel for
  for j = 1:get_size(lattice.impl, i)
    val = 0.0
    @simd for l = 1:lattice.n
      @inbounds val += probability(lattice.impl, i, j, l) * vals[descendant(lattice.impl, i, j, l)]
    end
    @inbounds val *= discount(lattice.impl, i, j)
    @inbounds newVals[j] = val
  end

  return newVals
end

get_size(b::Branching) = b.jMax - b.jMin + 1

function add!(branch::Branching, k::Int, p1::Float64, p2::Float64, p3::Float64)
  push!(branch.k, k)
  push!(branch.probs[1], p1)
  push!(branch.probs[2], p2)
  push!(branch.probs[3], p3)

  # maintain invariants
  branch.kMin = min(branch.kMin, k)
  branch.jMin = branch.kMin - 1
  branch.kMax = max(branch.kMax, k)
  branch.jMax = branch.kMax + 1

  return branch
end

descendant(b::Branching, idx::Int, branch::Int) = b.k[idx] - b.jMin - 1 + branch
probability(b::Branching, idx::Int, branch::Int) = b.probs[branch][idx]
branches(::Type{TrinomialTree}) = 3
get_size(t::TrinomialTree, i::Int) = i == 1 ? 1 : get_size(t.branchings[i-1])

function get_underlying(t::TrinomialTree, i::Int, idx::Int)
  if i == 1
    return t.process.x0
  else
    @inbounds return t.process.x0 + (t.branchings[i - 1].jMin + (idx - 1)) * t.dx[i]
  end
end

descendant(t::TrinomialTree, i::Int, idx::Int, branch::Int) = descendant(t.branchings[i], idx, branch)

probability(t::TrinomialTree, i::Int, j::Int, b::Int) = probability(t.branchings[i], j, b)
