# Frequency
using Dates

# ==============================================================================================================================================================
# ==============================================================================================================================================================
# ============================================================= FREQUENCY ======================================================================================
# ==============================================================================================================================================================
# ==============================================================================================================================================================
abstract type Frequency end

# Here we define a special set of objects: the frequencies
# NoFrequency, Once, Annual, Semiannual, EveryFourthMonth
# Quarterly, Bimonthly, Monthly, EveryFourthWeek, Biweekly
# Weekly, Daily, OtherFrequency

struct NoFrequency <: Frequency end
struct Once <: Frequency end
struct Annual <: Frequency end
struct Semiannual <: Frequency end
struct EveryFourthMonth <: Frequency end
struct Quarterly <: Frequency end
struct Bimonthly <: Frequency end
struct Monthly <: Frequency end
struct EveryFourthWeek <: Frequency end
struct Biweekly <: Frequency end
struct Weekly <: Frequency end
struct Daily <: Frequency end
struct OtherFrequency <: Frequency end

# ===============================================================================================================================
# Methods Returned:
# value(::Frequency)
# Returns the number of times the event will occur in one year (e.g. 1 for Annual, 2 for Semiannual, 3 for EveryFourthMonth, etc)
#
# period(::Frequency)
# Returns the underlying time period of the frequency (e.g. 1 Year for Annual, 6 Months for Semiannual, etc)
# ===============================================================================================================================
# This is a way of specifying functions
# No I can define a Frequency Object like
# freq = QuantLib.Time.NoFrequency()
# and call the value of that object
# value(freq) -> -1
# These values are going to be used to calculate tenor periods

# default value if no freq specified
value(::Frequency) = -1

# negative value, when we define a tenor period it's defined as
#  if freq < 0
#  period = Dates.Day(0)
value(::NoFrequency) = -1

value(::Once)			 	= 0
value(::Annual)			= 1

value(::Semiannual)		= 2
value(::EveryFourthMonth)  = 3
value(::Quarterly)		 	= 4
value(::Bimonthly)		 	= 6
value(::Monthly)			= 12
value(::EveryFourthWeek)  	= 13
value(::Biweekly)		 	= 26
value(::Weekly)			= 52
value(::Daily)			 	= 365
value(::OtherFrequency)   	= 999

period(::Annual) = Year(1)
period(::Semiannual) = Month(6)
