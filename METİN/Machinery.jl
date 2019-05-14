if pwd() != @__DIR__; cd(@__DIR__); end
push!(LOAD_PATH, pwd())
using ExcelReaders, Dates, PrincipalComponentsAnalysis, JuMP, GLPK, LinearAlgebra, Statistics, JLD, PyCall, StatsNReporting
openpyxl = pyimport("openpyxl")

"""
    customdatainit()
Initialize a dictionary of data for stock strategy.
"""
function customdatainit()
    PriceSheet = readxlsheet("Close & PE.xlsx", "Prices 50")
    ntradeables = size(PriceSheet, 2) - 2
    LevelData = PriceSheet[2:end, 2:end]
    LevelData = [isa(i, Number) ? i : missing for i in LevelData]
    ReturnData = LevelData[1:end-1,:] ./ LevelData[2:end,:] .- 1
    LevelData = LevelData[1:end-1,:]
    DateVec = Date.(PriceSheet[2:end-1,1])
    StockNames = PriceSheet[1, 2:end]
    data = Dict()
    data[:dates] =  DateVec
    data[:stocks] = StockNames[1:ntradeables]
    data[:stocklevels] = LevelData[:, 1:ntradeables]
    data[:stockreturns] = ReturnData[:, 1:ntradeables]
    data[:securities] = StockNames[ntradeables+1:end]
    data[:securitieslevels] = Array{Float64}(LevelData[:, ntradeables+1:end])
    data[:securitiesreturns] = Array{Float64}(ReturnData[:, ntradeables+1:end])
    data
end

"""
    rankstatextractor(data::Dict, o::Dict)
Give the decision statistic vector for the strategy at any given date t = o[:currentdatepointer] using the data of {t-1, t-2, ..., t-o[:matrixretrospectionperiod]}.
"""
function rankstatextractor(data::Dict, o::Dict)
    ind = findfirst(x -> x < o[:currentdatepointer], data[:dates]):findlast(x -> x >= o[:currentdatepointer] - o[:matrixretrospectionperiod], data[:dates])
    data[:dates][ind]
    RelevantReturn = data[:stockreturns][ind, :]
    n = sum([!in(missing, Set(RelevantReturn[:, i])) for i in 1:size(RelevantReturn, 2)])
    reconstructed = inversePCA(PCA(RelevantReturn[:,1:n], typeofSim = :cov, normtype = 2, featurenum = 1))[1:o[:PCAdays], :]'
    realized = RelevantReturn[1:o[:PCAdays], 1:n]'
    returnspread = reconstructed - realized
    returnspreadndays = prod(returnspread .+ 1, dims = 2) .- 1
    spreadrankings = sortperm(sortperm(returnspreadndays[1:end], rev = true))
    spreadrankings
end

"""
    rankingnexplicitchurn(data::Dict, o::Dict)
Cosntruct day t's portfolio such that t = o[:currentdatepointer] using the data of {t-1, t-2, ..., t-o[:matrixretrospectionperiod]}.
Pays no attention to the churn constraint. Generally used as an initializer.
"""
function rankingnexplicitchurn(data::Dict, o::Dict)
    rankstat = rankstatextractor(data, o)
    m = Model(with_optimizer(GLPK.Optimizer))
    @variable(m, 0 <= x[1:length(rankstat)] <= 1/o[:numberofstocks])
    @objective(m, Min, dot(x, rankstat))
    @constraint(m, sum(x) == 1)
    optimize!(m)
    output = length(rankstat) == length(data[:stocks]) ? reshape(value.(x), 1, :) : reshape(vcat(value.(x), Array{Missing, 1}(missing, length(data[:stocks]) - length(rankstat))), 1, :)
    return output
end

