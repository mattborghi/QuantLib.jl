# using FloatFloat

mutable struct FittingMethodCommons{T <: Real}
  solution::Vector{T}
  guessSolution::Vector{T}
  numberOfIterations::Int
  minimumCostValue::Float64
  weights::Vector{T}
  costFunction::FittingCost
end

function FittingMethodCommons(size::Int, gsize::Int)
  solution = zeros(size)
  # solution = Vector{DD}(size)
  guessSolution = zeros(gsize)
  # guessSolution = Vector{DD}(gsize)
  numberOfIterations = 0
  minimumCostValue = 0.0
  weights = zeros(size)
  # weights = Vector{DD}(size)
  curve = NullCurve()
  costFunction = FittingCost(size, curve)

  return FittingMethodCommons(solution, guessSolution, numberOfIterations, minimumCostValue, weights, costFunction)
end

mutable struct ExponentialSplinesFitting <: FittingMethod
  constrainAtZero::Bool
  size::Int
  commons::FittingMethodCommons
end

function ExponentialSplinesFitting(constrainAtZero::Bool, size::Int)
  if constrainAtZero
    gsize = 9
  else
    gsize = 10
  end

  commons = FittingMethodCommons(size, gsize)

  return ExponentialSplinesFitting(constrainAtZero, gsize, commons)
end

mutable struct SimplePolynomialFitting <: FittingMethod
  constrainAtZero::Bool
  degree::Int
  size::Int
  commons::FittingMethodCommons
end

function SimplePolynomialFitting(constrainAtZero::Bool, degree::Int, size::Int)
  if constrainAtZero
    gsize = degree
  else
    gsize = degree + 1
  end

  commons = FittingMethodCommons(size, gsize)

  return SimplePolynomialFitting(constrainAtZero, degree, gsize, commons)
end

mutable struct NelsonSiegelFitting <: FittingMethod
  constrainAtZero::Bool
  size::Int
  commons::FittingMethodCommons
end

function NelsonSiegelFitting(size::Int)
  constrainAtZero = true
  gsize = 4

  commons = FittingMethodCommons(size, gsize)

  return NelsonSiegelFitting(constrainAtZero, gsize, commons)
end

mutable struct SvenssonFitting <: FittingMethod
  constrainAtZero::Bool
  size::Int
  commons::FittingMethodCommons
end

function SvenssonFitting(size::Int)
  constrainAtZero = true
  gsize = 6

  commons = FittingMethodCommons(size, gsize)

  return SvenssonFitting(constrainAtZero, gsize, commons)
end

mutable struct CubicBSplinesFitting <: FittingMethod
  constrainAtZero::Bool
  size::Int
  knots::Vector{Float64}
  splines::BSpline
  N::Int
  commons::FittingMethodCommons

  function CubicBSplinesFitting(constrainAtZero::Bool, knots::Vector{Float64}, size::Int)
    m = length(knots)
    m >= 8 || error("At least 8 knots are required")

    splines = BSpline(3, m - 4, knots)
    basis_functions = m - 4
    if constrainAtZero
      gsize = basis_functions - 1

      N = 2
      abs(spline_oper(splines, N, 0.0) > QuantLib.Math.EPS_VAL) || error("N_th cubic B-spline must be nonzero at t=0")
    else
      gsize = basis_functions
      N = 1
    end

    commons = FittingMethodCommons(size, gsize)

    new(constrainAtZero, gsize, knots, splines, N, commons)
  end
end

# CubicBSplinesFitting(constrainAtZero::Bool, knots::Vector{Float64}, size::Int) = CubicBSplinesFitting(constrainAtZero, knots, size)


# function ExponentialSplinesFitting(constrainAtZero::Bool, size::Integer)
#   solution = zeros(size)
#   if constrainAtZero
#     gsize = 9
#   else
#     gsize = 10
#   end
#   guessSolution = zeros(gsize)
#   numberOfIterations = 0
#   minimumCostValue = 0.0
#   weights = zeros(size)
#   curve = NullCurve()
#   costFunction = FittingCost(size, curve)
#
#   return ExponentialSplinesFitting(constrainAtZero, gsize,
#           FittingMethodCommons(solution, guessSolution, numberOfIterations, minimumCostValue, weights, costFunction))
# end

guess_size(fitting::ExponentialSplinesFitting) = fitting.constrainAtZero ? 9 : 10
guess_size(fitting::SimplePolynomialFitting) = fitting.constrainAtZero ? fitting.degree : fitting.degree + 1

# Discount functions
function discount_function(method::ExponentialSplinesFitting, x::Vector{T}, t::Float64) where {T <: Real}
  d = 0.0
  N = guess_size(method)
  kappa = x[N]
  coeff = 0.0
  if !method.constrainAtZero
    @simd for i = 1:N
      @inbounds d += x[i] * exp(-kappa * (i) * t)
    end
  else
    @simd for i = 1:N - 1
      @inbounds d += x[i]  * exp(-kappa * (i + 1) * t)
      @inbounds coeff += x[i]
    end
    coeff = 1.0 - coeff
    d += coeff * exp(-kappa * t)
  end
  return d
end

function discount_function(method::SimplePolynomialFitting, x::Vector{T}, t::Float64) where {T <: Real}
  d = 0.0
  N = method.size

  if !method.constrainAtZero
    @simd for i = 1:N
      @inbounds d += x[i] * get_polynomial(BernsteinPolynomial(), i-1, i-1, t)
    end
  else
    d = 1.0
    @simd for i = 1:N
      @inbounds d += x[i] * get_polynomial(BernsteinPolynomial(), i, i, t)
    end
  end

  return d
end

function discount_function(method::NelsonSiegelFitting, x::Vector{T}, t::Float64) where {T <: Real}
  kappa = x[method.size]
  @inbounds zero_rate = x[1] + (x[2] + x[3]) * (1.0 - exp(-kappa * t)) / ((kappa + QuantLib.Math.EPS_VAL) * (t + QuantLib.Math.EPS_VAL)) - (x[3]) * exp(-kappa * t)
  d = exp(-zero_rate * t)

  return d
end

function discount_function(method::SvenssonFitting, x::Vector{T}, t::Float64) where {T <: Real}
  kappa = x[method.size - 1]
  kappa_1 = x[method.size]
  eps_v = QuantLib.Math.EPS_VAL

  zero_rate = x[1] + (x[2] + x[3]) * (1.0 - exp(-kappa * t)) / ((kappa + eps_v) * (t + eps_v)) - (x[3]) * exp(-kappa * t) + x[4] * (((1.0 - exp(-kappa_1 * t)) / ((kappa_1 + eps_v) * (t + eps_v))) - exp(-kappa_1 * t))

  d = exp(-zero_rate * t)
  return d
end

function discount_function(method::CubicBSplinesFitting, x::Vector{T}, t::Float64) where {T <: Real}
  d = 0.0
  if !method.constrainAtZero
    @simd for i = 1:method.size
      @inbounds d += x[i] * spline_oper(method.splines, i, t)
    end
  else
    t_star = 0.0
    sum = 0.0
    @simd for i = 1:method.size
      if i < method.N
        @inbounds d += x[i] * spline_oper(method.splines, i, t)
        @inbounds sum += x[i] * spline_oper(method.splines, i, t_star)
      else
        @inbounds d += x[i] * spline_oper(method.splines, i + 1, t)
        @inbounds sum += x[i] * spline_oper(method.splines, i + 1, t_star)
      end
    end
    coeff = 1.0 - sum
    coeff /= spline_oper(method.splines, method.N, t_star)
    d += coeff * spline_oper(method.splines, method.N, t)
  end

  return d
end
