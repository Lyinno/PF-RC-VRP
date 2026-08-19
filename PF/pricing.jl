using JuMP
using HiGHS
import MathOptInterface as MOI


function wait_for_available_memory(minFreeRamGB)
    minFreeBytes = minFreeRamGB * 1024^3

    while Sys.free_memory() < minFreeBytes
        sleep(0.1)
    end
end


function route_key(rota)
    return Tuple(sort(unique(rota[2:end-1])))
end


function extract_route(z, nodes, arcSet)
    CD = 1
    rota = [CD]
    atual = CD

    for _ in 1:(length(nodes) + 1)
        proximo = nothing

        for j in nodes
            if j != atual && ((atual,j) in arcSet) && value(z[(atual,j)]) > 0.5
                proximo = j
                break
            end
        end

        proximo === nothing && error("Rota quebrada: não existe arco saindo do nó $atual.")

        push!(rota, proximo)

        if proximo == CD
            return rota
        end

        atual = proximo
    end

    error("Erro ao extrair rota: ciclo inesperado.")
end


function solve_pricing_vehicle(v, π, αv, vehiclesByStore, tempo, fretes, demandaPeso, demandaVolume, capPeso, capVolume, max_t, t_descarga, rotasExistentes, timeWindows)
    CD = 1

    # Elimina lojas que esse veículo jamais conseguiria atender, mesmo sozinhas.
    lojas = [s for s in 2:size(tempo,1) if
        v in get(vehiclesByStore,s,Int[]) &&
        demandaPeso[s] <= capPeso[v] &&
        demandaVolume[s] <= capVolume[v] &&
        isfinite(tempo[CD,s]) &&
        isfinite(tempo[s,CD]) &&
        tempo[CD,s] + t_descarga + tempo[s,CD] <= max_t
    ]

    isempty(lojas) && return nothing

    nodes = [CD; lojas]
    N = length(lojas)

    arcos = Tuple{Int,Int}[]

    for s in lojas
        push!(arcos, (CD,s))
        push!(arcos, (s,CD))
    end

    for i in lojas, j in lojas
        if i == j || !isfinite(tempo[i,j])
            continue
        end

        # Se i e j juntos já excedem capacidade, esse arco nunca poderá ser utilizado.
        if demandaPeso[i] + demandaPeso[j] > capPeso[v] || demandaVolume[i] + demandaVolume[j] > capVolume[v]
            continue
        end

        # Mesmo na rota mínima CD -> i -> j -> CD, o tempo já seria excessivo.
        if tempo[CD,i] + t_descarga + tempo[i,j] + t_descarga + tempo[j,CD] > max_t
            continue
        end

        # Mesmo atendendo i no primeiro instante possível, seria impossível chegar em j antes de fechar.
        if timeWindows[i][1] + t_descarga + tempo[i,j] > timeWindows[j][2]
            continue
        end

        push!(arcos, (i,j))
    end

    arcSet = Set(arcos)

    saidas = Dict(i => Tuple{Int,Int}[] for i in nodes)
    entradas = Dict(i => Tuple{Int,Int}[] for i in nodes)

    for a in arcos
        push!(saidas[a[1]], a)
        push!(entradas[a[2]], a)
    end

    model = Model(HiGHS.Optimizer)
    set_silent(model)
    set_attribute(model, MOI.NumberOfThreads(), 1)

    @variable(model, y[lojas], Bin)
    @variable(model, z[arcos], Bin)
    @variable(model, custo >= 0)
    @variable(model, 1 <= u[lojas] <= N)

    # chegada[s] = instante em que o caminhão chega/inicia atendimento na loja s.
    @variable(model, chegada[s in lojas] >= timeWindows[s][1])
    for s in lojas
        set_upper_bound(chegada[s], timeWindows[s][2])
    end

    minOpen = minimum(timeWindows[s][1] for s in lojas)
    maxClose = maximum(timeWindows[s][2] for s in lojas)

    @variable(model, minOpen - max_t <= inicio <= maxClose)
    @variable(model, minOpen <= fim <= maxClose + max_t)

    # Uma saída e um retorno ao CD.
    @constraint(model, sum(z[a] for a in saidas[CD]) == 1)
    @constraint(model, sum(z[a] for a in entradas[CD]) == 1)

    # Se a loja é visitada, exatamente um arco entra e um sai.
    @constraint(model, entrada[s in lojas], sum(z[a] for a in entradas[s]) == y[s])
    @constraint(model, saida[s in lojas], sum(z[a] for a in saidas[s]) == y[s])

    # Elimina subtours.
    for (i,j) in arcos
        if i != CD && j != CD
            @constraint(model, u[i] - u[j] + N * z[(i,j)] <= N - 1)
        end
    end

    @constraint(model, sum(demandaPeso[s] * y[s] for s in lojas) <= capPeso[v])
    @constraint(model, sum(demandaVolume[s] * y[s] for s in lojas) <= capVolume[v])

    # Restrição agregada continua sendo uma boa restrição válida e ajuda o solver.
    @constraint(model, sum(tempo[i,j] * z[(i,j)] for (i,j) in arcos) + t_descarga * sum(y[s] for s in lojas) <= max_t)

    # CD -> primeira loja.
    for j in lojas
        a = (CD,j)

        if a in arcSet
            M = max(0.0, maxClose + tempo[CD,j] - timeWindows[j][1])
            @constraint(model, chegada[j] >= inicio + tempo[CD,j] - M * (1 - z[a]))
        end
    end

    # Loja i -> loja j.
    for (i,j) in arcos
        if i != CD && j != CD
            M = max(0.0, timeWindows[i][2] + t_descarga + tempo[i,j] - timeWindows[j][1])
            @constraint(model, chegada[j] >= chegada[i] + t_descarga + tempo[i,j] - M * (1 - z[(i,j)]))
        end
    end

    # Última loja -> CD.
    for i in lojas
        a = (i,CD)

        if a in arcSet
            M = max(0.0, timeWindows[i][2] + t_descarga + tempo[i,CD] - minOpen)
            @constraint(model, fim >= chegada[i] + t_descarga + tempo[i,CD] - M * (1 - z[a]))
        end
    end

    # Ao contrário da restrição agregada, esta também contabiliza eventuais esperas pelas janelas.
    @constraint(model, fim >= inicio)
    @constraint(model, fim - inicio <= max_t)

    for s in lojas
        @constraint(model, custo >= fretes[(s,v)] * y[s])
    end

    @objective(model, Min, custo - sum(π[s] * y[s] for s in lojas) - αv)

    optimize!(model)

    if termination_status(model) != MOI.OPTIMAL || !has_values(model)
        return nothing
    end

    rota = extract_route(z, nodes, arcSet)

    return (reduced_cost=objective_value(model), rota=rota, custo=value(custo), veiculo=v)