"""
    rankingnexplicitchurn(data::Dict, o::Dict, oldportfolio)
Cosntruct day t's portfolio such that t = o[:currentdatepointer] using the data of {t-1, t-2, ..., t-o[:matrixretrospectionperiod]}. Subject to the churn constraint given the portfolio of t-1.
"""
function rankingnexplicitchurn(data::Dict, o::Dict, oldportfolio)
    rankstat = rankstatextractor(data, o)
    m = Model(with_optimizer(GLPK.Optimizer))
    @variable(m, 0 <= x[1:length(rankstat)] <= 1/o[:numberofstocks])
    @variable(m, z[1:length(rankstat)])
    @objective(m, Min, dot(x, rankstat))
    @constraint(m, sum(x) == 1)
    @constraint(m, [i = 1:length(x)], z[i] - x[i] >= (ismissing(oldportfolio[i]) ? 0 : -oldportfolio[i]))
    @constraint(m, [i = 1:length(x)], z[i] + x[i] >= (ismissing(oldportfolio[i]) ? 0 : oldportfolio[i]))
    @constraint(m, sum(z) <= 2*o[:churn])
    optimize!(m)
    output = length(rankstat) == length(data[:stocks]) ? reshape(value.(x), 1, :) : reshape(vcat(value.(x), Array{Missing, 1}(missing, length(data[:stocks]) - length(rankstat))), 1, :)
    return output
end

"""
    portfolioconstructor(data::Dict, o::Dict)
Create a portfolio allocation matrix given data and options for a specified period of time between `o[:periodstart]` and `o[:periodend]`.
"""
function portfolioconstructor(data::Dict, o::Dict)
    PortfolioAllocations = Any[]
    datevec = data[:dates][(data[:dates] .>= o[:periodstart]).&(data[:dates] .<= o[:periodend])]
    oldportfolio = portfolioinitializer(data, o)
    for date in datevec[end:-1:1]
        o[:currentdatepointer] = date
        newportfolio = rankingnexplicitchurn(data, o, oldportfolio)
        push!(PortfolioAllocations, newportfolio)
        oldportfolio = newportfolio
    end
    PortfolioAllocations = reverse(vcat(PortfolioAllocations...), dims = 1)
    return PortfolioAllocations
end

"""
    portfolioinitializer(data::Dict, o::Dict)
Given a period start time `t = o[:periodstart]` initializes a portfolio from `t - 3 Months` and carries it to `t` to remove the initialization effect and bring the strategy to a `steady state`.
Is intended for embedded use by the `portfolioconstructor(data::Dict, o::Dict)` function.
"""
function portfolioinitializer(data::Dict, o::Dict)
    datevec = data[:dates][(data[:dates] .<= o[:periodstart]) .& (data[:dates] .>= o[:periodstart] - Month(6))]
    o[:currentdatepointer] = datevec[end]
    oldportfolio = rankingnexplicitchurn(data, o)
    for date in datevec[end-1:-1:1]
        o[:currentdatepointer] = date
        newportfolio = rankingnexplicitchurn(data, o, oldportfolio)
        oldportfolio = newportfolio
    end
    return oldportfolio
end

"""
    readlastportfolio(data, o; dt = data[:dates][1])
Reads the current and yesterday's portfolios from the CRE Allocations document. Note that this function is intended for embedded use in the daily strategy routine function.
"""
function readlastportfolio(data, o; dt = data[:dates][1])
    ws, ys = data[:dates][data[:dates] .< dt][[1,2]]
    y, m, d = yearmonthday(ws)
    wsn = string.(d, ".",m, ".",y)
    stocknames = readxl("CRE Allocations.xlsx", wsn * "!A3:A$(3 + o[:numberofstocks] - 1)")[:]
    oldportfolio = zeros(size(data[:stocks]))
    oldportfolio[indexin(stocknames, data[:stocks])] .= 1/o[:numberofstocks]
    y, m, d = yearmonthday(ys)
    ysn = string.(d, ".",m, ".",y)
    stocknamestda = readxl("CRE Allocations.xlsx", ysn * "!A3:A$(3 + o[:numberofstocks] - 1)")[:]
    twodayagoportfolio = zeros(size(data[:stocks]))
    twodayagoportfolio[indexin(stocknamestda, data[:stocks])] .= 1/o[:numberofstocks]
    oldportfolio, stocknames, twodayagoportfolio, stocknamestda
end

