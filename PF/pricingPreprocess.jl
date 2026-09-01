struct PricingPreprocessData
    eligibleByVehicle::Dict{Int,Vector{Int}}
    nextStoresByVehicle::Dict{Int,Vector{Vector{Int}}}
end

function eligible_stores_for_vehicle(v, data, max_t, t_descarga)
    return [s for s in 2:data.nStores if
        v in get(data.vehiclesByStore,s,BitSet()) &&
        haskey(data.fretes,(s,v)) &&
        isfinite(data.fretes[(s,v)]) &&
        data.demandaPeso[s] <= data.capPeso[v] + 1e-9 &&
        data.demandaVolume[s] <= data.capVolume[v] + 1e-9 &&
        isfinite(data.tempo[1,s]) &&
        isfinite(data.tempo[s,1]) &&
        data.tempo[1,s] + t_descarga + data.tempo[s,1] <= max_t + 1e-9
    ]
end

function build_pricing_preprocess_data(V, data, max_t, t_descarga, timeWindows)
    eligibleByVehicle = Dict{Int,Vector{Int}}()
    nextStoresByVehicle = Dict{Int,Vector{Vector{Int}}}()

    for v in V
        stores = eligible_stores_for_vehicle(v, data, max_t, t_descarga)
        eligibleByVehicle[v] = stores

        nextStores = [Int[] for _ in 1:data.nStores]

        for i in stores
            candidates = nextStores[i]

            for j in stores
                i == j && continue
                !isfinite(data.tempo[i,j]) && continue

                data.demandaPeso[i] + data.demandaPeso[j] > data.capPeso[v] + 1e-9 && continue
                data.demandaVolume[i] + data.demandaVolume[j] > data.capVolume[v] + 1e-9 && continue

                # Se nem saindo de i no inicio de sua janela e possivel chegar em j
                # antes do fechamento, o arco i -> j nunca pode aparecer.
                timeWindows[i][1] + t_descarga + data.tempo[i,j] > timeWindows[j][2] + 1e-9 && continue

                push!(candidates, j)
            end
        end

        nextStoresByVehicle[v] = nextStores
    end

    return PricingPreprocessData(eligibleByVehicle, nextStoresByVehicle)
end