end


function pricing_vehicle_dir(stateDir, v)
    dir = joinpath(stateDir, "vehicle_$v")
    mkpath(dir)
    return dir
end


function read_pricing_meta(path)
    meta = Dict{String,String}()

    if !isfile(path)
        return meta
    end

    for line in eachline(path)
        isempty(strip(line)) && continue
        p = split(line, "="; limit=2)
        length(p) == 2 && (meta[p[1]] = p[2])
    end

    return meta
end


function write_pricing_meta(path, timeLimit, depth, offset, complete)
    tempPath = path * ".tmp"

    open(tempPath, "w") do io
        println(io, "time_limit=$timeLimit")
        println(io, "depth=$depth")
        println(io, "offset=$offset")
        println(io, "complete=$complete")
    end

    mv(tempPath, path; force=true)
end


function write_route_state(io, rota, peso, volume, intervalo, custo)
    println(io, join(rota, ","), '\t', peso, '\t', volume, '\t', intervalo[1], '\t', intervalo[2], '\t', intervalo[3], '\t', custo)
end


# Cache permanente: para recalcular RC só precisamos da sequência da rota e do custo.
function write_cached_route(io, rota, custo)
    println(io, join(rota, ","), '\t', custo)
end


function read_route_state(line)
    p = split(chomp(line), '\t')

    rota = parse.(Int, split(p[1], ','))
    peso = parse(Float64, p[2])
    volume = parse(Float64, p[3])
    intervalo = [parse(Float64,p[4]), parse(Float64,p[5]), parse(Float64,p[6])]
    custo = parse(Float64, p[7])

    return rota, peso, volume, intervalo, custo