"""
    results2excel(filename::String, array::Array, refcell::Tuple{Int64, Int64}, worksheet)
Prints a given array to Excel. First three arguments are self explanatory given their types. `worksheet` argument may be and `Int` or `String` type standing for position or name.
"""
function results2excel(filename, array, refcell, worksheet::Int)
    filename = filename * ".xlsx"
    mode = in(filename, readdir()) ? (println("$(filename) is loaded!");:edit) : (println("$(filename) is created!");:new)
    wb = in(filename, readdir()) ? openpyxl.load_workbook(filename) : openpyxl.Workbook()
    nws = length(wb._sheets)
    ws = worksheet <= nws ? (println("Worksheet number $worksheet is loaded!"); wb._sheets[worksheet]) : (println("Workbook has only $nws sheets. A new one is appended to the end.");wb.create_sheet())
    r, c = refcell
    for i in 1:size(array, 1), j in 1:size(array,2)
        if !ismissing(array[i,j])
            ws.cell(row = i+r-1, column = j+c-1, value = array[i,j])
        end
    end
    wb.save(filename)
end

function results2excel(filename, array, refcell, worksheet::String)
    filename = filename * ".xlsx"
    mode = in(filename, readdir()) ? (println("$(filename) is loaded!");:edit) : (println("$(filename) is created!");:new)
    wb = in(filename, readdir()) ? openpyxl.load_workbook(filename) : openpyxl.Workbook()
    ws = in(worksheet, wb.sheetnames) ? wb._sheets[first(indexin([worksheet], wb.sheetnames))] : (mode == :new ? first(wb._sheets) : wb.create_sheet(worksheet))
    in(worksheet, wb.sheetnames) ? println("\"$(worksheet)\" worksheet is loaded.") : println("\"$(worksheet)\" worksheet is created.")
    if mode == :new; ws.title = worksheet; end
    r, c = refcell
    for i in 1:size(array, 1), j in 1:size(array,2)
        if !ismissing(array[i,j])
            ws.cell(row = i+r-1, column = j+c-1, value = array[i,j])
        end
    end
    wb.save(filename)
end

"""
    portfolioallocations(dates, allocations, hyperparameters)
Composite type used for reporting the results of daily rolling hyperparameter optimization strategy. The fields are self explanatory.
"""
struct portfolioallocations
    dates
    allocations
    hyperparameters
    returns
end

"""
    nolookbackpredictions(Results::Dict, data::Dict, o::Dict; testperiodstart = Date(2013, 1, 1), optimizationperiod = Month(1))
Constructs a portfolio while trying to circumvent the look ahead bias.

The hyperparameters of the strategy are redetermined every day by constructing a return surface on the hyperparameter space based on the returns of {t-1,...,t-`optimizationperiod`}
and taking the argmin as the hyperparameter configuration for time t. The return surface may also be smoothed optionally using `o[:smoothingdims]`.
"""
function nolookbackpredictions(Results::Dict, data::Dict, o::Dict; testperiodstart = Date(2013, 1, 1), optimizationperiod = Month(12), alpha = 1)
    ind = findfirst(x -> x <= o[:periodend], data[:dates]):findlast(x -> x >= o[:periodstart], data[:dates])
    RealizedReturns = data[:stockreturns][ind,:]
    RealizedReturns[ismissing.(RealizedReturns)] .= 0
    datevec = data[:dates][ind]
    portfolios = Any[]
    ReturnsDict = Dict()
    [ReturnsDict[key] = sum(value .* RealizedReturns, dims = 2) for (key, value) in Results];
    ReturnsArray = zeros(length(keys(Results)), length(first(ReturnsDict)[2]))
    [ReturnsArray[key...,:] = ReturnsDict[key] for (key, value) in ReturnsDict];
    startdate = data[:dates][o[:periodend] .>= data[:dates] .>= testperiodstart][end]
    oldportfolio = Array{Any, 2}(undef, 1, length(data[:stocks]))
    for date in data[:dates][o[:periodend] .>= data[:dates] .>= testperiodstart][end:-1:1]
        fs = findfirst(x -> x .< date, datevec) + 1
        ls = findlast(x -> x .>= date - optimizationperiod - Day(1), datevec)
        periodreturns = zeros(length(keys(Results)))
        for i in CartesianIndices(periodreturns)
            rtar = ReturnsArray[i,fs:ls]
            periodreturns[i] = prod(rtar .* alpha.^(1:length(rtar)) .+ 1)
        end
        bestparam = findmax(periodreturns)[2]
        pcadays = bestparam
        o[:currentdatepointer] = date
        o[:PCAdays] = pcadays
        newportfolio = date == startdate ? rankingnexplicitchurn(data, o) : rankingnexplicitchurn(data, o, oldportfolio)
        oldportfolio = newportfolio
        println(date)
        push!(portfolios, hcat(date, pcadays, sum(skipmissing(RealizedReturns[datevec .== date, :] .* oldportfolio)), oldportfolio))
    end
    portfoliomatrix = vcat(reverse(portfolios)...)
    @assert (o[:resultmode] == :struct) | (o[:resultmode] == :matrix) "The valid choices for o[:resultmode] are `:struct` or `:matrix`."
    o[:resultmode] == :struct ? portfolioallocations(portfoliomatrix[:,1], portfoliomatrix[:,4:end], portfoliomatrix[:,2], portfoliomatrix[:,3]) : portfoliomatrix
