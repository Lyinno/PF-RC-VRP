include("readData.jl")


function nearestNeighborRoute(stores, travelTime)
    route = [1]
    remaining = Set(filter(x -> x != 1, stores))

    current = 1

    while !isempty(remaining)
        nextStore = argmin(
            s -> travelTime[current, s],
            remaining
        )

        push!(route, nextStore)
        delete!(remaining, nextStore)

        current = nextStore
    end

    return route
end


function makeRoutes(path, max_t, t_descarga, n_routes)
    println("Gerando rotas iniciais")

    df = readData(path)
    df_tempo = df[1]
    df_demanda = df[2]
    df_capacidade = df[3]
    df_frete = df[4]

    vehiclesByStore = Dict{Int, Vector{Int}}()
    for row in eachrow(df_frete)
        if isfinite(row.valor_frete)
            push!(
                get!(vehiclesByStore, row.store, Int[]),
                row.vehicle
            )
        end
    end

    n_stores = nrow(df[2])

    tempo = fill(Inf, n_stores, n_stores)
    for row in eachrow(df_tempo)
        tempo[row.store1, row.store2] = row.tempo_deslocamento
    end

    all_routes = []
    i_routes = []
    for s in 2:n_stores
        vehicles = []
        dp = df_demanda[s,2]
        dv = df_demanda[s,3]
        for v in vehiclesByStore[s]
            cp = df_capacidade[v,2]
            cv = df_capacidade[v,3]
            if (cp >= dp)&&(cv >= dv)
                push!(vehicles,v)
            end 
        end
        push!(i_routes,[[1,s], tempo[1,s], [dp,dv], vehicles])
    end
    append!(all_routes,i_routes)
    
    while true
        set_routes = []
        j_routes = []
        for route in i_routes
            last_store = route[1][end]
            for store in 1:n_stores
               if store in route[1]
                    continue
               end
               dist_t = tempo[last_store,store]
               if dist_t + route[2] + tempo[store,1] + t_descarga <= max_t
                    new_route = copy(route[1])
                    push!(new_route,store)
                    if Set(new_route) in set_routes
                        continue
                    end

                    vehicles = route[4]
                    dp = route[3][1] + df_demanda[store,2]
                    dv = route[3][2] + df_demanda[store,3]
                    s_vehicles = vehiclesByStore[store]

                    new_vehicles = [v for v in vehicles if ((v in s_vehicles)&&(df_capacidade[v,2]>=dp)&&(df_capacidade[v,3]>=dv))]
                    if isempty(new_vehicles)
                        continue
                    end

                    new_route_opt = nearestNeighborRoute(new_route, tempo)
                    dist_t = 0
                    tam = length(new_route_opt)
                    for s in 2:tam
                        dist_t += tempo[new_route[s-1], new_route[s]]+t_descarga
                    end
                    push!(j_routes,[new_route_opt, dist_t, [dp,dv], new_vehicles])
                    push!(set_routes,Set(new_route_opt))
               end
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

    fretes = Dict(
        (row.store, row.vehicle) => row.valor_frete
        for row in eachrow(df_frete)
    )

    A = zeros(Int,min(n_routes,length(all_routes)),nrow(df_capacidade))
    Ast = zeros(Int,min(n_routes,length(all_routes)),nrow(df_demanda))
    Custo = zeros(min(n_routes,length(all_routes)),nrow(df_capacidade))
    for (i,route) in enumerate(all_routes)
        for v in route[4]
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
        push!(rota,1)
        push!(rotas,rota)
    end
    return (A, Ast, Custo, rotas, vehiclesByStore, tempo, fretes, df_demanda, df_capacidade)
end
