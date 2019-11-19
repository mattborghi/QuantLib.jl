using QuantLib

import Base.getindex, Base.lastindex

# Construct TimeGrid, we store
mutable struct TimeGrid
  times::Vector{Float64} # array of times
  dt::Vector{Float64} # an array of steps
  mandatoryTimes::Vector{Float64} # just the sort(unique()) of the input vector
end

# > QuantLib.Time.TimeGrid([1.,2.,3.,4.,5.,6.,7.,8.,9.,10.], 20)
# > QuantLib.Time.TimeGrid([0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5  …  5.5, 6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0],
# [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5,.5, 0.5], [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0])
function TimeGrid(times::Vector{Float64}, steps::Int)
  sortedUniqueTimes = sort(unique(times))

  lastTime = sortedUniqueTimes[end]

  # TODO check if steps is 0
  dtMax = lastTime / steps
  periodBegin = 0.0
  times = zeros(1)

  @inbounds @simd for t in sortedUniqueTimes
    periodEnd = t
    if periodEnd != 0.0
      nSteps = Int(floor((periodEnd - periodBegin) / dtMax + 0.5))
      nSteps = nSteps != 0 ? nSteps : 1
      dt = (periodEnd - periodBegin) / nSteps

      tempTimes = zeros(nSteps)
      for n=1:nSteps
        tempTimes[n] = periodBegin + n * dt
      end
    end
    periodBegin = periodEnd
    times = vcat(times, tempTimes)
  end

  dt = diff(times)

  return TimeGrid(times, dt, sortedUniqueTimes)
end

# > QuantLib.Time.TimeGrid(17.5, 20)
# > QuantLib.Time.TimeGrid([0.0, 0.875, 1.75, 2.625, 3.5, 4.375, 5.25, 6.125, 7.0, 7.875  …  9.625, 10.5, 11.375, 12.25, 13.125, 14.0, 14.875, 15.75, 16.625, 17.5],
# [0.875, 0.875, 0.875, 0.875, 0.875, 0.875, 0.875, 0.875, 0.875, 0.875, 0.875, 0.875, 0.875, 0.875, 0.875, 0.875, 0.875, 0.875, 0.875, 0.875], [17.5])
function TimeGrid(endTime::Float64, steps::Int)
  endTime > 0.0 || error("negative times not allowed")
  dt = endTime / steps
  times = zeros(steps + 1)
  @simd for i in eachindex(times)
    @inbounds times[i] = dt * (i - 1)
  end

  mandatoryTimes = [endTime]

  dtVec = fill(dt, steps)

  return TimeGrid(times, dtVec, mandatoryTimes)
end

getindex(tg::TimeGrid, i::Int) = tg.times[i]
lastindex(tg::TimeGrid) = lastindex(tg.times)

is_empty(tg::TimeGrid) = length(tg.times) == 0

function closest_index(tg::TimeGrid, t::Float64)
  # stuff
  res = searchsortedfirst(tg.times, t)
  if res == 1
    return 1
  elseif res == length(tg.times) + 1
    return length(tg.times)
  else
    dt1 = tg.times[res] - t
    dt2 = t - tg.times[res - 1]
    if dt1 < dt2
      return res
    else
      return res - 1
    end
  end
end

closest_time(tg::TimeGrid, t::Float64) = tg.times[closest_index(tg, t)]

function return_index(tg::TimeGrid, t::Float64)
  i = closest_index(tg, t)
  if QuantLib.Math.close_enough(t, tg.times[i])
    return i
  else
    error("this time grid is wrong, $i $t $(tg.times[i]) $(tg.times[i-1]) $(tg.times[i+1])")
  end
end