end

function gridupdater(data)
    updateuntil = data[:dates][2]
    initdir = @__DIR__
    cd(initdir * "\\Grid")
    GridCurrent = load("DailyGrid.jld")
    o = Dict()
    if updateuntil == GridCurrent["Dates"][1]
        println("Grid search is up to date!")
        return
    end
    o[:periodstart] = GridCurrent["Dates"][1] + Day(1)
    o[:periodend] = updateuntil
    o[:matrixretrospectionperiod] = Month(6)
    o[:numberofstocks] = 15
    o[:churn] = 2 * 1 / o[:numberofstocks]
    datevec = data[:dates][(data[:dates] .>= o[:periodstart]).&(data[:dates] .<= o[:periodend])]
    for (key, value) in GridCurrent["Results"]
        PCAdays = key
        o[:PCAdays] = PCAdays
        PortfolioAllocations = Any[]
        oldportfolio = reshape(GridCurrent["Results"][key][1,:], 1, :)
        for date in datevec[end:-1:1]
            o[:currentdatepointer] = date
            newportfolio = rankingnexplicitchurn(data, o, oldportfolio)
            push!(PortfolioAllocations, newportfolio)
            oldportfolio = newportfolio
        end
        PortfolioAllocations = reverse(vcat(PortfolioAllocations...), dims = 1)
        GridCurrent["Results"][key] =  vcat(PortfolioAllocations, value)
    end
    GridCurrent["Dates"] = vcat(datevec, GridCurrent["Dates"])
    save("DailyGrid.jld", "Results", GridCurrent["Results"], "Dates", GridCurrent["Dates"], "Parameters", GridCurrent["Parameters"])
    cd(initdir)
end

#=
data = customdatainit()
GridResults = load("DailyGrid.jld")

o = Dict()
o[:matrixretrospectionperiod] = Month(6)
o[:numberofstocks] = 15
o[:churn] = 2 * 1/o[:numberofstocks] #[0.05, 0.3]
o[:periodend] = Date(2019, 4, 17)
o[:periodstart] = Date(2012, 1, 1)
o[:resultmode] = :struct
=#

#=
Results = GridResults["Results"]
testperiodstart = Date(2013, 1, 1)
optimizationperiod = Month(12)
alpha = 0.99
=#
#=
o = Dict()
o[:matrixretrospectionperiod] = Month(6)
o[:numberofstocks] = 15
#o[:PCAdays] = 4
o[:churn] = 2 * 1/o[:numberofstocks] #[0.05, 0.3]

o[:periodend] = Date(2019, 4, 17)
o[:periodstart] = Date(2012, 1, 1)

data = customdatainit()
Results = Dict()
for pcadays in 1:10
    o[:PCAdays] = pcadays
    println((:PcaDays, pcadays))
    PortfolioAllocations = portfolioconstructor(data, o)
    PortfolioAllocations = [ismissing(x) ? 0.0 : x for x in PortfolioAllocations]
    Results[pcadays] = PortfolioAllocations#prod(dailyreturns .+ 1).^(1/9) .- 1, std(dailyreturns) .* sqrt(250)