end


function initialize_vehicle_pricing(v, lojas, tempo, fretes, demandaPeso, demandaVolume, max_t, t_descarga, timeWindows, stateDir, initialTimeLimit)
    CD = 1
    dir = pricing_vehicle_dir(stateDir, v)

    metaPath = joinpath(dir, "meta.txt")
    routesPath = joinpath(dir, "routes.tsv")
    frontierPath = joinpath(dir, "frontier_1.tsv")

    if isfile(metaPath)
        return
    end

    open(routesPath, "w") do routesIO
        open(frontierPath, "w") do frontierIO
            for s in lojas
                intervalo = [timeWindows[s][1] - tempo[CD,s], timeWindows[s][2] - tempo[CD,s], tempo[CD,s] + t_descarga]

                if intervalo[3] + tempo[s,CD] > max_t
                    continue
                end

                rota = [CD,s]
                custo = fretes[(s,v)]

                write_cached_route(routesIO, rota, custo)
                write_route_state(frontierIO, rota, demandaPeso[s], demandaVolume[s], intervalo, custo)
            end
        end
    end

    complete = !isfile(frontierPath) || filesize(frontierPath) == 0
    write_pricing_meta(metaPath, initialTimeLimit, 1, 0, complete)
end


function best_cached_route(v, π, αv, routesPath)
    melhorRC = Inf
    melhorRota = nothing
    melhorCusto = 0.0

    if !isfile(routesPath)
        return melhorRC, melhorRota, melhorCusto
    end

    open(routesPath, "r") do io
        for line in eachline(io)
            isempty(line) && continue

            firstTab = findfirst(==('\t'), line)
            lastTab = findlast(==('\t'), line)

            firstTab === nothing && continue
            lastTab === nothing && continue

            rotaStr = SubString(line, 1, firstTab - 1)
            custo = parse(Float64, SubString(line, lastTab + 1, lastindex(line)))

            somaPi = 0.0
            primeiro = true

            for token in eachsplit(rotaStr, ',')
                if primeiro
                    primeiro = false
                    continue
                end

                somaPi += π[parse(Int, token)]
            end

            rc = custo - somaPi - αv

            if rc < melhorRC
                melhorRC = rc
                melhorCusto = custo
                melhorRota = parse.(Int, split(rotaStr, ','))
                push!(melhorRota, 1)
            end
        end
    end

    return melhorRC, melhorRota, melhorCusto
end


