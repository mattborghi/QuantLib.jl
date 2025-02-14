struct BatesEngine{C <: ComplexLogFormula} <: AbstractHestonEngine{HestonGaussLaguerre}
  model::BatesModel
  evaluations::Int
  cpxLog::C
  integration::HestonGaussLaguerre
end

function BatesEngine(batesModel::BatesModel)
  evals = 0
  cpxLog = Gatheral()
  integration = HestonGaussLaguerre(144)

  return BatesEngine(batesModel, evals, cpxLog, integration)
end

function add_on_term(pe::BatesEngine, phi::Float64, t::Float64, j::Int)
  batesModel = pe.model
  nu = get_nu(batesModel)
  delta2 = 0.5 * get_delta(batesModel) * get_delta(batesModel)
  lambda = get_lambda(batesModel)
  i = j == 1 ? 1.0 : 0.0
  g = complex(i, phi)

  return t * lambda * (expm1(nu * g + delta2 * g * g) - g * expm1(nu * delta2))
end
