struct ProblemData
    tempo::Matrix{Float64}
    demandaPeso::Vector{Float64}
    demandaVolume::Vector{Float64}
    capPeso::Vector{Float64}
    capVolume::Vector{Float64}
    fretes::Dict{Tuple{Int,Int},Float64}
    vehiclesByStore::Dict{Int,BitSet}
    nStores::Int
    nVehicles::Int
end

@inline function parse_number(x::AbstractString)
    s = lowercase(replace(strip(x), ',' => '.'))
    s == "inf" && return Inf
    s == "+inf" && return Inf
    s == "-inf" && return -Inf
    return parse(Float64, s)
end
@inline parse_int(x::AbstractString) = parse(Int, strip(x))

function detect_section(tokens)
    t = Set(lowercase.(tokens))

    if all(x -> x in t, ["store1", "store2", "tempo_deslocamento"])
        return :tempo
    elseif all(x -> x in t, ["store", "demanda_peso", "demanda_volume"])
        return :demanda
    elseif all(x -> x in t, ["vehicles", "capacidade_peso", "capacidade_volume"])
        return :capacidade
    elseif all(x -> x in t, ["store", "vehicle", "valor_frete"])
        return :frete
    end

    return nothing
end

function readData(path)
    println("Lendo dados")

    tempoRows = Tuple{Int,Int,Float64}[]
    demandaRows = Tuple{Int,Float64,Float64}[]
    capacidadeRows = Tuple{Int,Float64,Float64}[]
    freteRows = Tuple{Int,Int,Float64}[]

    section = nothing

    open(path, "r") do io
        for rawLine in eachline(io)
            line = strip(rawLine)
            isempty(line) && continue

            tokens = split(line)
            detected = detect_section(tokens)

            if detected !== nothing
                section = detected
                continue
            end

            section === nothing && continue

            try
                if section === :tempo && length(tokens) >= 3
                    push!(tempoRows, (parse_int(tokens[1]), parse_int(tokens[2]), parse_number(tokens[3])))
                elseif section === :demanda && length(tokens) >= 3
                    push!(demandaRows, (parse_int(tokens[1]), parse_number(tokens[2]), parse_number(tokens[3])))
                elseif section === :capacidade && length(tokens) >= 3
                    push!(capacidadeRows, (parse_int(tokens[1]), parse_number(tokens[2]), parse_number(tokens[3])))
                elseif section === :frete && length(tokens) >= 3
                    valor = lowercase(tokens[3]) == "inf" ? Inf : parse_number(tokens[3])
                    push!(freteRows, (parse_int(tokens[1]), parse_int(tokens[2]), valor))
                end
            catch err
                error("Erro lendo linha '$line' em $path: $err")
            end
        end
    end

    isempty(demandaRows) && error("Secao de demanda nao encontrada em $path")
    isempty(capacidadeRows) && error("Secao de capacidade nao encontrada em $path")

    nStores = maximum(r[1] for r in demandaRows)
    nVehicles = maximum(r[1] for r in capacidadeRows)

    tempo = fill(Inf, nStores, nStores)
    for s in 1:nStores
        tempo[s,s] = 0.0
    end
    for (i,j,t) in tempoRows
        i <= nStores && j <= nStores && (tempo[i,j] = t)
    end

    demandaPeso = zeros(Float64, nStores)
    demandaVolume = zeros(Float64, nStores)
    for (s,peso,volume) in demandaRows
        demandaPeso[s] = peso
        demandaVolume[s] = volume
    end

    capPeso = zeros(Float64, nVehicles)
    capVolume = zeros(Float64, nVehicles)
    for (v,peso,volume) in capacidadeRows
        capPeso[v] = peso
        capVolume[v] = volume
    end

    fretes = Dict{Tuple{Int,Int},Float64}()
    vehiclesByStore = Dict{Int,BitSet}()

    for (s,v,custo) in freteRows
        fretes[(s,v)] = custo

        if isfinite(custo)
            push!(get!(vehiclesByStore, s, BitSet()), v)
        end
    end

    return ProblemData(tempo, demandaPeso, demandaVolume, capPeso, capVolume, fretes, vehiclesByStore, nStores, nVehicles)
end

function ler_janelas_recebimento(path)
    rows = Tuple{Int,Float64,Float64}[]

    open(path, "r") do io
        for rawLine in eachline(io)
            tokens = split(strip(rawLine))
            length(tokens) < 3 && continue

            try
                s = parse_int(tokens[1])
                inicio = parse_number(tokens[2])
                fim = parse_number(tokens[3])
                push!(rows, (s,inicio,fim))
            catch
                continue
            end
        end
    end

    isempty(rows) && error("Nenhuma janela de recebimento encontrada em $path")

    nStores = maximum(r[1] for r in rows)
    windows = fill((0.0, Inf), nStores)

    for (s,inicio,fim) in rows
        windows[s] = (inicio,fim)
    end

    return windows
end