end

load("DailyGrid.jld")
save("DailyGrid.jld", "Results", Results, "Dates", data[:dates][(data[:dates].>=o[:periodstart]).&(data[:dates].<=o[:periodend])], "Parameters", [:PCAdays])
=#

function deletelastgrid()
    rootdir = @__DIR__
    cd(rootdir * "\\Grid")
    GridCurrent = load("DailyGrid.jld")
    DateVec = GridCurrent["Dates"][2:end]
    Results = Dict()
    for (k,v) in GridCurrent["Results"]
        Results[k] = v[2:end,:]
    end
    rm(pwd() * "\\DailyGrid.jld")
    save("DailyGrid.jld", "Results", Results, "Dates", DateVec, "Parameters", [:PCAdays])
    cd(rootdir)
end

#=
dt = data[:dates][1]
function readlastportfolio(data, o; dt = data[:dates][1])
    ws, ys = data[:dates][data[:dates] .< dt][[1,2]]
    y, m, d = yearmonthday(ws)
    wsn = string.(d, ".",m, ".",y)
    stocknames = readxl("CRE Allocations.xlsx", wsn * "!A3:A17")[:]
    oldportfolio = zeros(size(data[:stocks]))
    oldportfolio[indexin(stocknames, data[:stocks])] .= 1/o[:numberofstocks]
    y, m, d = yearmonthday(ys)
    ysn = string.(d, ".",m, ".",y)
    stocknamestda = readxl("CRE Allocations.xlsx", ysn * "!A3:A17")[:]
    twodayagoportfolio = zeros(size(data[:stocks]))
    twodayagoportfolio[indexin(stocknamestda, data[:stocks])] .= 1/o[:numberofstocks]
    oldportfolio, stocknames, twodayagoportfolio, stocknamestda
end


deletelastgrid()
data = customdatainit()
gridupdater(data)

