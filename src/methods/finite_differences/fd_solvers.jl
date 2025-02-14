mutable struct FdmSolverDesc{F <: FdmMesher, C <: FdmInnerValueCalculator}
  mesher::F
  bcSet::FdmBoundaryConditionSet
  condition::FdmStepConditionComposite
  calculator::C
  maturity::Float64
  timeSteps::Int
  dampingSteps::Int
end

## Solvers ##
mutable struct FdmBackwardSolver{F <: FdmSchemeDescType}
  map::FdmLinearOpComposite
  bcSet::FdmBoundaryConditionSet
  condition::FdmStepConditionComposite
  schemeDesc::FdmSchemeDesc{F}
end

function FdmBackwardSolver(map::FdmLinearOpComposite, bcSet::FdmBoundaryConditionSet, schemeDesc::FdmSchemeDesc{F}) where {F <: FdmSchemeDescType}
  condition = FdmStepConditionComposite(Vector{Float64}(), Vector{StepCondition}())

  return FdmBackwardSolver{F}(map, bcSet, condition, schemeDesc)
end

function rollback!(bsolv::FdmBackwardSolver, schemeType::Hundsdorfer, rhs::Vector{Float64}, from::Float64, to::Float64, steps::Int, dampingSteps::Int)
  deltaT = from - to
  allSteps = steps + dampingSteps
  dampingTo = from - (deltaT * dampingSteps) / allSteps

  # if dampingSteps > 0
  #   implicitEvolver = ImplicitEulerScheme(bsolv.map, bsolv.bcSet)
  # end

  dampingSteps == 0 || error("damping steps should be 0")

  hsEvolver = HundsdorferScheme(bsolv.schemeDesc.theta, bsolv.schemeDesc.mu, bsolv.map, bsolv.bcSet)
  hsModel = FiniteDifferenceModel{HundsdorferScheme}(hsEvolver, bsolv.condition.stoppingTimes)
  rollback!(hsModel, rhs, dampingTo, to, steps, bsolv.condition)

  return bsolv, rhs
end

function rollback!(bsolv::FdmBackwardSolver, schemeType::Douglas, rhs::Vector{Float64}, from::Float64, to::Float64, steps::Int, dampingSteps::Int)
  deltaT = from - to
  allSteps = steps + dampingSteps
  dampingTo = from - (deltaT * dampingSteps) / allSteps

  dampingSteps == 0 || error("damping steps should be 0")

  dsEvolver = DouglasScheme(bsolv.schemeDesc.theta, bsolv.map, bsolv.bcSet)
  dsModel = FiniteDifferenceModel{DouglasScheme}(dsEvolver, bsolv.condition.stoppingTimes)
  rollback!(dsModel, rhs, dampingTo, to, steps, bsolv.condition)

  return bsolv, rhs
end

mutable struct Fdm1DimSolver{FS <: FdmSolverDesc, F <: FdmSchemeDescType, FD <: FdmLinearOpComposite} <: LazyObject
  lazyMixin::LazyMixin
  solverDesc::FS
  schemeDesc::FdmSchemeDesc{F}
  op::FD
  thetaCondition::FdmSnapshotCondition
  conditions::FdmStepConditionComposite
  initialValues::Vector{Float64}
  resultValues::Vector{Float64}
  x::Vector{Float64}
  interpolation::NaturalCubicSpline{Float64}

  function Fdm1DimSolver{FS, F, FD}(solverDesc::FS,
                                      schemeDesc::FdmSchemeDesc{F},
                                      op::FD) where {FS, F, FD}
    thetaCondition = FdmSnapshotCondition(0.99 * min(1.0 / 365.0, length(solverDesc.condition.stoppingTimes) == 0 ? solverDesc.maturity : solverDesc.condition.stoppingTimes[1]))
    conditions = join_conditions_FdmStepConditionComposite(thetaCondition, solverDesc.condition)

    layout = solverDesc.mesher.layout

    x = zeros(layout.size)
    initialValues = zeros(layout.size)
    resultValues = zeros(layout.size)

    coords = ones(Int, length(layout.dim))

    for i = 1:layout.size
      initialValues[i], solverDesc.calculator = avg_inner_value(solverDesc.calculator, coords, i, solverDesc.maturity)
      x[i] = get_location(solverDesc.mesher, coords, 1)

      iter_coords!(coords, layout.dim)
    end

    new{FS, F, FD}(LazyMixin(), solverDesc, schemeDesc, op, thetaCondition, conditions, initialValues, resultValues, x)
  end
end

Fdm1DimSolver(solverDesc::FS,
              schemeDesc::FdmSchemeDesc{F},
              op::FD) where {FS <: FdmSolverDesc, F <: FdmSchemeDescType, FD <: FdmLinearOpComposite} =
              Fdm1DimSolver{FS, F, FD}(solverDesc, schemeDesc, op)