function solve_pricing_vehicle_alt(v, π, αv, vehiclesByStore, tempo, fretes, demandaPeso, demandaVolume, capPeso, capVolume, max_t, t_descarga, rotasExistentes, timeWindows, stateDir; initialTimeLimit=0.5, timeIncrement=0.1, checkEvery=1000, cacheReadTokens=nothing)
    CD = 1

    lojas = [s for s in 2:size(tempo,1) if
        v in get(vehiclesByStore,s,Int[]) &&
        demandaPeso[s] <= capPeso[v] &&
        demandaVolume[s] <= capVolume[v] &&
        isfinite(tempo[CD,s]) &&
        isfinite(tempo[s,CD]) &&
        tempo[CD,s] + t_descarga + tempo[s,CD] <= max_t
    ]

    isempty(lojas) && return nothing

    dir = pricing_vehicle_dir(stateDir, v)

    initialize_vehicle_pricing(v, lojas, tempo, fretes, demandaPeso, demandaVolume, max_t, t_descarga, timeWindows, stateDir, initialTimeLimit)

    metaPath = joinpath(dir, "meta.txt")
    routesPath = joinpath(dir, "routes.tsv")

    meta = read_pricing_meta(metaPath)

    timeLimit = parse(Float64, meta["time_limit"])
    depth = parse(Int, meta["depth"])
    offset = parse(Int64, meta["offset"])
    complete = parse(Bool, meta["complete"])

    # Reavalia todas as rotas já conhecidas com os duais ATUAIS.
    # Limita quantos veículos podem varrer arquivos grandes ao mesmo tempo.
    if cacheReadTokens === nothing
        melhorRC, melhorRota, melhorCusto = best_cached_route(v, π, αv, routesPath)
    else
        take!(cacheReadTokens)
        try
            melhorRC, melhorRota, melhorCusto = best_cached_route(v, π, αv, routesPath)
        finally
            put!(cacheReadTokens, nothing)
        end
    end

    if complete
        melhorRota === nothing && return nothing
        return (reduced_cost=melhorRC, rota=melhorRota, custo=melhorCusto, veiculo=v)
    end

    inicio = time()
    testadosDesdeCheck = 0

    while true
        currentPath = joinpath(dir, "frontier_$(depth).tsv")
        nextPath = joinpath(dir, "frontier_$(depth + 1).tsv")

        if !isfile(currentPath)
            write_pricing_meta(metaPath, timeLimit, depth, 0, true)

            melhorRota === nothing && return nothing
            return (reduced_cost=melhorRC, rota=melhorRota, custo=melhorCusto, veiculo=v)
        end

        terminouNivel = true
        novoOffset = offset

        open(currentPath, "r") do currentIO
            seek(currentIO, offset)

            open(nextPath, "a") do nextIO
                open(routesPath, "a") do routesIO
                    while !eof(currentIO)
                        line = readline(currentIO)
                        isempty(line) && continue

                        rota, pesoAtual, volumeAtual, intervalo, custoAtual = read_route_state(line)

                        somaPiAtual = 0.0
                        for k in 2:length(rota)
                            somaPiAtual += π[rota[k]]
                        end

                        last_store = rota[end]

                        for store in lojas
                            testadosDesdeCheck += 1

                            if store in rota
                                continue
                            end

                            novoPeso = pesoAtual + demandaPeso[store]
                            novoPeso > capPeso[v] && continue

                            novoVolume = volumeAtual + demandaVolume[store]
                            novoVolume > capVolume[v] && continue

                            dist_t = tempo[last_store,store]

                            if !isfinite(dist_t) || !isfinite(tempo[store,CD])
                                continue
                            end

                            if intervalo[3] + dist_t + t_descarga + tempo[store,CD] > max_t
                                continue
                            end

                            if intervalo[1] + dist_t + intervalo[3] > timeWindows[store][2]
                                continue
                            end

                            if intervalo[2] + dist_t + intervalo[3] <= timeWindows[store][1]
                                novoIntervalo = [intervalo[2], intervalo[2], timeWindows[store][1] - intervalo[2] + t_descarga]
                            else
                                novoIntervalo = [max(intervalo[1], timeWindows[store][1] - dist_t - intervalo[3]), intervalo[2], intervalo[3] + dist_t + t_descarga]
                            end

                            if novoIntervalo[3] + tempo[store,CD] > max_t
                                continue
                            end

                            novoCusto = max(custoAtual, fretes[(store,v)])

                            novaRota = copy(rota)
                            push!(novaRota, store)

                            write_route_state(nextIO, novaRota, novoPeso, novoVolume, novoIntervalo, novoCusto)
                            write_cached_route(routesIO, novaRota, novoCusto)

                            rc = novoCusto - (somaPiAtual + π[store]) - αv

                            if rc < melhorRC
                                melhorRC = rc
                                melhorRota = [novaRota; CD]
                                melhorCusto = novoCusto
                            end
                        end

                        novoOffset = position(currentIO)

                        if testadosDesdeCheck >= checkEvery
                            flush(nextIO)
                            flush(routesIO)

                            write_pricing_meta(metaPath, timeLimit, depth, novoOffset, false)

                            testadosDesdeCheck = 0

                            if time() - inicio >= timeLimit
                                terminouNivel = false
                                break
                            end
                        end
                    end
                end
            end
        end

        if !terminouNivel
            # Próxima execução desse veículo terá mais 0.5 s.
            write_pricing_meta(metaPath, timeLimit + timeIncrement, depth, novoOffset, false)

            melhorRota === nothing && return nothing
            return (reduced_cost=melhorRC, rota=melhorRota, custo=melhorCusto, veiculo=v)
        end

        # Terminamos de expandir TODAS as rotas com "depth" lojas.
        rm(currentPath; force=true)

        if !isfile(nextPath) || filesize(nextPath) == 0
            rm(nextPath; force=true)

            write_pricing_meta(metaPath, timeLimit, depth, 0, true)

            melhorRota === nothing && return nothing
            return (reduced_cost=melhorRC, rota=melhorRota, custo=melhorCusto, veiculo=v)
        end

        depth += 1
        offset = 0

        write_pricing_meta(metaPath, timeLimit, depth, offset, false)

        # Também verifica o limite ao terminar uma camada inteira.
        if time() - inicio >= timeLimit
            write_pricing_meta(metaPath, timeLimit + timeIncrement, depth, offset, false)

            melhorRota === nothing && return nothing
            return (reduced_cost=melhorRC, rota=melhorRota, custo=melhorCusto, veiculo=v)
        end
    end
