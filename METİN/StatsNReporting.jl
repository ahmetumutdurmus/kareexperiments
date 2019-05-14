print(pwd())

module StatsNReporting

export quarterlyportfoliostats, shortstatsummary

using DataStructures, Statistics, Dates, DataStructures

function portfolioreturn(portfolioallocations, returns)
    @assert size(portfolioallocations) == size(returns) "The dimensions of portfolio allocations and asset returns must match!"
    prod([sum(skipmissing(portfolioallocations[i,:] .* returns[i,:])) for i in 1:size(returns, 1)] .+ 1) .- 1
end

function portfolioreturn(returns)
    prod([mean(skipmissing(returns[i,:])) for i in 1:size(returns, 1)] .+ 1) .- 1
end

function portfoliovol(portfolioallocations, returns)
    @assert size(portfolioallocations) == size(returns) "The dimensions of portfolio allocations and asset returns must match!"
    std([sum(skipmissing(portfolioallocations[i,:] .* returns[i,:])) for i in 1:size(returns, 1)]) * sqrt(250)
end

function portfoliovol(returns)
    std([mean(skipmissing(returns[i,:])) for i in 1:size(returns, 1)]) * sqrt(250)
end

function portfoliochurn(portfolioallocations)
    copyport = copy(portfolioallocations)
    copyport[ismissing.(copyport)] .= 0
    mean(sum(abs, copyport[1:end-1,:] .- copyport[2:end,:], dims = 2) / 2)
end

function sharperatio(portfolioallocations, returns)
    ((portfolioreturn(portfolioallocations, returns) + 1).^(250/size(portfolioallocations, 1)) - 1) / portfoliovol(portfolioallocations, returns)
end

function sharperatio(returns)
    ((portfolioreturn(returns) + 1).^(250/size(returns, 1)) - 1) / portfoliovol(returns)
end

function quarterlyportfoliostats(data, o, portfolioallocations::Array)
    @assert sum((data[:dates] .>= o[:periodstart]) .& (data[:dates] .<= o[:periodend])) == size(portfolioallocations, 1) "There is inconsistency between the portfolio allocations and period start and end dates. Either update the `o[:periodstart]` and `o[:periodend]` dates or supply the portfolio allocations in a struct containing a `dates` and `allocations` field."
    ind = findfirst(x -> x <= o[:periodend], data[:dates]):findlast(x -> x >= o[:periodstart], data[:dates])
    signaldates = data[:dates][ind]
    stockreturns = data[:stockreturns][ind,:]
    indexreturns = data[:securitiesreturns][ind,:]
    quarters = SortedDict()
    for dt in signaldates[end]:Month(3):signaldates[1]
        quarters[Symbol(string(year(dt))*"Q"*string(quarterofyear(dt)))] = data[:dates][(data[:dates] .>= o[:periodstart]) .& (data[:dates] .<= o[:periodend]) .& (data[:dates] .>= firstdayofquarter(dt)) .& (data[:dates] .<= lastdayofquarter(dt))]
    end
    Results = Any[]
    for (qt, dt) in quarters
        quarterholdings = portfolioallocations[indexin(dt, signaldates), :]
        quarterstockreturns = stockreturns[indexin(dt, signaldates), :]
        quarterindexreturns = indexreturns[indexin(dt, signaldates), :]
        push!(Results, [String(qt) portfolioreturn(quarterholdings, quarterstockreturns) portfolioreturn(quarterstockreturns) portfolioreturn(quarterindexreturns)])
    end
    M = vcat(reverse(Results)...)
    vcat(hcat("Yearly Average", prod(M[:,2:end] .+ 1, dims = 1) .^ (250 / size(portfolioallocations, 1)) .- 1), M)
end

function quarterlyportfoliostats(data, o, portfolioallocations)
    ind = indexin(portfolioallocations.dates, data[:dates])
    signaldates = data[:dates][ind]
    stockreturns = data[:stockreturns][ind,:]
    indexreturns = data[:securitiesreturns][ind,:]
    quarters = SortedDict()
    for dt in signaldates[end]:Month(3):signaldates[1]
        quarters[Symbol(string(year(dt))*"Q"*string(quarterofyear(dt)))] = data[:dates][(data[:dates] .>= o[:periodstart]) .& (data[:dates] .<= o[:periodend]) .& (data[:dates] .>= firstdayofquarter(dt)) .& (data[:dates] .<= lastdayofquarter(dt))]
    end
    Results = Any[]
    for (qt, dt) in quarters
        quarterholdings = portfolioallocations.allocations[indexin(dt, signaldates), :]
        quarterstockreturns = stockreturns[indexin(dt, signaldates), :]
        quarterindexreturns = indexreturns[indexin(dt, signaldates), :]
        push!(Results, [String(qt) portfolioreturn(quarterholdings, quarterstockreturns) portfolioreturn(quarterstockreturns) portfolioreturn(quarterindexreturns)])
    end
    M = vcat(reverse(Results)...)
    vcat(hcat("Yearly Average", prod(M[:,2:end] .+ 1, dims = 1) .^ (250 / size(portfolioallocations.allocations, 1)) .- 1), M)
end

function shortstatsummary(data, o, portfolioallocations::Array)
    @assert sum((data[:dates] .>= o[:periodstart]) .& (data[:dates] .<= o[:periodend])) == size(portfolioallocations, 1) "There is inconsistency between the portfolio allocations and period start and end dates. Either update the `o[:periodstart]` and `o[:periodend]` dates or supply the portfolio allocations in a struct containing a `dates` and `allocations` field."
    ind = findfirst(x -> x <= o[:periodend], data[:dates]):findlast(x -> x >= o[:periodstart], data[:dates])
    indreturns = data[:stockreturns][ind, :] .* portfolioallocations
    yrrtn = prod([sum(skipmissing(indreturns[i,:])) for i in 1:size(indreturns, 1)] .+ 1) .^ (250/size(indreturns, 1)) .- 1
    yrvol = std([sum(skipmissing(indreturns[i,:])) for i in 1:size(indreturns, 1)]) * sqrt(250)
    acc = mean([sum(skipmissing(indreturns[i,:])) for i in 1:size(indreturns, 1)] .>= 0)
    shrp = yrrtn / yrvol
    ["Yearly Return" yrrtn; "Sharpe Ratio" shrp; "Accuracy" acc]
end

function shortstatsummary(data, o, portfolioallocations)
    ind = indexin(portfolioallocations.dates, data[:dates])
    indreturns = data[:stockreturns][ind, :] .* portfolioallocations.allocations
    yrrtn = prod([sum(skipmissing(indreturns[i,:])) for i in 1:size(indreturns, 1)] .+ 1) .^ (250/size(indreturns, 1)) .- 1
    yrvol = std([sum(skipmissing(indreturns[i,:])) for i in 1:size(indreturns, 1)]) * sqrt(250)
    acc = mean([sum(skipmissing(indreturns[i,:])) for i in 1:size(indreturns, 1)] .>= 0)
    shrp = yrrtn / yrvol
    ["Yearly Return" yrrtn; "Sharpe Ratio" shrp; "Accuracy" acc]
end

end
