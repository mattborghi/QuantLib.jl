using Dates

# Null
struct FdmNullStepCondition <: StepCondition end

apply_to!(cond::FdmNullStepCondition, a::Vector{Float64}, ::Float64) = cond, a

mutable struct FdmDividendHandler{F <: FdmMesher} <: StepCondition
  x::Vector{Float64}
  dividendTimes::Vector{Float64}
  dividendDates::Vector{Date}
  dividends::Vector{Float64}
  mesher::F
  equityDirection::Int
end

function FdmDividendHandler(schedule::DividendSchedule, mesher::F, refDate::Date, dc::DayCount, equityDirection::Int) where {F <: FdmMesher}
  schedLength = length(schedule.dividends)
  dividends = zeros(schedLength)
  dividendDates = Vector{Date}(undef, schedLength)
  dividendTimes = zeros(schedLength)
  x = zeros(mesher.layout.dim[equityDirection])

  @inbounds @simd for i = 1:schedLength
    dividends = amount(schedule.dividends[i])
    dividendDates = date(schedule.dividends[i])
    dividendTimes = year_fraction(dc, refDate, date(schedule.dividends[i]))
  end

  tmp = get_locations(mesher, equityDirection)
  spacing = mesher.layout.spacing[equityDirection]

  @inbounds @simd for i = 1:length(x)
    iter = ((i - 1) * spacing) + 1
    x[i] = exp(tmp[iter])
  end

  return FdmDividendHandler{F}(x, dividendTimes, dividendDates, dividends, mesher, equityDirection)
end

mutable struct FdmAmericanStepCondition{F <: FdmMesher, C <: FdmInnerValueCalculator} <: StepCondition
  mesher::F
  calculator::C
end

mutable struct FdmBermudanStepCondition{F <: FdmMesher, C <: FdmInnerValueCalculator} <: StepCondition
  mesher::F
  calculator::C
  exerciseTimes::Vector{Float64}
end

function FdmBermudanStepCondition(exerciseDates::Vector{Date}, refDate::Date, dc::DayCount, mesher::F, calculator::C) where {F <: FdmMesher, C <: FdmInnerValueCalculator}
  exerciseTimes = zeros(length(exerciseDates))
  for i = 1:length(exerciseTimes)
    exerciseTimes[i] = year_fraction(dc, refDate, exerciseDates[i])
  end

  return FdmBermudanStepCondition{F, C}(mesher, calculator, exerciseTimes)
end

function apply_to!(cond::FdmBermudanStepCondition, a::Vector{Float64}, t::Float64)
  if findfirst(isequal(t), cond.exerciseTimes) != nothing
    layout = cond.mesher.layout
    dims = length(layout.dim)
    coords = ones(Int, dims)

    locations = zeros(dims)

    @inbounds @simd for i = 1:layout.size
      for j = 1:dims
        locations[dims] = get_location(cond.mesher, coords, j)
      end

      innerValue, cond.calculator = inner_value(cond.calculator, coords, i, t)
      if innerValue > a[i]
        a[i] = innerValue
      end

      iter_coords!(coords, cond.mesher.layout.dim)
    end
  end

  return cond, a
end

mutable struct FdmSnapshotCondition <: StepCondition
  t::Float64
  a::Vector{Float64}
end

FdmSnapshotCondition(t::Float64) = FdmSnapshotCondition(t, Vector{Float64}())

function apply_to!(cond::FdmSnapshotCondition, a::Vector{Float64}, t::Float64)
  if cond.t == t
    cond.a = a
  end

  return cond, a
end

mutable struct FdmStepConditionComposite{C <: StepCondition} <: StepCondition
  stoppingTimes::Vector{Float64}
  conditions::Vector{C}
end

# Constructors
function vanilla_FdmStepConditionComposite(cashFlow::DividendSchedule, exercise::Exercise, mesher::FdmMesher, calculator::FdmInnerValueCalculator,
                                          refDate::Date, dc::DayCount)
  stoppingTimes = Vector{Float64}()
  stepConditions = Vector{StepCondition}()

  if length(cashFlow.dividends) > 0
    dividendCondition = FdmDividendHandler(cashFlow, mesher, refDate, dc, 1)
    push!(stepConditions, dividendCondition)
    append!(stoppingTimes, dividendCondition.dividendTimes)
  end

  if isa(exercise, AmericanExercise)
    push!(stepConditions, FdmAmericanStepCondition(mesher, calculator))
  elseif isa(exercise, BermudanExercise)
    bermudanCondition = FdmBermudanStepCondition(exercise.dates, refDate, dc, mesher, calculator)
    push!(stepConditions, bermudanCondition)
    append!(stoppingTimes, bermudanCondition.exerciseTimes)
  end

  return FdmStepConditionComposite(stoppingTimes, stepConditions)
end

function join_conditions_FdmStepConditionComposite(c1::FdmSnapshotCondition, c2::FdmStepConditionComposite)
  stoppingTimes = c2.stoppingTimes
  push!(stoppingTimes, c1.t)

  conditions = Vector{StepCondition}(undef, 2)
  conditions[1] = c2
  conditions[2] = c1

  return FdmStepConditionComposite(stoppingTimes, conditions)
end

function apply_to!(cond::FdmStepConditionComposite, a::Vector{Float64}, t::Float64)
  for c in cond.conditions
    apply_to!(c, a, t)
  end

  return cond, a
end

mutable struct ArrayWrapper <: CurveWrapper
  value::Vector{Float64}
end

get_value(wrapper::ArrayWrapper, ::Vector{Float64}, idx::Int) = wrapper.value[idx]

mutable struct PayoffWrapper{P <: StrikedTypePayoff} <: CurveWrapper
  payoff::P
end

struct AmericanStepConditionType <: StepType end

mutable struct CurveDependentStepCondition{T <: StepType, C <: CurveWrapper} <: StepCondition
  stepType::T
  curveItem::C
end

const AmericanStepCondition{C} =  CurveDependentStepCondition{AmericanStepConditionType, C}

build_AmericanStepCondition(intrinsicValues::Vector{Float64}) = CurveDependentStepCondition{AmericanStepConditionType, ArrayWrapper}(AmericanStepConditionType(), ArrayWrapper(intrinsicValues))

apply_to_value(::AmericanStepCondition, current::Float64, intrinsic::Float64) = max(current, intrinsic)

function apply_to!(cond::CurveDependentStepCondition, a::Vector{Float64}, ::Float64)
  @simd for i in eachindex(a)
    @inbounds a[i] = apply_to_value(cond, a[i], get_value(cond, a, i))
  end

  return cond, a
end

get_value(cond::CurveDependentStepCondition, a::Vector{Float64}, idx::Int) = get_value(cond.curveItem, a, idx)

mutable struct StepConditionSet{C <: StepCondition} <: StepCondition
  conditions::Vector{C}
end

function apply_to!(cond::StepConditionSet, a::Vector{Vector{Float64}}, t::Float64)
  for i in eachindex(cond.conditions)
    apply_to!(cond.conditions[i], a[i], t)
  end

  return cond, a
end