A = load("DailyGrid.jld")
rootdir = @__DIR__
cd(rootdir * "\\Grid")
B = load("DailyGrid.jld")
A["Results"] == B["Results"]
=#
function dailyrollingstrategy()
    o = Dict()
    o[:matrixretrospectionperiod] = Month(6)
    o[:numberofstocks] = 15
    #o[:PCAdays] = 4
    o[:churn] = 2 * 1/o[:numberofstocks] #[0.05, 0.3]

    data = customdatainit()
    oldportfolio, currentstocks, yesterdayportfolio, yesterdaystocks = readlastportfolio(data, o)

    o[:currentdatepointer] = first(data[:dates]) + Day(1)
    gridupdater(data)
    function readgrid()
        rootdir = @__DIR__
        cd(rootdir * "\\Grid")
        GridCurrent = load("DailyGrid.jld")
        cd(rootdir)
        return GridCurrent
    end
    GridCurrent = readgrid()

    fd = GridCurrent["Dates"][1]
    ld = GridCurrent["Dates"][1] - Year(1) + Day(1)

    dataind = findfirst(x -> x <= fd, data[:dates]):findlast(x -> x >= ld, data[:dates])
    gridind = findfirst(x -> x <= fd, GridCurrent["Dates"]):findlast(x -> x >= ld, GridCurrent["Dates"])

    returngrid = zeros(length(keys(GridCurrent["Results"])))
    for (k,v) in GridCurrent["Results"]
        rt = sum(v[gridind,:] .* data[:stockreturns][dataind,:], dims = 2)
        returngrid[k] = prod(0.995.^collect(1:length(rt)) .* rt .+ 1)
    end
    pcadays = findmax(returngrid)[2]
    o[:PCAdays] = pcadays

    ind = findfirst(x -> x < o[:currentdatepointer], data[:dates]):findlast(x -> x >= o[:currentdatepointer] - o[:matrixretrospectionperiod], data[:dates])
    data[:dates][ind]
    RelevantReturn = data[:stockreturns][ind, :]

    n = sum([!in(missing, Set(RelevantReturn[:, i])) for i in 1:size(RelevantReturn, 2)])
    reconstructed = inversePCA(PCA(RelevantReturn[:,1:n], typeofSim = :cov, normtype = 2, featurenum = 1))[1:o[:PCAdays], :]'
    realized = RelevantReturn[1:o[:PCAdays], 1:n]'
    returnspread = reconstructed - realized
    returnspreadndays = prod(returnspread .+ 1, dims = 2) .- 1
    rankstat = sortperm(sortperm(returnspreadndays[1:end], rev = true))

    m = Model(with_optimizer(GLPK.Optimizer))
    @variable(m, 0 <= x[1:length(rankstat)] <= 1/o[:numberofstocks])
    @variable(m, z[1:length(rankstat)])
    @objective(m, Min, dot(x, rankstat))
    @constraint(m, sum(x) == 1)
    @constraint(m, [i = 1:length(x)], z[i] - x[i] >= -oldportfolio[i])
    @constraint(m, [i = 1:length(x)], z[i] + x[i] >= oldportfolio[i])
    @constraint(m, sum(z) <= 2*o[:churn])
    optimize!(m)

    output = reshape(Array(value.(x)), 1, :)[:]
    longs = collect(1:length(output))[isapprox.(output, 1/o[:numberofstocks])]
    shorts = collect(1:length(output))[.!isapprox.(output, 1/o[:numberofstocks])]
    imatlong = hcat(data[:stocks], reconstructed, realized, returnspread, returnspreadndays, rankstat)[longs,:]
    imatshort = hcat(data[:stocks], reconstructed, realized, returnspread, returnspreadndays, rankstat)[shorts,:]

    imat = vcat(imatlong[sortperm(rankstat[longs], rev = false), :], imatshort[sortperm(rankstat[shorts], rev = false), :])

    wb = openpyxl.load_workbook("CRE Allocations.xlsx")

    y, m, d = yearmonthday(o[:currentdatepointer] - Day(1))
    wsn = string.(d, ".",m, ".",y)
    ws = wb.create_sheet(wsn, 1)

    datehead = reshape(data[:dates][data[:dates] .< o[:currentdatepointer]][1:o[:PCAdays]], 1, :)
    ndays = length(datehead)

    py"""
    import openpyxl

    def setcolwidth(ws, col, w):
        ws.column_dimensions[col].width = w
    """
    for i in 1:(1+3*ndays)
        py"setcolwidth"(ws, openpyxl.utils.cell.get_column_letter(i), 12.71)
    end
    py"setcolwidth"(ws, openpyxl.utils.cell.get_column_letter(2+3*ndays), 21)
    py"setcolwidth"(ws, openpyxl.utils.cell.get_column_letter(3+3*ndays), 12.71)
    py"setcolwidth"(ws, openpyxl.utils.cell.get_column_letter(4+3*ndays), 9.14)
    py"setcolwidth"(ws, openpyxl.utils.cell.get_column_letter(5+3*ndays), 33.71)

    function openpyxlarraywriter(array::Array, refcell, ws)
        r, c = refcell
        for i in 1:size(array, 1), j in 1:size(array,2)
            ws.cell(row = i+r-1, column = j+c-1, value = array[i,j])
        end
    end
    function openpyxlarrayreader(cellrangestopleft, cellrangesbottomright, ws)
        y0, x0 = cellrangestopleft
        y1, x1 = cellrangesbottomright
        output = Array{Any}(undef, y1 - y0 + 1, x1- x0 + 1)
        for i in y0:y1, j in x0:x1
            output[i-y0+1, j-x0+1] = ws.cell(row =  i, column = j).value
        end
        output
    end
    openpyxlarraywriter(hcat(datehead, datehead, datehead), (2, 2), ws)
    openpyxlarraywriter(imat, (3, 1), ws)
    ws.cell(row = 2, column = 2 + 3 * ndays, value = "$(ndays) Days")

    r,c = size(imat)
    for i in 3:r+2, j in 2:c-1
        ws.cell(row = i, column = j).number_format = "0.00%"
    end

    for j in 2:c-1
        ws.cell(row = 2, column = j).number_format = "d.mm.yyyy"
    end

    ws.merge_cells(start_row = 1, start_column = 2, end_row = 1, end_column = ndays + 1)
    ws.cell(row = 1, column = 2, value = "PCA").alignment =  openpyxl.styles.Alignment(horizontal="center", vertical="center")
    ws.merge_cells(start_row = 1, start_column = ndays + 2, end_row = 1, end_column = 2 * ndays + 1)
    ws.cell(row = 1, column = ndays + 2, value = "Real").alignment =  openpyxl.styles.Alignment(horizontal="center", vertical="center")
    ws.merge_cells(start_row = 1, start_column = 2 * ndays + 2, end_row = 1, end_column = 3 * ndays + 1)
    ws.cell(row = 1, column = 2 * ndays + 2, value = "Spread").alignment =  openpyxl.styles.Alignment(horizontal="center", vertical="center")
    ws.cell(row = 1, column = 3 * ndays + 2, value = "Compounded Spread")
    ws.merge_cells(start_row = 1, start_column =  3 * ndays + 3, end_row = 2, end_column =  3 * ndays + 3)
    ws.cell(row = 1, column = 3 * ndays + 3, value = "Rank").alignment =  openpyxl.styles.Alignment(horizontal="center", vertical="center")
    ws.freeze_panes = "B3"

    y, m, d = yearmonthday(datehead[2])
    rtday = string.(d, ".",m, ".",y)
    ws.cell(row = 3, column = 5+3*ndays, value = "Strategy Return on " * rtday)
    ws.cell(row = 4, column = 5+3*ndays, value = sum(data[:stockreturns][2,:] .* yesterdayportfolio)).number_format = "0.00%"
    ws.cell(row = 6, column = 5+3*ndays, value = "Buy and Hold Return on " * rtday)
    ws.cell(row = 7, column = 5+3*ndays, value = mean(data[:stockreturns][2,:])).number_format = "0.00%"
    ws.cell(row = 9, column = 5+3*ndays, value = "XU030 Return on " * rtday)
    ws.cell(row = 10, column = 5+3*ndays, value = data[:securitiesreturns][2,1]).number_format = "0.00%"

    ins = data[:stocks][isapprox.((output - oldportfolio), 1/o[:numberofstocks])]
    outs = data[:stocks][isapprox.((output - oldportfolio), -1/o[:numberofstocks])]

    for i in indexin(ins, imat[:,1]) .+ 2, j in 1:size(imat, 2)
        ws.cell(row = i, column = j).fill = openpyxl.styles.PatternFill(patternType = "solid", fill_type = "solid", fgColor = "0092D050")
    end
    for i in indexin(outs, imat[:,1]) .+ 2, j in 1:size(imat, 2)
        ws.cell(row = i, column = j).fill = openpyxl.styles.PatternFill(patternType = "solid", fill_type = "solid", fgColor = "00FF3300")
    end

    thick = openpyxl.styles.Side(border_style = "medium", color = "00000000")
    thin = openpyxl.styles.Side(border_style = "thin", color = "00000000")
    double = openpyxl.styles.Side(border_style = "double", color = "00000000")
    noborder = openpyxl.styles.Side(border_style = nothing, color = "00FFFFFF")
    for j in 1:size(imat, 2)
        ws.cell(row = 3, column = j).border = openpyxl.styles.Border(top = thick)
        ws.cell(row = 18, column = j).border = openpyxl.styles.Border(top = double)
    end

    ws.cell(row = 3, column = 5+3*ndays).border = openpyxl.styles.Border(top = thick, right = thick, left = thick, bottom = thin)
    ws.cell(row = 4, column = 5+3*ndays).border = openpyxl.styles.Border(right = thick, left = thick, bottom = thick)
    ws.cell(row = 6, column = 5+3*ndays).border = openpyxl.styles.Border(top = thick, right = thick, left = thick, bottom = thin)
    ws.cell(row = 7, column = 5+3*ndays).border = openpyxl.styles.Border(right = thick, left = thick, bottom = thick)
    ws.cell(row = 9, column = 5+3*ndays).border = openpyxl.styles.Border(top = thick, right = thick, left = thick, bottom = thin)
    ws.cell(row = 10, column = 5+3*ndays).border = openpyxl.styles.Border(right = thick, left = thick, bottom = thick)

    ws = wb._sheets[1]
    i = 0
    while !isnothing(ws.cell(row = i + 4, column = 2).value)
        i += 1
    end

    ### Stat page updates starts here

    dailylog = openpyxlarrayreader((4,2), (i + 3, 7), ws)
    months = unique(monthname.(dailylog[:,1]))
    strat = sum(data[:stockreturns][2,:] .* yesterdayportfolio)
    buynhold = mean(data[:stockreturns][2,:])
    xu030ret = data[:securitiesreturns][2,1]
    dailylog = vcat([DateTime(datehead[2]) strat buynhold xu030ret strat - buynhold strat - xu030ret], dailylog)
    totalcompound = prod(dailylog[:,2:4] .+ 1, dims = 1) .- 1
    openpyxlarraywriter(vcat(["Total" totalcompound totalcompound[1] - totalcompound[2] totalcompound[1] - totalcompound[3]], dailylog), (3, 2), ws)
    array2compute = [reshape([monthname(dailylog[i, 1]), dailylog[i, 2:4]...], 1, 4) for i in 1:size(dailylog, 1)]
    monthlystats = Any[]
    for mnth in months[end:-1:1]
        monthly = prod(vcat(filter(x->x[1] == mnth, array2compute)...)[:,2:end] .+ 1, dims = 1) .- 1
        push!(monthlystats, vcat(mnth, [monthly monthly[1] - monthly[2] monthly[1] - monthly[3]]'))
    end
    openpyxlarraywriter(hcat(monthlystats...), (2, 11), ws)
    cellrangestopleft = (2,2)
    cellrangesbottomright = (i+4, 7)
    y0, x0 = cellrangestopleft
    y1, x1 = cellrangesbottomright
    bottomleftcorner = openpyxl.styles.Border(left = openpyxl.styles.Side(border_style = "medium", color = "00000000"), right = openpyxl.styles.Side(border_style = "thin", color = "00000000"), top = openpyxl.styles.Side(border_style = nothing, color = "00FFFFFF"), bottom = openpyxl.styles.Side(border_style = "medium", color = "00000000"))
    bottommedium = openpyxl.styles.Border(bottom = openpyxl.styles.Side(border_style = "medium", color = "00000000"), top = openpyxl.styles.Side(border_style = nothing, color = "00FFFFFF"))
    bottomrightcorner = openpyxl.styles.Border(bottom = openpyxl.styles.Side(border_style = "medium", color = "00000000"), right = openpyxl.styles.Side(border_style = "medium", color = "00000000"), top = openpyxl.styles.Side(border_style = nothing, color = "00FFFFFF"))
    ws.cell(row = y1, column = 2).border = bottomleftcorner
    ws.cell(row = y1, column = 2).number_format = "d.mm.yyyy"
    for j in 3:6
        ws.cell(row = y1, column = j).border = bottommedium
        ws.cell(row = y1, column = j).number_format = "0.00%"
    end
    ws.cell(row = y1, column = 7).border = bottomrightcorner
    ws.cell(row = y1, column = 7).number_format = "0.00%"
    ws.cell(row = y1-1, column = 2).border = openpyxl.styles.Border(left = openpyxl.styles.Side(border_style = "medium", color = "00000000"), bottom = openpyxl.styles.Side(border_style = nothing, color = "00FFFFFF"), right = openpyxl.styles.Side(border_style = "thin", color = "00000000"))
    for j in 3:6
        ws.cell(row = y1-1, column = j).border = openpyxl.styles.Border(bottom = openpyxl.styles.Side(border_style = nothing, color = "00FFFFFF"))
    end
    ws.cell(row = y1-1, column = 7).border = openpyxl.styles.Border(bottom = openpyxl.styles.Side(border_style = nothing, color = "00FFFFFF"), right = openpyxl.styles.Side(border_style = "medium", color = "00000000"))
    ### Stat page updates end here.
    wb.save("CRE Allocations.xlsx")
    println("CRE Allocations.xlsx is updated for $(first(data[:dates]))!")
end

dailyrollingstrategy()
