module ResultsReporter

export quarterlyportfoliostats, results2excel

using StatsBase, LinearAlgebra, Statistics, DataStructures, DateHandler, XLSX

portfolioreturns(PortfolioAllocations::Array{Float64,2}, RealizedReturns::Array{Float64,2}) = prod(sum(PortfolioAllocations .* RealizedReturns, dims = 2) .+ 1) .- 1

portfolioreturns(RealizedReturns::Array{Float64,2}) = prod(mean(RealizedReturns, dims = 2) .+ 1) .- 1

portfoliovols(PortfolioAllocations::Array{Float64,2}, RealizedReturns::Array{Float64,2}) = std(sum(PortfolioAllocations .* RealizedReturns, dims = 2)) * 250^(.5)

portfoliovols(RealizedReturns::Array{Float64,2}) = std(mean(RealizedReturns, dims = 2)) * 250^(.5)

function portfoliomaxdrawdown(PortfolioAllocations::Array{Float64,2}, RealizedReturns::Array{Float64,2})
    r = sum(PortfolioAllocations .* RealizedReturns, dims = 2)  .+ 1
    levels = cumprod(r[end:-1:1], dims = 1)[end:-1:1]
    peak = accumulate(max, levels[end:-1:1])[end:-1:1]
    levels .== peak
    through = ones(size(levels))
    maxdrawdown = zeros(size(levels))
    for i = length(levels):-1:1
        through[i] = levels[i] .== peak[i] ? peak[i] : min(levels[i], through[i+1])
    end
    maximum((peak - through) ./ peak)
end

function portfoliomaxdrawdown(RealizedReturns::Array{Float64,2})
    r = mean(RealizedReturns, dims = 2) .+ 1
    levels = cumprod(r[end:-1:1], dims = 1)[end:-1:1]
    peak = accumulate(max, levels[end:-1:1])[end:-1:1]
    levels .== peak
    through = ones(size(levels))
    maxdrawdown = zeros(size(levels))
    for i = length(levels):-1:1
        through[i] = levels[i] .== peak[i] ? peak[i] : min(levels[i], through[i+1])
    end
    maximum((peak - through) ./ peak)
end

function portfoliomaxdrawdown(RealizedReturns::Vector{Float64})
    r = RealizedReturns .+ 1
    levels = cumprod(r[end:-1:1], dims = 1)[end:-1:1]
    peak = accumulate(max, levels[end:-1:1])[end:-1:1]
    levels .== peak
    through = ones(size(levels))
    maxdrawdown = zeros(size(levels))
    for i = length(levels):-1:1
        through[i] = levels[i] .== peak[i] ? peak[i] : min(levels[i], through[i+1])
    end
    maximum((peak - through) ./ peak)
end

churn(PortfolioAllocations::Array) = mean(sum(abs, PortfolioAllocations[1:end-1,:] .- PortfolioAllocations[2:end,:], dims = 2) / 2)

function portfoliostats(PortfolioAllocations, StockReturns, IndexReturns)
    stats = OrderedDict()
    stats[:StrategyReturn] = portfolioreturns(PortfolioAllocations, StockReturns)
    stats[:BuynHoldReturn] = portfolioreturns(StockReturns)
    stats[:BenchmarkReturn] = prod(IndexReturns[:,1] .+ 1) .- 1
    stats[:StrategyVol] = portfoliovols(PortfolioAllocations, StockReturns)
    stats[:BuynHoldVol] = portfoliovols(StockReturns)
    stats[:BenchmarkVol] = std(IndexReturns[:,1]) * 250^(.5)
    stats[:StrategyMaxDraw] = portfoliomaxdrawdown(PortfolioAllocations, StockReturns)
    stats[:BuynHoldMaxDraw] = portfoliomaxdrawdown(StockReturns)
    stats[:BenchmarkMaxDraw] = portfoliomaxdrawdown(IndexReturns[:,1])
    stats[:PortfolioChurn] = churn(PortfolioAllocations)
    return stats
end

function statsdict2statsmatrix(quarterlystats::OrderedDict)
    mat = hcat([collect(values(value)) for (key, value) in quarterlystats]...)
    mi = hcat(string.(collect(keys(first(quarterlystats)[2]))), mat, mean(mat, dims = 2))
    headers = hcat("", string.(collect(keys(quarterlystats)))..., "Mean")
    vcat(headers, mi)
