push!(LOAD_PATH, pwd())
using ExcelReaders, Dates, DateHandler, PrincipalComponentsAnalysis, JuMP, Cbc, StatsBase, LinearAlgebra, Statistics, DataStructures, XLSX, ResultsReporter

"""
    CustomDataInit(;first::Symbol = Symbol("2011Q1"), last::Symbol = Symbol(string(year(today())) * "Q" * string(quarterofyear(today())))
My custom data reader. Options `first` and `last` determine the data range. The default is the whole available range up to date.
"""
function CustomDataInit(;first::Symbol = Symbol("2011Q1"), last::Symbol = Symbol(string(year(today())) * "Q" * string(quarterofyear(today()))))
    PriceSheet = readxlsheet("Close & PE.xlsx", "Up2DatePrice")
    PESheet = readxlsheet("Close & PE.xlsx", "Up2DatePE")
    LevelData = PriceSheet[2:end, 2:end]
    ReturnData = LevelData[1:end-1,:] ./ LevelData[2:end,:] .- 1
    LevelData = LevelData[1:end-1,:]
    DateVec = Date.(PriceSheet[2:end-1,1])
    StockNames = PriceSheet[1, 2:end]
    PERatios = PESheet[2:end-1, 2:end]
    QuarterInfo = Symbol.(string.(year.(DateVec)) .* "Q" .* string.(quarterofyear.(DateVec)))
    indexes = (QuarterInfo .>= first) .& (QuarterInfo .<= last)
    data = Dict()
    data[:dates] =  DateVec[indexes, :][:]
    data[:PEs] = PERatios[indexes, :].^-1
    data[:stocks] = StockNames[1:107]
    data[:stocklevels] = Array{Float64}(LevelData[indexes, 1:107])
    data[:stockreturns] = Array{Float64}(ReturnData[indexes, 1:107])
    data[:securities] = StockNames[108:end]
    data[:securitieslevels] = Array{Float64}(LevelData[indexes, 108:end])
    data[:securitiesreturns] = Array{Float64}(ReturnData[indexes, 108:end])
    data
end

"""
    rankstatextractor(data::Dict, o::Dict)
"""
function rankstatextractor(data::Dict, o::Dict)
    _, RetroDataIndex = DateHandler.DateRetrospection(data[:dates], o[:endofperiod], o[:retrospectionperiod])
    RelevantReturn = o[:addsecurities] ? hcat(data[:stockreturns], data[:securitiesreturns])[RetroDataIndex, :] : data[:stockreturns][RetroDataIndex, :]
    RelevantEP = data[:PEs][RetroDataIndex, :][1,:]
    PEranks = sortperm(sortperm(RelevantEP, rev = true))
    returnspread = (inversePCA(PCA(RelevantReturn, typeofSim = o[:pcatype], normtype = o[:normtype], featurenum = o[:featurenum])) - RelevantReturn)[1:o[:PCAdays], 1:size(data[:stockreturns], 2)]
    returnspreadndays = prod(returnspread .+ 1, dims = 1)
    spreadrankings = sortperm(sortperm(returnspreadndays[1:end], rev = true))
    collectiverankstat = spreadrankings + o[:lambda] * PEranks
    if o[:rankmode] == :Collective
        return collectiverankstat
    end
    if o[:rankmode] == :PEranks
        return PEranks
    end
    if o[:rankmode] == :Spreadranks
        return spreadrankings
    end
end

"""

"""
function RankingNExplicitChurn(data::Dict, o::Dict)
    rankstat = rankstatextractor(data, o)
    m = Model(solver = CbcSolver())
    @variable(m, 0 <= x[1:length(rankstat)] <= 0.05)
    @objective(m, Min, dot(x, rankstat))
    @constraint(m, sum(x) == 1)
    solve(m)
    output = reshape(Array(getvalue(x)), 1, :)
    return output
end

"""
"""
function RankingNExplicitChurn(data::Dict, o::Dict, oldportfolio)
    rankstat = rankstatextractor(data, o)
    m = Model(solver = CbcSolver())
    @variable(m, 0 <= x[1:length(rankstat)] <= 0.05)
    @variable(m, z[1:length(rankstat)])
    @objective(m, Min, dot(x, rankstat))
    @constraint(m, sum(x) == 1)
    @constraint(m, [i = 1:length(x)], z[i] - x[i] >= -oldportfolio[i])
    @constraint(m, [i = 1:length(x)], z[i] + x[i] >= oldportfolio[i])
    @constraint(m, sum(z) <= 2*o[:churn])
    solve(m)
    output = reshape(Array(getvalue(x)), 1, :)
    return output
end

"""
    portfolioconstructor(data::Dict, o::Dict)
Create a portfolio allocation matrix given data and options.
"""
function portfolioconstructor(data::Dict, o::Dict)
    PortfolioAllocations = Any[]
    o[:endofperiod] = o[:initialstart]
    oldportfolio = RankingNExplicitChurn(data, o)
    push!(PortfolioAllocations, oldportfolio)
    datevec = data[:dates]
    for date in datevec[datevec .>= o[:initialstart]][end-1:-1:1]
        o[:endofperiod] = date
        newportfolio = RankingNExplicitChurn(data, o, oldportfolio)
        push!(PortfolioAllocations, newportfolio)
        oldportfolio = newportfolio
    end
    PortfolioAllocations = reverse(vcat(PortfolioAllocations...), dims = 1)
    return PortfolioAllocations
