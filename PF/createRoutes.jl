include("readData.jl")

function makeRoutes(path, timeWindowPath, max_t, t_descarga, n_routes)
    println("Gerando rotas iniciais")

    timeWindow = ler_janelas_recebimento(timeWindowPath)

    df = readData(path)
    df_tempo = df[1]
    df_demanda = df[2]
    df_capacidade = df[3]
    df_frete = df[4]

    vehiclesByStore = Dict{Int, Vector{Int}}()
    for row in eachrow(df_frete)
        if isfinite(row.valor_frete)
            push!(get!(vehiclesByStore, row.store, Int[]), row.vehicle)
        end
    end

    n_stores = nrow(df_demanda)

    tempo = fill(Inf, n_stores, n_stores)
    for row in eachrow(df_tempo)
        tempo[row.store1, row.store2] = row.tempo_deslocamento
    end

    demandaPeso = df_demanda[:,2]
    demandaVolume = df_demanda[:,3]
    capPeso = df_capacidade[:,2]
    capVolume = df_capacidade[:,3]

    all_routes = []
    i_routes = []

    for s in 2:n_stores
        vehicles = []
        dp = demandaPeso[s]
        dv = demandaVolume[s]

        for v in vehiclesByStore[s]
            if capPeso[v] >= dp && capVolume[v] >= dv
                push!(vehicles, v)
            end
        end

        push!(i_routes, [[1,s], [dp,dv], vehicles, [timeWindow[s][1]-tempo[1,s], timeWindow[s][2]-tempo[1,s], tempo[1,s]+t_descarga]])
    end

    append!(all_routes, i_routes)

    while true
        println("Rotas até o momento: $(length(all_routes)) | Rotas a expandir: $(length(i_routes))")

        resultados = Vector{Union{Nothing,Vector{Any}}}(nothing, length(i_routes))

        Threads.@threads for idx in eachindex(i_routes)
            route = i_routes[idx]
            local_routes = nothing

            last_store = route[1][end]
            intervalo = route[4]

            if intervalo[3] + t_descarga > max_t
                continue
            end

            for store in 1:n_stores
                if store in route[1]
                    continue
                end

                dist_t = tempo[last_store,store]

                if intervalo[1] + dist_t + intervalo[3] > timeWindow[store][2]
                    continue
                end

                if intervalo[2] + dist_t + intervalo[3] <= timeWindow[store][1]
                    newIntervalo = [intervalo[2], intervalo[2], timeWindow[store][1]-intervalo[2]+t_descarga]
                else
                    newIntervalo = [max(intervalo[1], timeWindow[store][1]-dist_t-intervalo[3]), intervalo[2], intervalo[3]+dist_t+t_descarga]
                end

                if newIntervalo[3] <= max_t
                    dp = route[2][1] + demandaPeso[store]
                    dv = route[2][2] + demandaVolume[store]
                    s_vehicles = vehiclesByStore[store]

                    new_vehicles = [v for v in route[3] if v in s_vehicles && capPeso[v] >= dp && capVolume[v] >= dv]

                    if isempty(new_vehicles)
                        continue
                    end

                    new_route = copy(route[1])
                    push!(new_route, store)

                    if local_routes === nothing
                        local_routes = Any[]
                    end

                    push!(local_routes, [new_route, [dp,dv], new_vehicles, newIntervalo])
                end
            end

            resultados[idx] = local_routes
        end

        j_routes = Any[]
        for r in resultados
            if r !== nothing
                append!(j_routes, r)
            end
        end

        if isempty(j_routes)
            break
        end

        faltam = n_routes - length(all_routes)
        append!(all_routes, j_routes[1:min(faltam, length(j_routes))])
        i_routes = j_routes

        if length(all_routes) == n_routes
            break
        end
    end
    println("Rotas geradas: $(length(all_routes))")

    fretes = Dict((row.store, row.vehicle) => row.valor_frete for row in eachrow(df_frete))

    A = zeros(Int, min(n_routes,length(all_routes)), nrow(df_capacidade))
    Ast = zeros(Int, min(n_routes,length(all_routes)), nrow(df_demanda))
    Custo = zeros(min(n_routes,length(all_routes)), nrow(df_capacidade))

    for (i,route) in enumerate(all_routes)
        for v in route[3]
            A[i,v] = 1
            cost = maximum([fretes[s,v] for s in route[1]])
            Custo[i,v] = cost
        end

        for s in route[1]
            Ast[i,s] = 1
        end
    end

    rotas = []

    for r in all_routes
        rota = copy(r[1])
        push!(rota, 1)
        push!(rotas, rota)
    end

    return (A, Ast, Custo, rotas, vehiclesByStore, tempo, fretes, df_demanda, df_capacidade, timeWindow)
end