end

function quarterlyportfoliostats(data, o, PortfolioAllocations)
    SignalDates = data[:dates][data[:dates] .>= o[:initialstart]]
    QuarterDates = DateHandler.QuarterlyDateParser(SignalDates)
    RealizedReturns = data[:stockreturns][data[:dates] .>= o[:initialstart],:]
    RealizedIndices = data[:securitiesreturns][data[:dates] .>= o[:initialstart],:]
    quarterlystats = OrderedDict()
    for qt in sort(collect(keys(QuarterDates)))
        QuarterHoldings = Date2Data(PortfolioAllocations, SignalDates, QuarterDates[qt])
        QuarterActuals = Date2Data(RealizedReturns, SignalDates, QuarterDates[qt])
        QuarterIndices = Date2Data(RealizedIndices, SignalDates, QuarterDates[qt])
        quarterlystats[qt] = portfoliostats(QuarterHoldings, QuarterActuals, QuarterIndices)
    end
    statsdict2statsmatrix(quarterlystats)
end

function writematrix(sheet::XLSX.Worksheet, data::Array; anchor_cell::XLSX.CellRef=XLSX.CellRef("A1"))
    row_count = size(data, 1)
    col_count = size(data, 2)
    anchor_row = XLSX.row_number(anchor_cell)
    anchor_col = XLSX.column_number(anchor_cell)
    # write table data
    for i in 1:row_count, j in 1:col_count
        target_cell_ref = XLSX.CellRef(i + anchor_row - 1, j + anchor_col - 1)
        sheet[target_cell_ref] = data[i, j]
    end
end

function results2excel(FileName::String, Result::Array; headers = true)
    if headers == true
        XLSX.openxlsx(FileName * ".xlsx", mode = "w") do xf
            Sheet = xf[1]
            XLSX.rename!(Sheet, "Results")
            AnchorCell = XLSX.CellRef("A1")
            XLSX.writetable!(Sheet, [Result[2:end, i] for i in 1:size(Result, 2)], Result[1,:], anchor_cell = AnchorCell)
            Sheet[AnchorCell] = FileName
        end
    elseif headers == false
        XLSX.openxlsx(FileName * ".xlsx", mode = "w") do xf
            Sheet = xf[1]
            XLSX.rename!(Sheet, "Results")
            AnchorCell = XLSX.CellRef("A1")
            writematrix(Sheet, Result, anchor_cell = AnchorCell)
        end
    end
end

function results2excel(FileName::String, Results::Dict; headers = true)
    if headers == true
        XLSX.openxlsx(FileName * ".xlsx", mode = "w") do xf
            Sheet = xf[1]
            XLSX.rename!(Sheet, "Results")
            AnchorCell = XLSX.CellRef("A1")
            for key in sort(collect(keys(Results)))
                Sheet[AnchorCell] = string(key)
                AnchorCell = XLSX.CellRef(XLSX.row_number(AnchorCell) + 1, XLSX.column_number(AnchorCell))
                XLSX.writetable!(Sheet, [Results[key][2:end, i] for i in 1:size(Results[key], 2)], Results[key][1,:], anchor_cell = AnchorCell)
                AnchorCell = XLSX.CellRef(XLSX.row_number(AnchorCell) + size(Results[key], 1) + 2, XLSX.column_number(AnchorCell))
            end
        end
    elseif headers == false
        XLSX.openxlsx(FileName * ".xlsx", mode = "w") do xf
            Sheet = xf[1]
            XLSX.rename!(Sheet, "Results")
            AnchorCell = XLSX.CellRef("A1")
            for key in sort(collect(keys(Results)))
                Sheet[AnchorCell] = string(key)
                AnchorCell = XLSX.CellRef(XLSX.row_number(AnchorCell) + 1, XLSX.column_number(AnchorCell))
                writematrix(Sheet, Results, anchor_cell = AnchorCell)
                AnchorCell = XLSX.CellRef(XLSX.row_number(AnchorCell) + size(Results[key], 1) + 2, XLSX.column_number(AnchorCell))
            end
        end
    end
end

end
