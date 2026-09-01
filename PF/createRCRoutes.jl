function create_route_rows(rota, V, data)
    stores = rota[2:end-1]

    novaA = zeros(Int8, length(V))
    novaAst = zeros(Int8, data.nStores)
    novosCustos = zeros(Float64, length(V))

    novaAst[1] = 1
    for s in stores
        novaAst[s] = 1
    end

    peso = sum(data.demandaPeso[s] for s in stores)
    volume = sum(data.demandaVolume[s] for s in stores)

    for v in V
        peso > data.capPeso[v] + 1e-6 && continue
        volume > data.capVolume[v] + 1e-6 && continue
        all(v in get(data.vehiclesByStore, s, BitSet()) for s in stores) || continue

        novaA[v] = 1
        novosCustos[v] = maximum(data.fretes[(s,v)] for s in stores)
    end

    return novaA, novaAst, novosCustos
end