end


function solve_all_pricings(V, π, α, vehiclesByStore, tempo, fretes, demandaPeso, demandaVolume, capPeso, capVolume, max_t, t_descarga, rotas, timeWindows, stateDir; initialTimeLimit=0.5, timeIncrement=0.1, checkEvery=1000, minFreeRamGB=2.0, maxConcurrentCacheReads=12)
    mkpath(stateDir)

    resultados = Vector{Any}(undef, length(V))
    fill!(resultados, nothing)

    println("Realizando pricing para criação de novas rotas")
    println("Veículos: $(length(V)) | Threads Julia: $(Threads.nthreads())")

    concluidos = Threads.Atomic{Int}(0)
    printLock = ReentrantLock()
    total = length(V)

    nCacheReaders = max(1, min(maxConcurrentCacheReads, total))
    cacheReadTokens = Channel{Nothing}(nCacheReaders)
    for _ in 1:nCacheReaders
        put!(cacheReadTokens, nothing)
    end
    println("Leituras simultâneas do cache: $nCacheReaders")

    print("Progresso pricing: 0/$total | Faltam: $total")
    flush(stdout)

    Threads.@threads for i in eachindex(V)
        v = V[i]

        wait_for_available_memory(minFreeRamGB)

        resultados[i] = solve_pricing_vehicle_alt(v, π, α[v], vehiclesByStore, tempo, fretes, demandaPeso, demandaVolume, capPeso, capVolume, max_t, t_descarga, rotas, timeWindows, stateDir; initialTimeLimit=initialTimeLimit, timeIncrement=timeIncrement, checkEvery=checkEvery, cacheReadTokens=cacheReadTokens)

        terminou = Threads.atomic_add!(concluidos, 1) + 1
        faltam = total - terminou

        lock(printLock) do
            print("\r\e[2KProgresso pricing: $terminou/$total | Faltam: $faltam")
            flush(stdout)
        end
    end

    println()

    return resultados
end