mutable struct Fdm2DimSolver{FS <: FdmSolverDesc, F <: FdmSchemeDescType, FD <: FdmLinearOpComposite} <: LazyObject
  lazyMixin::LazyMixin
  solverDesc::FS
  schemeDesc::FdmSchemeDesc{F}
  op::FD
  thetaCondition::FdmSnapshotCondition
  conditions::FdmStepConditionComposite
  initialValues::Vector{Float64}
  resultValues::Matrix{Float64}
  x::Vector{Float64}
  y::Vector{Float64}
  interpolation::BicubicSpline

  function Fdm2DimSolver{FS, F, FD}(solverDesc::FS,
                                      schemeDesc::FdmSchemeDesc{F},
                                      op::FD) where {FS, F, FD}
    thetaCondition = FdmSnapshotCondition(0.99 * min(1.0 / 365.0, length(solverDesc.condition.stoppingTimes) == 0 ? solverDesc.maturity : solverDesc.condition.stoppingTimes[1]))
    conditions = join_conditions_FdmStepConditionComposite(thetaCondition, solverDesc.condition)

    layout = solverDesc.mesher.layout

    initialValues = zeros(layout.size)
    resultValues = zeros(layout.dim[1], layout.dim[2])

    x = zeros(layout.dim[1])
    y = zeros(layout.dim[2])
    x_count = 1
    y_count = 1

    coords = ones(Int, length(layout.dim))

    @inbounds @simd for i = 1:layout.size
      initialValues[i], solverDesc.calculator = avg_inner_value(solverDesc.calculator, coords, i, solverDesc.maturity)

      if coords[2] == 1
        x[x_count] = get_location(solverDesc.mesher, coords, 1)
        x_count += 1
      end

      if coords[1] == 1
        y[y_count] =  get_location(solverDesc.mesher, coords, 2)
        y_count += 1
      end

      iter_coords!(coords, layout.dim)
    end

    return new{FS, F, FD}(LazyMixin(), solverDesc, schemeDesc, op, thetaCondition, conditions, initialValues, resultValues, x, y)
  end
end

Fdm2DimSolver(solverDesc::FS,
              schemeDesc::FdmSchemeDesc{F},
              op::FD) where {FS <: FdmSolverDesc, F <: FdmSchemeDescType, FD <: FdmLinearOpComposite} =
              Fdm2DimSolver{FS, F, FD}(solverDesc, schemeDesc, op)

get_interpolation(solv::Fdm1DimSolver, x::Float64) = solv.interpolation(x)
get_interpolation(solv::Fdm2DimSolver, x::Float64, y::Float64) = solv.interpolation.spline(x, y)

function interpolate_at(solv::Fdm1DimSolver, x::Float64)
  calculate!(solv)
  return get_interpolation(solv, x)
end

function interpolate_at(solv::Fdm2DimSolver, x::Float64, y::Float64)
  calculate!(solv)
  return get_interpolation(solv, x, y)
end

function perform_calculations!(solv::Fdm1DimSolver)
  rhs = copy(solv.initialValues)

  bsolver = FdmBackwardSolver(solv.op, solv.solverDesc.bcSet, solv.conditions, solv.schemeDesc)
  rollback!(bsolver, solv.schemeDesc.schemeType, rhs, solv.solverDesc.maturity, 0.0, solv.solverDesc.timeSteps, solv.solverDesc.dampingSteps)
  solv.resultValues = copy(rhs)
  solv.interpolation = NaturalCubicSpline(solv.x, solv.resultValues)

  return solv
end

function perform_calculations!(solv::Fdm2DimSolver)
  rhs = copy(solv.initialValues)

  bsolver = FdmBackwardSolver(solv.op, solv.solverDesc.bcSet, solv.conditions, solv.schemeDesc)
  rollback!(bsolver, solv.schemeDesc.schemeType, rhs, solv.solverDesc.maturity, 0.0, solv.solverDesc.timeSteps, solv.solverDesc.dampingSteps)
  solv.resultValues = reshape(rhs, length(solv.x), length(solv.y))
  solv.interpolation = BicubicSpline(solv.x, solv.y, solv.resultValues)

  return solv
end

mutable struct FdmG2Solver{FS <: FdmSolverDesc, F <: FdmSchemeDescType} <: LazyObject
  lazyMixin::LazyMixin
  model::G2
  solverDesc::FS
  schemeDesc::FdmSchemeDesc{F}
  solver::Fdm2DimSolver{FS, F, FdmG2Op}

  function FdmG2Solver{FS, F}(model::G2,
                                solverDesc::FS,
                                schemeDesc::FdmSchemeDesc{F}) where {FS, F}
    op = FdmG2Op(solverDesc.mesher, model, 1, 2)
    solver = Fdm2DimSolver{FS, F, FdmG2Op}(solverDesc, schemeDesc, op)
    new{FS, F}(LazyMixin(), model, solverDesc, schemeDesc, solver)
  end
end

FdmG2Solver(model::G2,
            solverDesc::FS,
            schemeDesc::FdmSchemeDesc{F}) where {FS <: FdmSolverDesc, F <: FdmSchemeDescType} =
            FdmG2Solver{FS, F}(model, solverDesc, schemeDesc)

mutable struct FdmHullWhiteSolver{FS <: FdmSolverDesc, F <: FdmSchemeDescType} <: LazyObject
  lazyMixin::LazyMixin
  model::HullWhite
  solverDesc::FS
  schemeDesc::FdmSchemeDesc{F}
  solver::Fdm1DimSolver{FS, F, FdmHullWhiteOp}

  function FdmHullWhiteSolver{FS, F}(model::HullWhite,
                                        solverDesc::FS,
                                        schemeDesc::FdmSchemeDesc{F}) where {FS, F}
    op = FdmHullWhiteOp(solverDesc.mesher, model, 1)
    solver = Fdm1DimSolver{FS, F, FdmHullWhiteOp}(solverDesc, schemeDesc, op)
    new{FS, F}(LazyMixin(), model, solverDesc, schemeDesc, solver)
  end
end

FdmHullWhiteSolver(model::HullWhite, solverDesc::FS, schemeDesc::FdmSchemeDesc{F}) where {FS <: FdmSolverDesc, F <: FdmSchemeDescType} =
                  FdmHullWhiteSolver{FS, F}(model, solverDesc, schemeDesc)

function value_at(solv::FdmG2Solver, x::Float64, y::Float64)
  return interpolate_at(solv.solver, x, y)
end

function value_at(solv::FdmHullWhiteSolver, x::Float64)
  return interpolate_at(solv.solver, x)
end
