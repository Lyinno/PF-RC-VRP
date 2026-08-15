using DataFrames


smartparse(x::AbstractString) = begin
    s = replace(strip(String(x)), ',' => '.')
    s == "" ? missing :
    occursin(r"^[+-]?\d+$", s) ? parse(Int, s) :
    occursin(r"^[+-]?(?:\d+\.\d*|\d*\.\d+)$", s) ? parse(Float64, s) :
    lowercase(s) == "inf" ? Inf : s
end


function rows_to_df(data)
    conv = [smartparse.(row) for row in data]
    hdr = Symbol.(conv[1])
    rows = conv[2:end]
    n = length(hdr)
    rows = filter(r -> length(r) == n, rows)
    cols = [getindex.(rows, j) for j in 1:n]
    DataFrame(cols, hdr)
end


function readData(path)
    println("Lendo dados")
    lines = readlines(path)
    dfs = []
    df = []
    for line in lines
        itens = split(strip(line), r"\s+")
        if length(itens) == 1
            continue
        end
        if any(x -> occursin(r"[A-Za-z]", x) && lowercase(x) != "inf", itens)
            if length(df) != 0
                push!(dfs,df)
                df = []
            end
        end
        push!(df, itens)
    end

    if !isempty(df)
        push!(dfs, df)
    end

    allDfs = []
    for df in dfs
        finalDf = rows_to_df(df)
        push!(allDfs, finalDf)
    end
    return allDfs
end
