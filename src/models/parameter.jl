# call{P <: Parameter}(param::P, t::Float64) = value(param, t)

mutable struct ConstantParameter{C <: Constraint} <: Parameter
  data::Vector{Float64}
  constraint::C
end

get_data(c::ConstantParameter) = c.data
set_params!(c::ConstantParameter, i::Int, val::Float64) = c.data[i] = val
# call(c::ConstantParameter, t::Float64) = value(c, t)

mutable struct G2FittingParameter{T <: TermStructure} <: Parameter
  a::Float64
  sigma::Float64
  b::Float64
  eta::Float64
  rho::Float64
  ts::T
end

(g::G2FittingParameter)(t::Float64) = value(g, t)

function value(param::G2FittingParameter, t::Float64)
  forward = forward_rate(param.ts, t, t, ContinuousCompounding(), NoFrequency()).rate
  temp1 = param.sigma * (-expm1(-param.a * t)) / param.a
  temp2 = param.eta * (-expm1(-param.b * t)) / param.b

  val = 0.5 * temp1 * temp1 + 0.5 * temp2 * temp2 + param.rho * temp1 * temp2 + forward

  return val
end

mutable struct HullWhiteFittingParameter{T <: TermStructure} <: Parameter
  a::Float64
  sigma::Float64
  ts::T
end

(h::HullWhiteFittingParameter)(t::Float64) = value(h, t)

function value(param::HullWhiteFittingParameter, t::Float64)
  forward = forward_rate(param.ts, t, t, ContinuousCompounding(), NoFrequency()).rate
  temp = param.a < sqrt(eps()) ? param.sigma * t : param.sigma * (-expm1(-param.a * t)) / param.a

  return forward + 0.5 * temp * temp
end

mutable struct TermStructureFittingParameter{T <: TermStructure} <: Parameter
  times::Vector{Float64}
  values::Vector{Float64}
  ts::T
end

TermStructureFittingParameter(ts::T) where {T <: TermStructure} = TermStructureFittingParameter{T}(zeros(0), zeros(0), ts)

(tsp::TermStructureFittingParameter)(t::Float64) = value(tsp, t)

function reset_param_impl!(param::TermStructureFittingParameter)
  param.times = zeros(length(param.times))
  param.values = zeros(length(param.values))

  return param
end

function set_params!(param::TermStructureFittingParameter, tm::Float64, val::Float64)
  push!(param.times, tm)
  push!(param.values, val)

  return param
end

function value(param::TermStructureFittingParameter, t::Float64)
  idx = findfirst(isequal(t), param.times)
  return param.values[idx]
end

mutable struct PiecewiseConstantParameter{C <: Constraint} <: Parameter
  times::Vector{Float64}
  constraint::C

  function PiecewiseConstantParameter{C}(times::Vector{Float64}, constraint::C) where C
    retTimes = push!(times, 0.0)
    return new{C}(retTimes, constraint)
  end
end

PiecewiseConstantParameter(times::Vector{Float64}, constraint::C) where {C <: Constraint} = PiecewiseConstantParameter{C}(times, constraint)

# call(p::PiecewiseConstantParameter, t::Float64) = value(p, t)

set_params!(param::PiecewiseConstantParameter, i::Int, val::Float64) = param.times[i] = val
get_data(param::PiecewiseConstantParameter) = param.times

NullParameter(_type::DataType) = _type([0.0], NoConstraint())

test_params(c::ConstantParameter, params::Vector{Float64}) = QuantLib.Math.test(c.constraint, params)
