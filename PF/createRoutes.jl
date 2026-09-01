include("readData.jl")

struct InitialRouteState
    stores::Vector{Int}
    visited::BitSet
    peso::Float64
    volume::Float64
    vehicles::Vector{Int}
    intervalo1::Float64
    intervalo2::Float64
    duracao::Float64
end

function build_initial_next_stores(data, timeWindows, t_descarga)
    nextStores = [Int[] for _ in 1:data.nStores]

    for i in 2:data.nStores
        lista = nextStores[i]

        for j in 2:data.nStores
            i == j && continue
            !isfinite(data.tempo[i,j]) && continue

            if timeWindows[i][1] + t_descarga + data.tempo[i,j] <= timeWindows[j][2]
                push!(lista, j)
            end
        end
    end

    return nextStores
end

function initial_vehicle_list(store, data)
    vehicles = Int[]

    for v in get(data.vehiclesByStore, store, BitSet())
        if data.demandaPeso[store] <= data.capPeso[v] && data.demandaVolume[store] <= data.capVolume[v]
            push!(vehicles, v)
        end
    end

    return vehicles
end

function expand_initial_state(state, nextStores, data, timeWindows, max_t, t_descarga)
    lastStore = state.stores[end]
    children = InitialRouteState[]

    for store in nextStores[lastStore]
        store in state.visited && continue

        novoPeso = state.peso + data.demandaPeso[store]
        novoVolume = state.volume + data.demandaVolume[store]

        newVehicles = Int[]
        compatible = get(data.vehiclesByStore, store, BitSet())

        for v in state.vehicles
            if v in compatible && novoPeso <= data.capPeso[v] && novoVolume <= data.capVolume[v]
                push!(newVehicles, v)
            end
        end

        isempty(newVehicles) && continue

        dist_t = data.tempo[lastStore,store]
        state.intervalo1 + dist_t + state.duracao > timeWindows[store][2] && continue

        if state.intervalo2 + dist_t + state.duracao <= timeWindows[store][1]
            novoIntervalo1 = state.intervalo2
            novoIntervalo2 = state.intervalo2
            novaDuracao = timeWindows[store][1] - state.intervalo2 + t_descarga
        else
            novoIntervalo1 = max(state.intervalo1, timeWindows[store][1] - dist_t - state.duracao)
            novoIntervalo2 = state.intervalo2
            novaDuracao = state.duracao + dist_t + t_descarga
        end

        novaDuracao + data.tempo[store,1] > max_t && continue

        newStores = copy(state.stores)
        push!(newStores, store)

        newVisited = copy(state.visited)
        push!(newVisited, store)

        push!(children, InitialRouteState(newStores, newVisited, novoPeso, novoVolume, newVehicles, novoIntervalo1, novoIntervalo2, novaDuracao))
    end

    return children
end

function makeRoutes(path, timeWindowPath, max_t, t_descarga, n_routes)
    println("Gerando rotas iniciais")

    data = readData(path)
    timeWindows = ler_janelas_recebimento(timeWindowPath)

    length(timeWindows) < data.nStores && error("Arquivo de janelas possui menos lojas que o arquivo de dados")
    n_routes < data.nStores - 1 && error("n_routes deve ser pelo menos $(data.nStores - 1) para incluir uma rota simples por loja")

    nextStores = build_initial_next_stores(data, timeWindows, t_descarga)
    frontier = InitialRouteState[]

    for s in 2:data.nStores
        vehicles = initial_vehicle_list(s, data)
        isempty(vehicles) && continue
        !isfinite(data.tempo[1,s]) && continue
        !isfinite(data.tempo[s,1]) && continue
        data.tempo[1,s] + t_descarga + data.tempo[s,1] > max_t && continue

        state = InitialRouteState([s], BitSet([s]), data.demandaPeso[s], data.demandaVolume[s], vehicles, timeWindows[s][1] - data.tempo[1,s], timeWindows[s][2] - data.tempo[1,s], data.tempo[1,s] + t_descarga)
        push!(frontier, state)
    end

    covered = BitSet()
    for state in frontier
        push!(covered, state.stores[1])
    end

    missing = [s for s in 2:data.nStores if !(s in covered)]
    isempty(missing) || error("Existem lojas sem rota simples viavel: $missing")

    # Fila BFS: para assim que n_routes e atingido, sem materializar um nivel inteiro
    # que pode conter dezenas de milhares de rotas desnecessarias.
    allStates = copy(frontier)
    cursor = 1

    while cursor <= length(allStates) && length(allStates) < n_routes
        state = allStates[cursor]
        children = expand_initial_state(state, nextStores, data, timeWindows, max_t, t_descarga)

        for child in children
            push!(allStates, child)
            length(allStates) == n_routes && break
        end

        cursor += 1
    end

    println("Rotas geradas: $(length(allStates))")

    n = length(allStates)
    A = zeros(Int8, n, data.nVehicles)
    Ast = zeros(Int8, n, data.nStores)
    Custos = zeros(Float64, n, data.nVehicles)
    rotas = Vector{Vector{Int}}(undef, n)

    for (r,state) in enumerate(allStates)
        rota = Vector{Int}(undef, length(state.stores) + 2)
        rota[1] = 1
        rota[2:end-1] = state.stores
        rota[end] = 1
        rotas[r] = rota

        Ast[r,1] = 1
        for s in state.stores
            Ast[r,s] = 1
        end

        for v in state.vehicles
            A[r,v] = 1
            Custos[r,v] = maximum(data.fretes[(s,v)] for s in state.stores)
        end
    end

    return A, Ast, Custos, rotas, data, timeWindows
end