end

function dailypcaroutine()
    data = CustomDataInit()
    o = Dict()
    o[:retrospectionperiod] = Month(6)
    o[:PCAdays] = 4
    o[:rankmode] = :Collective # {:Collective, :PEranks, :Spreadranks}
    o[:addsecurities] = false
    o[:pcatype] = :cov
    o[:normtype] = 0
    o[:featurenum] = 1 #{1:NumberOfTradeables}
    o[:endofperiod] = today() + Day(1)
    _, RetroDataIndex = DateHandler.DateRetrospection(data[:dates], o[:endofperiod], o[:retrospectionperiod])
    RelevantReturn = o[:addsecurities] ? hcat(data[:stockreturns], data[:securitiesreturns])[RetroDataIndex, :] : data[:stockreturns][RetroDataIndex, :]
    reconstructed = inversePCA(PCA(RelevantReturn, typeofSim = o[:pcatype], normtype = o[:normtype], featurenum = 1))[1:o[:PCAdays], 1:size(data[:stockreturns], 2)]'
    realized = RelevantReturn[1:o[:PCAdays], 1:size(data[:stockreturns], 2)]'
    spread = reconstructed - realized
    spreadnday = prod(spread .+ 1, dims = 2) .- 1
    imat = hcat(data[:stocks], reconstructed, realized, spread, spreadnday)
    rankperm = sortperm(spreadnday[:], rev = true)
    output = imat[rankperm, :]
    results2excel("111", output, headers = false)
end


data = CustomDataInit(last = Symbol("2018Q3"))

o = Dict()
o[:retrospectionperiod] = Month(6)
o[:PCAdays] = 4 # {1:o[:retrospectionperiod]}
o[:rankmode] = :Collective # {:Collective, :PEranks, :Spreadranks}
o[:addsecurities] = false #{true, false}
o[:pcatype] = :cov #{:cov, cor}
o[:normtype] = 0 #{:nonorm, :meannorm, :zscore, :minmax} Note that if minmax is used using range[-1,1] or [0.1,0.9] is also an option need 2 take care of that.
o[:featurenum] = 0 #{1:NumberOfTradeables}
o[:lambda] = 1 #[0, +)
o[:churn] = 0.15 #[0.05, 0.3]
o[:initialstart] = Date(2013, 1, 2)
o[:endofperiod] = o[:initialstart]

#PortfolioAllocations = portfolioconstructor(data, o)
#quarterlystats = quarterlyportfoliostats(data, o, PortfolioAllocations)



GridResults = Dict()
for lambda in round.(exp.(log(0.1):log(99.9999999999999)/50:log(10)), digits = 2), churn in collect(0.10:0.01:0.20), normtype in [0, 1]
    o[:lambda], o[:churn], o[:normtype] = lambda, churn, normtype
    PortfolioAllocations = portfolioconstructor(data, o)
    quarterlystats = quarterlyportfoliostats(data, o, PortfolioAllocations)
    GridResults[lambda, churn, normtype] = quarterlystats
end

#=

GridResults = Dict()
for lambda in round.(exp.(log(0.1):log(99.9999999999999)/50:log(10)), digits = 2), churn in collect(0.10:0.01:0.20), pcatype in [:cov, :cor], normtype in [0,1,2]
    o[:lambda], o[:churn], o[:pcatype], o[:normtype] = lambda, churn, pcatype, normtype
    PortfolioAllocations = portfolioconstructor(data, o)
    quarterlystats = quarterlyportfoliostats(data, o, PortfolioAllocations)
    GridResults[lambda, churn, pcatype, normtype] = quarterlystats
end

=#
#=
normtype = 1

Results2Print = Dict()
Results2Print[:Returns] = Array{Float64, 2}(undef, 51, 11)
for (i, lambda) in enumerate(round.(exp.(log(0.1):log(99.9999999999999)/50:log(10)), digits = 2)), (j, churn) in enumerate(collect(0.10:0.01:0.20))
    Results2Print[:Returns][i,j] = GridResults[lambda, churn, normtype][2, end]
end

Results2Print[:Vols] = Array{Float64, 2}(undef, 51, 11)
for (i, lambda) in enumerate(round.(exp.(log(0.1):log(99.9999999999999)/50:log(10)), digits = 2)), (j, churn) in enumerate(collect(0.10:0.01:0.20))
    Results2Print[:Vols][i,j] = GridResults[lambda, churn, normtype][5, end]
end

Results2Print[:MaxDrawdowns] =  Array{Float64, 2}(undef, 51, 11)
for (i, lambda) in enumerate(round.(exp.(log(0.1):log(99.9999999999999)/50:log(10)), digits = 2)), (j, churn) in enumerate(collect(0.10:0.01:0.20))
    Results2Print[:MaxDrawdowns][i,j] = GridResults[lambda, churn, normtype][8, end]
end

results2excel("111",Results2Print)
=#
