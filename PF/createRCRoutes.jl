function create_route_rows(rota, V, n_stores, vehiclesByStore, fretes, demandaPeso, demandaVolume, capPeso, capVolume)
    lojas = rota[2:end-1]

    novaA = zeros(Int, length(V))
    novaAst = zeros(Int, n_stores)
    novosCustos = zeros(Float64, length(V))

    novaAst[1] = 1

    for s in lojas
        novaAst[s] = 1
    end

    peso = sum(demandaPeso[s] for s in lojas)
    volume = sum(demandaVolume[s] for s in lojas)

    for v in V
        compativel = all(v in vehiclesByStore[s] for s in lojas)
        cabe = peso <= capPeso[v] + 1e-6 && volume <= capVolume[v] + 1e-6
        fretesValidos = all(haskey(fretes, (s,v)) && isfinite(fretes[(s,v)]) for s in lojas)

        if compativel && cabe && fretesValidos
            novaA[v] = 1
            novosCustos[v] = maximum(fretes[(s,v)] for s in lojas)
        end
    end

    return novaA, novaAst, novosCustos
end
