# Hybrid pricing for VRP:
# - FAST phase: RC-Savings + bounded Pulse DFS to find negative columns cheaply.
# - EXACT phase: only runs when FAST found no negative route. It searches only
#   for existence of RC < 0; it does NOT waste time minimizing RC exactly.
# - A certified (possibly loose) lower bound is available every iteration from
#   safe root relaxation bounds. At convergence, LB = RMP exactly.
# - DFS keeps memory low; no global label heap/frontier is used.

# -----------------------------------------------------------------------------
# Visit mask and state
# -----------------------------------------------------------------------------

@inline function mask_position(store)
    bit = store - 2
    return (bit >>> 6) + 1, UInt64(1) << (bit & 63)
end

@inline function mask_contains(mask::NTuple{N,UInt64}, store) where N
    word, bit = mask_position(store)
    return (mask[word] & bit) != 0
end

@inline function mask_add(mask::NTuple{N,UInt64}, store) where N
    word, bit = mask_position(store)
    return Base.setindex(mask, mask[word] | bit, word)
end

@inline mask_and(a::NTuple{N,UInt64}, b::NTuple{N,UInt64}) where N = ntuple(i -> a[i] & b[i], Val(N))
@inline mask_or(a::NTuple{N,UInt64}, b::NTuple{N,UInt64}) where N = ntuple(i -> a[i] | b[i], Val(N))
@inline empty_visit_mask(::Val{N}) where N = ntuple(_ -> UInt64(0), Val(N))

struct PulseState{N}
    lastStore::Int
    visited::NTuple{N,UInt64}
    blocked::NTuple{N,UInt64}
    peso::Float64
    volume::Float64
    intervalo1::Float64
    intervalo2::Float64
    duracao::Float64
    custo::Float64
    somaPi::Float64
    somaPiPos::Float64
end

@inline reduced_cost(state::PulseState, alphav) = state.custo - state.somaPi - alphav

# -----------------------------------------------------------------------------
# Feasibility transitions
# -----------------------------------------------------------------------------

function initial_pulse_state(::Val{N}, s, v, pi, data, max_t, t_descarga, timeWindows, conflictMasks) where N
    !isfinite(data.tempo[1,s]) && return nothing
    !isfinite(data.tempo[s,1]) && return nothing
    data.demandaPeso[s] > data.capPeso[v] + 1e-9 && return nothing
    data.demandaVolume[s] > data.capVolume[v] + 1e-9 && return nothing
    !haskey(data.fretes, (s,v)) && return nothing
    !isfinite(data.fretes[(s,v)]) && return nothing

    intervalo1 = timeWindows[s][1] - data.tempo[1,s]
    intervalo2 = timeWindows[s][2] - data.tempo[1,s]
    duracao = data.tempo[1,s] + t_descarga

    duracao + data.tempo[s,1] > max_t + 1e-9 && return nothing

    visited = mask_add(empty_visit_mask(Val(N)), s)
    blocked = conflictMasks[s]
    p = pi[s]
    return PulseState{N}(s, visited, blocked, data.demandaPeso[s], data.demandaVolume[s], intervalo1, intervalo2, duracao, data.fretes[(s,v)], p, max(p,0.0))
end

function extend_pulse_state(state::PulseState{N}, store, v, pi, data, max_t, t_descarga, timeWindows, conflictMasks) where N
    mask_contains(state.visited, store) && return nothing
    mask_contains(state.blocked, store) && return nothing

    novoPeso = state.peso + data.demandaPeso[store]
    novoPeso > data.capPeso[v] + 1e-9 && return nothing

    novoVolume = state.volume + data.demandaVolume[store]
    novoVolume > data.capVolume[v] + 1e-9 && return nothing

    dist_t = data.tempo[state.lastStore,store]
    !isfinite(dist_t) && return nothing
    !isfinite(data.tempo[store,1]) && return nothing

    state.duracao + dist_t + t_descarga + data.tempo[store,1] > max_t + 1e-9 && return nothing
    state.intervalo1 + dist_t + state.duracao > timeWindows[store][2] + 1e-9 && return nothing

    if state.intervalo2 + dist_t + state.duracao <= timeWindows[store][1] + 1e-9
        novoIntervalo1 = state.intervalo2
        novoIntervalo2 = state.intervalo2
        novaDuracao = timeWindows[store][1] - state.intervalo2 + t_descarga
    else
        novoIntervalo1 = max(state.intervalo1, timeWindows[store][1] - dist_t - state.duracao)
        novoIntervalo2 = state.intervalo2
        novaDuracao = state.duracao + dist_t + t_descarga
    end

    novaDuracao + data.tempo[store,1] > max_t + 1e-9 && return nothing

    visited = mask_add(state.visited, store)
    blocked = mask_or(state.blocked, conflictMasks[store])
    p = pi[store]

    return PulseState{N}(
        store,
        visited,
        blocked,
        novoPeso,
        novoVolume,
        novoIntervalo1,
        novoIntervalo2,
        novaDuracao,
        max(state.custo, data.fretes[(store,v)]),
        state.somaPi + p,
        state.somaPiPos + max(p,0.0)
    )
end

# -----------------------------------------------------------------------------
# Safe continuation bounds
# -----------------------------------------------------------------------------

function build_bound_orders(stores, pi, data)
    orderPi = sort(copy(stores), by=s -> pi[s], rev=true)

    orderWeight = sort(copy(stores), by=s -> begin
        p = pi[s]
        w = data.demandaPeso[s]
        p <= 0 ? -Inf : w <= 1e-12 ? Inf : p / w
    end, rev=true)

    orderVolume = sort(copy(stores), by=s -> begin
        p = pi[s]
        vol = data.demandaVolume[s]
        p <= 0 ? -Inf : vol <= 1e-12 ? Inf : p / vol
    end, rev=true)

    return orderPi, orderWeight, orderVolume
end

function top_k_dual_upper(orderPi, visited, blocked, pi, k)
    k <= 0 && return 0.0

    total = 0.0
    used = 0

    for s in orderPi
        pi[s] <= 0 && break
        mask_contains(visited, s) && continue
        mask_contains(blocked, s) && continue
        total += pi[s]
        used += 1
        used == k && break
    end

    return total
end

function fractional_resource_dual_upper(orderRatio, visited, blocked, pi, resource, remaining)
    remaining < -1e-9 && return 0.0

    total = 0.0
    rem = max(0.0, remaining)

    for s in orderRatio
        pi[s] <= 0 && continue
        mask_contains(visited, s) && continue
        mask_contains(blocked, s) && continue

        consumption = resource[s]

        if consumption <= 1e-12
            total += pi[s]
            continue
        end

        rem <= 1e-12 && break

        fraction = min(1.0, rem / consumption)
        total += pi[s] * fraction
        rem -= consumption * fraction
    end

    return total
end

# -----------------------------------------------------------------------------
# Strong safe compatibility bound
# -----------------------------------------------------------------------------

# The travel matrix in the test data is not assumed to satisfy triangle
# inequality. Floyd-Warshall gives a lower bound on the travel required between
# two stores even if a route visits intermediate stores. Intermediate service
# times are ignored, making this deliberately optimistic and therefore safe.
const _SHORTEST_TRAVEL_CACHE = IdDict{Any,Matrix{Float64}}()

function all_pairs_shortest_travel(tempo)
    d = Matrix{Float64}(tempo)
    n = size(d,1)

    for i in 1:n
        d[i,i] = min(d[i,i],0.0)
    end

    for k in 1:n
        for i in 1:n
            dik = d[i,k]
            !isfinite(dik) && continue
            @inbounds for j in 1:n
                dkj = d[k,j]
                !isfinite(dkj) && continue
                alt = dik + dkj
                alt < d[i,j] && (d[i,j] = alt)
            end
        end
    end

    return d
end

function get_shortest_travel(tempo)
    return get!(_SHORTEST_TRAVEL_CACHE,tempo) do
        all_pairs_shortest_travel(tempo)
    end
end

# Two stores are marked incompatible only when they provably cannot coexist in
# any feasible route. The tests are NECESSARY conditions, so using them in an
# upper bound cannot remove a valid route:
#   1) pair capacity already exceeds the vehicle;
#   2) neither temporal ordering can fit the time windows even using the
#      shortest possible travel between the stores;
#   3) neither ordering can fit max_t even under an optimistic shortest-travel
#      path with no waiting and no intermediate service time.
function build_conflict_masks(::Val{N}, stores, v, data, max_t, t_descarga, timeWindows, shortestTravel) where N
    conflicts = [empty_visit_mask(Val(N)) for _ in 1:data.nStores]

    for a in 1:(length(stores)-1)
        i = stores[a]
        for b in (a+1):length(stores)
            j = stores[b]

            capacityConflict = data.demandaPeso[i] + data.demandaPeso[j] > data.capPeso[v] + 1e-9 ||
                               data.demandaVolume[i] + data.demandaVolume[j] > data.capVolume[v] + 1e-9

            ijWindowImpossible = !isfinite(shortestTravel[i,j]) || timeWindows[i][1] + t_descarga + shortestTravel[i,j] > timeWindows[j][2] + 1e-9
            jiWindowImpossible = !isfinite(shortestTravel[j,i]) || timeWindows[j][1] + t_descarga + shortestTravel[j,i] > timeWindows[i][2] + 1e-9
            windowConflict = ijWindowImpossible && jiWindowImpossible

            durIJ = shortestTravel[1,i] + t_descarga + shortestTravel[i,j] + t_descarga + shortestTravel[j,1]
            durJI = shortestTravel[1,j] + t_descarga + shortestTravel[j,i] + t_descarga + shortestTravel[i,1]
            durationConflict = (!isfinite(durIJ) || durIJ > max_t + 1e-9) && (!isfinite(durJI) || durJI > max_t + 1e-9)

            if capacityConflict || windowConflict || durationConflict
                conflicts[i] = mask_add(conflicts[i],j)
                conflicts[j] = mask_add(conflicts[j],i)
            end
        end
    end

    return conflicts
end

# -----------------------------------------------------------------------------
# Static pricing preprocessing
# -----------------------------------------------------------------------------

# These masks depend only on the instance, vehicle, time limit, unload time and
# time windows. They DO NOT depend on the master duals, so rebuilding them every
# column-generation iteration is pure repeated work.
struct PricingStaticSearchData{N}
    conflictMasksByVehicle::Vector{Vector{NTuple{N,UInt64}}}
end

function build_pricing_static_search_data(V, data, pricingData, max_t, t_descarga, timeWindows; verbose=true)
    nMaskWords = cld(data.nStores - 1,64)
    return _build_pricing_static_search_data(Val(nMaskWords),V,data,pricingData,max_t,t_descarga,timeWindows; verbose=verbose)
end

function _build_pricing_static_search_data(::Val{N}, V, data, pricingData, max_t, t_descarga, timeWindows; verbose=true) where N
    startedAt = time()
    verbose && println("Preprocess pricing | calculando shortest paths e incompatibilidades uma unica vez...")

    shortestTravel = get_shortest_travel(data.tempo)
    conflictMasksByVehicle = Vector{Vector{NTuple{N,UInt64}}}(undef,data.nVehicles)

    # Fill every slot so indexing remains safe even if V is a subset.
    emptyConflicts = [empty_visit_mask(Val(N)) for _ in 1:data.nStores]
    for v in 1:data.nVehicles
        conflictMasksByVehicle[v] = emptyConflicts
    end

    for v in V
        stores = pricingData.eligibleByVehicle[v]
        conflictMasksByVehicle[v] = build_conflict_masks(Val(N),stores,v,data,max_t,t_descarga,timeWindows,shortestTravel)
    end

    elapsed = time() - startedAt
    verbose && println("Preprocess pricing concluido | veiculos=$(length(V)) | $(compact_seconds(elapsed))")

    return PricingStaticSearchData{N}(conflictMasksByVehicle)
end

# Greedy clique cover of the conflict graph. Every group built below is a
# clique, so a feasible route may choose at most one store from each group.
# Sum(max positive dual in each clique) is therefore a SAFE upper bound on the
# dual that can still be collected. Because orderPi is descending, the first
# store placed in each clique is its maximum-weight member.
function conflict_clique_dual_upper(orderPi, visited::NTuple{N,UInt64}, blocked::NTuple{N,UInt64}, pi, conflictMasks) where N
    assigned = empty_visit_mask(Val(N))
    dualUpper = 0.0

    for s in orderPi
        pi[s] <= 0 && break
        mask_contains(visited,s) && continue
        mask_contains(blocked,s) && continue
        mask_contains(assigned,s) && continue

        dualUpper += pi[s]
        assigned = mask_add(assigned,s)
        commonConflicts = conflictMasks[s]

        for j in orderPi
            pi[j] <= 0 && break
            j == s && continue
            mask_contains(visited,j) && continue
            mask_contains(blocked,j) && continue
            mask_contains(assigned,j) && continue
            mask_contains(commonConflicts,j) || continue

            assigned = mask_add(assigned,j)
            commonConflicts = mask_and(commonConflicts,conflictMasks[j])
        end
    end

    return dualUpper
end

struct PruneDecision
    stage::UInt8
    compatibilityChecked::Bool
end

# Stage codes used by the dashboard:
# 0 = survives, 1 = total positive dual, 2 = time/cardinality,
# 3 = weight, 4 = volume, 5 = pairwise compatibility/clique cover.
function pulse_full_lower_bound(state::PulseState, totalPositivePi, orderPi, orderWeight, orderVolume, pi, alphav, data, v, max_t, t_descarga, conflictMasks; compatibilityBound=true)
    baseRC = reduced_cost(state,alphav)
    remainingPositive = max(0.0,totalPositivePi - state.somaPiPos)

    remainingTime = max(0.0,max_t - state.duracao)
    kTime = t_descarga > 1e-12 ? min(length(orderPi),floor(Int,remainingTime / t_descarga)) : length(orderPi)

    cardinalityUB = kTime <= 0 ? 0.0 : top_k_dual_upper(orderPi,state.visited,state.blocked,pi,kTime)
    weightUB = fractional_resource_dual_upper(orderWeight,state.visited,state.blocked,pi,data.demandaPeso,data.capPeso[v] - state.peso)
    volumeUB = fractional_resource_dual_upper(orderVolume,state.visited,state.blocked,pi,data.demandaVolume,data.capVolume[v] - state.volume)

    dualUpper = min(remainingPositive,cardinalityUB,weightUB,volumeUB)

    if compatibilityBound && dualUpper > 0.0
        conflictUB = conflict_clique_dual_upper(orderPi,state.visited,state.blocked,pi,conflictMasks)
        dualUpper = min(dualUpper,conflictUB)
    end

    return baseRC - dualUpper
end

# Staged pruning. The expensive compatibility/clique bound is evaluated only
# after all cheaper bounds failed to prune the state.
function pulse_prune_decision(state::PulseState, threshold, totalPositivePi, orderPi, orderWeight, orderVolume, pi, alphav, data, v, max_t, t_descarga, conflictMasks; tol=1e-6, compatibilityBound=true)
    baseRC = reduced_cost(state,alphav)

    remainingPositive = max(0.0,totalPositivePi - state.somaPiPos)
    bestDualUB = remainingPositive
    baseRC - bestDualUB >= threshold - tol && return PruneDecision(0x01,false)

    remainingTime = max(0.0,max_t - state.duracao)
    kTime = t_descarga > 1e-12 ? min(length(orderPi),floor(Int,remainingTime / t_descarga)) : length(orderPi)
    cardinalityUB = kTime <= 0 ? 0.0 : top_k_dual_upper(orderPi,state.visited,state.blocked,pi,kTime)
    bestDualUB = min(bestDualUB,cardinalityUB)
    baseRC - bestDualUB >= threshold - tol && return PruneDecision(0x02,false)

    weightUB = fractional_resource_dual_upper(orderWeight,state.visited,state.blocked,pi,data.demandaPeso,data.capPeso[v] - state.peso)
    bestDualUB = min(bestDualUB,weightUB)
    baseRC - bestDualUB >= threshold - tol && return PruneDecision(0x03,false)

    volumeUB = fractional_resource_dual_upper(orderVolume,state.visited,state.blocked,pi,data.demandaVolume,data.capVolume[v] - state.volume)
    bestDualUB = min(bestDualUB,volumeUB)
    baseRC - bestDualUB >= threshold - tol && return PruneDecision(0x04,false)

    if compatibilityBound && bestDualUB > 0.0
        conflictUB = conflict_clique_dual_upper(orderPi,state.visited,state.blocked,pi,conflictMasks)
        bestDualUB = min(bestDualUB,conflictUB)
        baseRC - bestDualUB >= threshold - tol && return PruneDecision(0x05,true)
        return PruneDecision(0x00,true)
    end

    return PruneDecision(0x00,false)
end

# -----------------------------------------------------------------------------
# Branch ordering
# -----------------------------------------------------------------------------

function median_freight(stores, v, data)
    isempty(stores) && return 0.0
    vals = sort([data.fretes[(s,v)] for s in stores])
    return vals[(length(vals) + 1) >>> 1]
end

function build_branch_order(stores, v, pi, data, nextStores)
    referenceCost = median_freight(stores, v, data)
    priority(s) = pi[s] - max(0.0, data.fretes[(s,v)] - referenceCost)

    ordered = [Int[] for _ in 1:data.nStores]
    for last in stores
        ordered[last] = sort(copy(nextStores[last]), by=priority, rev=true)
    end

    return ordered, priority
end

# -----------------------------------------------------------------------------
# Reduced-cost Savings heuristic
# -----------------------------------------------------------------------------

@inline function rc_saving(state::PulseState, store, v, pi, data)
    return pi[store] - max(0.0, data.fretes[(store,v)] - state.custo)
end

function choose_heuristic_seeds(stores, v, pi, data, nStarts)
    isempty(stores) && return Int[]
    nStarts = min(max(nStarts,1), length(stores))

    bySingle = sort(copy(stores), by=s -> pi[s] - data.fretes[(s,v)], rev=true)
    byDual = sort(copy(stores), by=s -> pi[s], rev=true)

    seeds = Int[]
    seen = BitSet()
    nSingle = cld(nStarts,2)

    for s in Iterators.take(bySingle, nSingle)
        push!(seeds,s)
        push!(seen,s)
    end

    for s in byDual
        length(seeds) >= nStarts && break
        s in seen && continue
        push!(seeds,s)
        push!(seen,s)
    end

    return seeds
end

function greedy_savings_completion(state::PulseState{N}, pathStores, branchOrder, conflictMasks, v, pi, alphav, data, max_t, t_descarga, timeWindows; requirePositiveSaving=true) where N
    current = state
    path = copy(pathStores)
    bestRC = reduced_cost(current, alphav)
    bestPath = copy(path)
    bestCost = current.custo

    while true
        bestStore = 0
        bestChild = nothing
        bestScore = -Inf
        bestChildRC = Inf

        # branchOrder is already statically ordered. We still evaluate the
        # dynamic savings score, but do not allocate/sort a candidate vector.
        for store in branchOrder[current.lastStore]
            mask_contains(current.visited, store) && continue
            child = extend_pulse_state(current, store, v, pi, data, max_t, t_descarga, timeWindows, conflictMasks)
            child === nothing && continue

            saving = rc_saving(current, store, v, pi, data)
            childRC = reduced_cost(child, alphav)

            if saving > bestScore + 1e-12 || (abs(saving - bestScore) <= 1e-12 && childRC < bestChildRC)
                bestStore = store
                bestChild = child
                bestScore = saving
                bestChildRC = childRC
            end
        end

        bestStore == 0 && break
        requirePositiveSaving && bestScore <= 1e-12 && break

        current = bestChild
        push!(path,bestStore)

        currentRC = reduced_cost(current, alphav)
        if currentRC < bestRC
            bestRC = currentRC
            bestPath = copy(path)
            bestCost = current.custo
        end
    end

    return (reduced_cost=bestRC, stores=bestPath, custo=bestCost)
end

function run_reduced_cost_savings_heuristic(::Val{N}, stores, v, pi, alphav, data, branchOrder, conflictMasks, max_t, t_descarga, timeWindows; nStarts=16, progressCallback=nothing) where N
    seeds = choose_heuristic_seeds(stores, v, pi, data, nStarts)

    bestRC = Inf
    bestRoute = nothing
    bestCost = 0.0
    updateEvery = max(1, cld(length(seeds),4))

    for (k,seed) in enumerate(seeds)
        state = initial_pulse_state(Val(N), seed, v, pi, data, max_t, t_descarga, timeWindows, conflictMasks)
        if state !== nothing
            result = greedy_savings_completion(state, Int[seed], branchOrder, conflictMasks, v, pi, alphav, data, max_t, t_descarga, timeWindows)

            if result.reduced_cost < bestRC
                bestRC = result.reduced_cost
                bestRoute = [1; result.stores; 1]
                bestCost = result.custo
            end
        end

        if progressCallback !== nothing && (k == 1 || k == length(seeds) || k % updateEvery == 0)
            progressCallback(k, length(seeds), bestRC)
        end
    end

    return (reduced_cost=bestRC, rota=bestRoute, custo=bestCost, calls=length(seeds))
end

# -----------------------------------------------------------------------------
# Bounded temporal dominance cache
# -----------------------------------------------------------------------------

struct TemporalRecord
    intervalo1::Float64
    intervalo2::Float64
    duracao::Float64
end

@inline function temporal_dominates(a::TemporalRecord, b::TemporalRecord; tol=1e-9)
    return a.intervalo1 <= b.intervalo1 + tol && a.intervalo2 >= b.intervalo2 - tol && a.duracao <= b.duracao + tol
end

function dominated_or_register!(cache::Dict{Tuple{Int,NTuple{N,UInt64}},Vector{TemporalRecord}}, state::PulseState{N}, maxKeys, clearCounter) where N
    maxKeys <= 0 && return false

    key = (state.lastStore, state.visited)
    current = TemporalRecord(state.intervalo1, state.intervalo2, state.duracao)
    bucket = get(cache,key,nothing)

    if bucket !== nothing
        for old in bucket
            temporal_dominates(old,current) && return true
        end

        filter!(old -> !temporal_dominates(current,old), bucket)
        push!(bucket,current)
        return false
    end

    if length(cache) >= maxKeys
        empty!(cache)
        clearCounter[] += 1
    end

    cache[key] = TemporalRecord[current]
    return false
end

# -----------------------------------------------------------------------------
# Compact overwrite-in-place terminal dashboard
# -----------------------------------------------------------------------------

@inline function ram_usage_fraction()
    total = Sys.total_memory()
    total <= 0 && return 0.0
    return clamp(1.0 - Sys.free_memory() / total, 0.0, 1.0)
end

function compact_count(x::Integer)
    x >= 1_000_000_000 && return string(round(x / 1e9, digits=1), "B")
    x >= 1_000_000 && return string(round(x / 1e6, digits=1), "M")
    x >= 1_000 && return string(round(x / 1e3, digits=1), "k")
    return string(x)
end

function compact_seconds(x)
    x < 60 && return string(round(x,digits=1), "s")
    m = floor(Int,x/60)
    s = floor(Int,x - 60m)
    return "$(m)m$(lpad(string(s),2,"0"))s"
end

mutable struct PricingProgressDashboard
    lock::ReentrantLock
    maxVisible::Int
    totalVehicles::Int
    phase::String
    completed::Int
    running::Int
    desired::Int
    activeOrder::Vector{Int}
    visible::Vector{Int}
    states::Dict{Int,String}
    initialized::Bool
    startedAt::Float64
end

function PricingProgressDashboard(totalVehicles, phase; maxVisible=5)
    return PricingProgressDashboard(ReentrantLock(), maxVisible, totalVehicles, phase, 0, 0, 0, Int[], Int[], Dict{Int,String}(), false, time())
end

function refresh_visible!(d::PricingProgressDashboard)
    filter!(v -> v in d.activeOrder, d.visible)
    for v in d.activeOrder
        length(d.visible) >= d.maxVisible && break
        v in d.visible && continue
        push!(d.visible,v)
    end
end

function render_dashboard_unlocked!(d::PricingProgressDashboard)
    nLines = d.maxVisible + 1

    if !d.initialized
        for _ in 1:nLines
            println()
        end
        d.initialized = true
    end

    print("\e[$(nLines)A")
    refresh_visible!(d)

    queued = max(0, d.totalVehicles - d.completed - d.running)
    ram = round(100 * ram_usage_fraction(), digits=1)
    elapsed = compact_seconds(time() - d.startedAt)

    print("\r\e[2KPricing $(d.phase) | concluidos=$(d.completed)/$(d.totalVehicles) | ativos=$(d.running) | fila=$queued | RAM=$(ram)% | limite=$(d.desired) | $elapsed\n")

    for slot in 1:d.maxVisible
        print("\r\e[2K")
        if slot <= length(d.visible)
            v = d.visible[slot]
            print(get(d.states,v,"V$v | iniciando..."))
        end
        print("\n")
    end

    flush(stdout)
end

function dashboard_scheduler!(d::PricingProgressDashboard; running=d.running, desired=d.desired)
    lock(d.lock) do
        d.running = running
        d.desired = desired
        render_dashboard_unlocked!(d)
    end
end

function dashboard_start_vehicle!(d::PricingProgressDashboard, v, phaseText)
    lock(d.lock) do
        push!(d.activeOrder,v)
        d.states[v] = "V$(lpad(string(v),3)) | $phaseText"
        render_dashboard_unlocked!(d)
    end
end

function dashboard_vehicle!(d::PricingProgressDashboard, v, text)
    lock(d.lock) do
        d.states[v] = "V$(lpad(string(v),3)) | $text"
        if v in d.visible
            render_dashboard_unlocked!(d)
        end
    end
end

function dashboard_finish_vehicle!(d::PricingProgressDashboard, v)
    lock(d.lock) do
        filter!(x -> x != v, d.activeOrder)
        filter!(x -> x != v, d.visible)
        delete!(d.states,v)
        d.completed += 1
        refresh_visible!(d)
        render_dashboard_unlocked!(d)
    end
end

function close_dashboard!(d::PricingProgressDashboard, message)
    lock(d.lock) do
        nLines = d.maxVisible + 1
        if d.initialized
            print("\e[$(nLines)A")
            print("\r\e[2K$message\n")
            for _ in 2:nLines
                print("\r\e[2K\n")
            end
            flush(stdout)
        else
            println(message)
        end
    end
end

# -----------------------------------------------------------------------------
# Search preparation
# -----------------------------------------------------------------------------

function prepare_vehicle_search(::Val{N}, v, pi, alphav, data, pricingData, pricingStaticData::PricingStaticSearchData{N}, max_t, t_descarga, timeWindows) where N
    stores = pricingData.eligibleByVehicle[v]
    isempty(stores) && return nothing

    orderPi, orderWeight, orderVolume = build_bound_orders(stores,pi,data)
    totalPositivePi = sum(max(pi[s],0.0) for s in stores)
    branchOrder, priority = build_branch_order(stores,v,pi,data,pricingData.nextStoresByVehicle[v])
    conflictMasks = pricingStaticData.conflictMasksByVehicle[v]

    roots = Vector{Tuple{Float64,Int,PulseState{N},Float64}}()
    sizehint!(roots,length(stores))

    rcLowerBound = 0.0
    firstRoot = true

    for s in stores
        state = initial_pulse_state(Val(N), s, v, pi, data, max_t, t_descarga, timeWindows, conflictMasks)
        state === nothing && continue

        lb = pulse_full_lower_bound(state,totalPositivePi,orderPi,orderWeight,orderVolume,pi,alphav,data,v,max_t,t_descarga,conflictMasks; compatibilityBound=true)
        push!(roots,(priority(s),s,state,lb))

        if firstRoot
            rcLowerBound = min(0.0,lb)
            firstRoot = false
        else
            rcLowerBound = min(rcLowerBound,lb)
        end
    end

    sort!(roots,by=x -> x[1],rev=true)

    return (
        stores=stores,
        orderPi=orderPi,
        orderWeight=orderWeight,
        orderVolume=orderVolume,
        totalPositivePi=totalPositivePi,
        branchOrder=branchOrder,
        conflictMasks=conflictMasks,
        roots=roots,
        rcLowerBound=firstRoot ? 0.0 : min(0.0,rcLowerBound)
    )
end

# -----------------------------------------------------------------------------
# DFS search engine: finds ANY new negative route. For column generation this is
# enough; minimizing RC exactly every iteration is unnecessary work.
# -----------------------------------------------------------------------------

function pulse_find_negative!(prepared, v, pi, alphav, data, max_t, t_descarga, timeWindows, existingKeys;
    tolRC=1e-6,
    nodeLimit=typemax(Int),
    timeLimit=Inf,
    progressEvery=50000,
    progressSeconds=1.0,
    dashboard=nothing,
    phaseText="BUSCA",
    globalStop=nothing,
    dominanceMaxKeys=50000,
    compatibilityBound=true)

    if isempty(prepared.roots)
        return (result=nothing, expanded=0, generated=0, boundPruned=0, pruneQuick=0, pruneTime=0, pruneWeight=0, pruneVolume=0, pruneConflict=0, compatibilityChecks=0, dominancePruned=0, cacheClears=0, cachePeak=0, bestSeenRC=Inf, aborted=false, elapsed=0.0)
    end

    cache = Dict{Tuple{Int,typeof(prepared.roots[1][3].visited)},Vector{TemporalRecord}}()
    cacheClears = Ref(0)
    cachePeak = Ref(0)

    path = Int[]
    expanded = Ref(0)
    generated = Ref(0)
    pruneQuick = Ref(0)
    pruneTime = Ref(0)
    pruneWeight = Ref(0)
    pruneVolume = Ref(0)
    pruneConflict = Ref(0)
    compatibilityChecks = Ref(0)
    dominancePruned = Ref(0)
    bestSeenRC = Ref(Inf)
    result = Ref{Any}(nothing)
    aborted = Ref(false)

    startedAt = time()
    lastProgress = Ref(startedAt)
    currentRoot = Ref(0)
    nRoots = length(prepared.roots)

    function external_stop()
        globalStop !== nothing && globalStop[] != 0 && return true
        expanded[] >= nodeLimit && return true
        isfinite(timeLimit) && time() - startedAt >= timeLimit && return true
        return false
    end

    function maybe_progress!(depth)
        dashboard === nothing && return
        progressEvery <= 0 && return
        expanded[] % progressEvery != 0 && return

        now = time()
        now - lastProgress[] < progressSeconds && return
        lastProgress[] = now

        elapsed = max(now - startedAt,1e-9)
        speed = expanded[] / elapsed
        rcText = isfinite(bestSeenRC[]) ? string(round(bestSeenRC[],digits=2)) : "--"
        cacheText = dominanceMaxKeys > 0 ? "$(compact_count(length(cache)))/$(compact_count(dominanceMaxKeys))" : "off"
        pruneText = "$(compact_count(pruneQuick[]))/$(compact_count(pruneTime[]))/$(compact_count(pruneWeight[]))/$(compact_count(pruneVolume[]))/$(compact_count(pruneConflict[]))"

        dashboard_vehicle!(dashboard,v,"$phaseText | raiz=$(currentRoot[])/$nRoots | nos=$(compact_count(expanded[])) | $(compact_count(round(Int,speed)))/s | prof=$depth | RC=$rcText | P(q/t/w/v/c)=$pruneText | dom=$(compact_count(dominancePruned[])) | cache=$cacheText clr=$(cacheClears[])")
    end

    function pulse!(state::PulseState, depth)
        generated[] += 1

        if generated[] % 1024 == 0 && external_stop()
            aborted[] = true
            return false
        end

        decision = pulse_prune_decision(state,0.0,prepared.totalPositivePi,prepared.orderPi,prepared.orderWeight,prepared.orderVolume,pi,alphav,data,v,max_t,t_descarga,prepared.conflictMasks; tol=tolRC, compatibilityBound=compatibilityBound)
        decision.compatibilityChecked && (compatibilityChecks[] += 1)

        if decision.stage != 0x00
            decision.stage == 0x01 && (pruneQuick[] += 1)
            decision.stage == 0x02 && (pruneTime[] += 1)
            decision.stage == 0x03 && (pruneWeight[] += 1)
            decision.stage == 0x04 && (pruneVolume[] += 1)
            decision.stage == 0x05 && (pruneConflict[] += 1)
            return false
        end

        if dominanceMaxKeys > 0 && dominated_or_register!(cache,state,dominanceMaxKeys,cacheClears)
            dominancePruned[] += 1
            return false
        end
        length(cache) > cachePeak[] && (cachePeak[] = length(cache))

        expanded[] += 1
        rc = reduced_cost(state,alphav)
        rc < bestSeenRC[] && (bestSeenRC[] = rc)

        if rc < -tolRC
            rota = [1; path; 1]
            if !(route_key(rota) in existingKeys)
                result[] = (reduced_cost=rc, rota=copy(rota), custo=state.custo, veiculo=v)
                return true
            end
        end

        maybe_progress!(depth)

        for store in prepared.branchOrder[state.lastStore]
            mask_contains(state.visited,store) && continue
            child = extend_pulse_state(state,store,v,pi,data,max_t,t_descarga,timeWindows,prepared.conflictMasks)
            child === nothing && continue

            push!(path,store)
            found = pulse!(child,depth + 1)
            pop!(path)

            found && return true
            aborted[] && return false
        end

        return false
    end

    for (rootIdx,(_,s,state,rootLB)) in enumerate(prepared.roots)
        currentRoot[] = rootIdx

        external_stop() && (aborted[] = true; break)
        rootLB >= -tolRC && (pruneConflict[] += 1; continue)

        empty!(path)
        push!(path,s)
        found = pulse!(state,1)
        found && break
        aborted[] && break
    end

    empty!(path)
    boundPruned = pruneQuick[] + pruneTime[] + pruneWeight[] + pruneVolume[] + pruneConflict[]

    return (
        result=result[], expanded=expanded[], generated=generated[], boundPruned=boundPruned,
        pruneQuick=pruneQuick[], pruneTime=pruneTime[], pruneWeight=pruneWeight[], pruneVolume=pruneVolume[], pruneConflict=pruneConflict[],
        compatibilityChecks=compatibilityChecks[], dominancePruned=dominancePruned[], cacheClears=cacheClears[], cachePeak=cachePeak[],
        bestSeenRC=bestSeenRC[], aborted=aborted[], elapsed=time() - startedAt
    )
end

# -----------------------------------------------------------------------------
# FAST vehicle pricing
# -----------------------------------------------------------------------------

function solve_fast_pricing_vehicle(v, pi, alphav, data, pricingData, pricingStaticData, max_t, t_descarga, timeWindows, existingKeys;
    tolRC=1e-6,
    heuristicStarts=16,
    fastNodeLimit=100000,
    fastTimeLimit=1.0,
    progressEvery=50000,
    progressSeconds=1.0,
    dashboard=nothing,
    dominanceMaxKeys=30000,
    compatibilityBound=true)

    nMaskWords = cld(data.nStores - 1,64)
    return _solve_fast_pricing_vehicle(Val(nMaskWords),v,pi,alphav,data,pricingData,pricingStaticData,max_t,t_descarga,timeWindows,existingKeys;
        tolRC=tolRC, heuristicStarts=heuristicStarts, fastNodeLimit=fastNodeLimit, fastTimeLimit=fastTimeLimit,
        progressEvery=progressEvery, progressSeconds=progressSeconds, dashboard=dashboard, dominanceMaxKeys=dominanceMaxKeys, compatibilityBound=compatibilityBound)
end

function _solve_fast_pricing_vehicle(::Val{N}, v, pi, alphav, data, pricingData, pricingStaticData::PricingStaticSearchData{N}, max_t, t_descarga, timeWindows, existingKeys;
    tolRC=1e-6,
    heuristicStarts=16,
    fastNodeLimit=100000,
    fastTimeLimit=1.0,
    progressEvery=50000,
    progressSeconds=1.0,
    dashboard=nothing,
    dominanceMaxKeys=30000,
    compatibilityBound=true) where N

    prepared = prepare_vehicle_search(Val(N),v,pi,alphav,data,pricingData,pricingStaticData,max_t,t_descarga,timeWindows)
    prepared === nothing && return (result=nothing, rc_lower_bound=0.0, expanded=0, generated=0, boundPruned=0, pruneQuick=0, pruneTime=0, pruneWeight=0, pruneVolume=0, pruneConflict=0, compatibilityChecks=0, dominancePruned=0, cacheClears=0, cachePeak=0, heuristicCalls=0, source=:empty, elapsed=0.0)

    startedAt = time()

    progressCallback = dashboard === nothing ? nothing : (k,n,bestRC) -> begin
        rcText = isfinite(bestRC) ? string(round(bestRC,digits=2)) : "--"
        dashboard_vehicle!(dashboard,v,"SAVINGS | seed=$k/$n | melhorRC=$rcText | $(compact_seconds(time()-startedAt))")
    end

    heuristic = run_reduced_cost_savings_heuristic(Val(N),prepared.stores,v,pi,alphav,data,prepared.branchOrder,prepared.conflictMasks,max_t,t_descarga,timeWindows; nStarts=heuristicStarts, progressCallback=progressCallback)

    if heuristic.rota !== nothing && heuristic.reduced_cost < -tolRC && !(route_key(heuristic.rota) in existingKeys)
        return (result=(reduced_cost=heuristic.reduced_cost, rota=heuristic.rota, custo=heuristic.custo, veiculo=v), rc_lower_bound=prepared.rcLowerBound, expanded=0, generated=0, boundPruned=0, pruneQuick=0, pruneTime=0, pruneWeight=0, pruneVolume=0, pruneConflict=0, compatibilityChecks=0, dominancePruned=0, cacheClears=0, cachePeak=0, heuristicCalls=heuristic.calls, source=:savings, elapsed=time()-startedAt)
    end

    dashboard !== nothing && dashboard_vehicle!(dashboard,v,"BUSCA RAPIDA | iniciando | limite=$(compact_count(fastNodeLimit)) nos")

    search = pulse_find_negative!(prepared,v,pi,alphav,data,max_t,t_descarga,timeWindows,existingKeys;
        tolRC=tolRC, nodeLimit=fastNodeLimit, timeLimit=fastTimeLimit, progressEvery=progressEvery,
        progressSeconds=progressSeconds, dashboard=dashboard, phaseText="RAPIDA", dominanceMaxKeys=dominanceMaxKeys, compatibilityBound=compatibilityBound)

    source = search.result === nothing ? :none : :fast_pulse

    return (result=search.result, rc_lower_bound=prepared.rcLowerBound, expanded=search.expanded, generated=search.generated, boundPruned=search.boundPruned, pruneQuick=search.pruneQuick, pruneTime=search.pruneTime, pruneWeight=search.pruneWeight, pruneVolume=search.pruneVolume, pruneConflict=search.pruneConflict, compatibilityChecks=search.compatibilityChecks, dominancePruned=search.dominancePruned, cacheClears=search.cacheClears, cachePeak=search.cachePeak, heuristicCalls=heuristic.calls, source=source, elapsed=time()-startedAt)
end

# -----------------------------------------------------------------------------
# EXACT certification vehicle pricing
# -----------------------------------------------------------------------------

function solve_exact_certification_vehicle(v, pi, alphav, data, pricingData, pricingStaticData, max_t, t_descarga, timeWindows, existingKeys;
    tolRC=1e-6,
    exactHeuristicStarts=48,
    progressEvery=50000,
    progressSeconds=1.0,
    dashboard=nothing,
    globalStop=nothing,
    dominanceMaxKeys=50000,
    compatibilityBound=true)

    nMaskWords = cld(data.nStores - 1,64)
    return _solve_exact_certification_vehicle(Val(nMaskWords),v,pi,alphav,data,pricingData,pricingStaticData,max_t,t_descarga,timeWindows,existingKeys;
        tolRC=tolRC, exactHeuristicStarts=exactHeuristicStarts, progressEvery=progressEvery, progressSeconds=progressSeconds,
        dashboard=dashboard, globalStop=globalStop, dominanceMaxKeys=dominanceMaxKeys, compatibilityBound=compatibilityBound)
end

function _solve_exact_certification_vehicle(::Val{N}, v, pi, alphav, data, pricingData, pricingStaticData::PricingStaticSearchData{N}, max_t, t_descarga, timeWindows, existingKeys;
    tolRC=1e-6,
    exactHeuristicStarts=48,
    progressEvery=50000,
    progressSeconds=1.0,
    dashboard=nothing,
    globalStop=nothing,
    dominanceMaxKeys=50000,
    compatibilityBound=true) where N

    prepared = prepare_vehicle_search(Val(N),v,pi,alphav,data,pricingData,pricingStaticData,max_t,t_descarga,timeWindows)
    prepared === nothing && return (result=nothing, proven_no_negative=true, expanded=0, generated=0, boundPruned=0, pruneQuick=0, pruneTime=0, pruneWeight=0, pruneVolume=0, pruneConflict=0, compatibilityChecks=0, dominancePruned=0, cacheClears=0, cachePeak=0, heuristicCalls=0, elapsed=0.0)

    # FAST already tried fewer seeds. A wider heuristic here is cheap compared
    # with a long exact DFS and can avoid it entirely.
    if exactHeuristicStarts > 0
        startedAt = time()
        progressCallback = dashboard === nothing ? nothing : (k,n,bestRC) -> begin
            rcText = isfinite(bestRC) ? string(round(bestRC,digits=2)) : "--"
            dashboard_vehicle!(dashboard,v,"SAVINGS+ | seed=$k/$n | melhorRC=$rcText | $(compact_seconds(time()-startedAt))")
        end

        heuristic = run_reduced_cost_savings_heuristic(Val(N),prepared.stores,v,pi,alphav,data,prepared.branchOrder,prepared.conflictMasks,max_t,t_descarga,timeWindows; nStarts=exactHeuristicStarts, progressCallback=progressCallback)

        if heuristic.rota !== nothing && heuristic.reduced_cost < -tolRC && !(route_key(heuristic.rota) in existingKeys)
            return (result=(reduced_cost=heuristic.reduced_cost, rota=heuristic.rota, custo=heuristic.custo, veiculo=v), proven_no_negative=false, expanded=0, generated=0, boundPruned=0, pruneQuick=0, pruneTime=0, pruneWeight=0, pruneVolume=0, pruneConflict=0, compatibilityChecks=0, dominancePruned=0, cacheClears=0, cachePeak=0, heuristicCalls=heuristic.calls, elapsed=time()-startedAt)
        end
    end

    dashboard !== nothing && dashboard_vehicle!(dashboard,v,"EXATO | certificando RC >= 0")

    search = pulse_find_negative!(prepared,v,pi,alphav,data,max_t,t_descarga,timeWindows,existingKeys;
        tolRC=tolRC, nodeLimit=typemax(Int), timeLimit=Inf, progressEvery=progressEvery, progressSeconds=progressSeconds,
        dashboard=dashboard, phaseText="EXATO", globalStop=globalStop, dominanceMaxKeys=dominanceMaxKeys, compatibilityBound=compatibilityBound)

    proven = search.result === nothing && !search.aborted

    return (result=search.result, proven_no_negative=proven, expanded=search.expanded, generated=search.generated, boundPruned=search.boundPruned, pruneQuick=search.pruneQuick, pruneTime=search.pruneTime, pruneWeight=search.pruneWeight, pruneVolume=search.pruneVolume, pruneConflict=search.pruneConflict, compatibilityChecks=search.compatibilityChecks, dominancePruned=search.dominancePruned, cacheClears=search.cacheClears, cachePeak=search.cachePeak, heuristicCalls=exactHeuristicStarts, elapsed=search.elapsed)
end

# -----------------------------------------------------------------------------
# Dynamic RAM scheduler
# -----------------------------------------------------------------------------

function desired_pricing_parallelism(; minParallel=1, maxParallel=min(8,Threads.nthreads()), ramLevel1=0.55, ramLevel2=0.68, ramLevel3=0.78, ramLevel4=0.88)
    maxParallel = clamp(maxParallel,1,Threads.nthreads())
    minParallel = clamp(minParallel,1,maxParallel)
    usage = ram_usage_fraction()

    desired = if usage >= ramLevel4
        1
    elseif usage >= ramLevel3
        2
    elseif usage >= ramLevel2
        4
    elseif usage >= ramLevel1
        6
    else
        maxParallel
    end

    return clamp(desired,minParallel,maxParallel), usage
end

function run_fast_phase(V, pi, alpha, data, pricingData, pricingStaticData, max_t, t_descarga, timeWindows, existingKeys;
    tolRC=1e-6,
    progressEvery=50000,
    progressSeconds=1.0,
    maxVisibleVehicles=5,
    minParallel=1,
    maxParallel=min(8,Threads.nthreads()),
    ramLevel1=0.55,
    ramLevel2=0.68,
    ramLevel3=0.78,
    ramLevel4=0.88,
    launchDelay=0.10,
    heuristicStarts=16,
    fastNodeLimit=100000,
    fastTimeLimit=1.0,
    dominanceMaxKeys=30000,
    compatibilityBound=true)

    results = Vector{Any}(undef,length(V)); fill!(results,nothing)
    rcLowerBounds = zeros(Float64,length(V))

    totalExpanded = Threads.Atomic{Int}(0)
    totalGenerated = Threads.Atomic{Int}(0)
    totalPruned = Threads.Atomic{Int}(0)
    totalDominated = Threads.Atomic{Int}(0)
    totalPruneQuick = Threads.Atomic{Int}(0)
    totalPruneTime = Threads.Atomic{Int}(0)
    totalPruneWeight = Threads.Atomic{Int}(0)
    totalPruneVolume = Threads.Atomic{Int}(0)
    totalPruneConflict = Threads.Atomic{Int}(0)
    totalCompatibilityChecks = Threads.Atomic{Int}(0)
    totalCacheClears = Threads.Atomic{Int}(0)
    maxCachePeak = Threads.Atomic{Int}(0)
    totalHeuristics = Threads.Atomic{Int}(0)

    dashboard = PricingProgressDashboard(length(V),"FAST"; maxVisible=min(maxVisibleVehicles,length(V)))
    finished = Channel{Tuple{Int,Int,Any}}(max(1,length(V)))

    nextIdx = 1
    running = 0
    completed = 0
    startedAt = time()

    while completed < length(V)
        desired, _ = desired_pricing_parallelism(; minParallel=minParallel,maxParallel=maxParallel,ramLevel1=ramLevel1,ramLevel2=ramLevel2,ramLevel3=ramLevel3,ramLevel4=ramLevel4)
        dashboard_scheduler!(dashboard; running=running,desired=desired)

        while nextIdx <= length(V) && running < desired
            idx = nextIdx
            v = V[idx]
            nextIdx += 1
            running += 1

            dashboard_start_vehicle!(dashboard,v,"SAVINGS | iniciando")
            dashboard_scheduler!(dashboard; running=running,desired=desired)

            # IMPORTANT: bind idx/v per task. A @spawn closure inside this while-loop
            # must not capture the mutable scheduler variables themselves, otherwise
            # a task may finish using the idx/v of a later launch.
            let taskIdx=idx, taskV=v
                Threads.@spawn begin
                    vehicleResult = try
                        solve_fast_pricing_vehicle(taskV,pi,alpha[taskV],data,pricingData,pricingStaticData,max_t,t_descarga,timeWindows,existingKeys;
                            tolRC=tolRC, heuristicStarts=heuristicStarts, fastNodeLimit=fastNodeLimit, fastTimeLimit=fastTimeLimit,
                            progressEvery=progressEvery, progressSeconds=progressSeconds, dashboard=dashboard, dominanceMaxKeys=dominanceMaxKeys, compatibilityBound=compatibilityBound)
                    catch err
                        (error=err,backtrace=catch_backtrace())
                    end
                    put!(finished,(taskIdx,taskV,vehicleResult))
                end
            end

            # Avoid paying launchDelay for every vehicle when RAM is comfortable.
            # The old 0.10 s default imposed ~10 s of pure scheduler delay for 100 vehicles.
            _, launchRam = desired_pricing_parallelism(; minParallel=minParallel,maxParallel=maxParallel,ramLevel1=ramLevel1,ramLevel2=ramLevel2,ramLevel3=ramLevel3,ramLevel4=ramLevel4)
            if launchDelay > 0 && launchRam >= ramLevel1
                sleep(launchRam >= ramLevel2 ? launchDelay : min(launchDelay,0.01))
            else
                yield()
            end
            desired, _ = desired_pricing_parallelism(; minParallel=minParallel,maxParallel=maxParallel,ramLevel1=ramLevel1,ramLevel2=ramLevel2,ramLevel3=ramLevel3,ramLevel4=ramLevel4)
        end

        idx,v,vehicleResult = take!(finished)
        running -= 1
        completed += 1

        if vehicleResult isa NamedTuple && haskey(vehicleResult,:error)
            close_dashboard!(dashboard,"Pricing FAST interrompido por erro.")
            Base.showerror(stderr,vehicleResult.error,vehicleResult.backtrace)
            println(stderr)
            throw(vehicleResult.error)
        end

        results[idx] = vehicleResult.result
        rcLowerBounds[idx] = vehicleResult.rc_lower_bound

        Threads.atomic_add!(totalExpanded,vehicleResult.expanded)
        Threads.atomic_add!(totalGenerated,vehicleResult.generated)
        Threads.atomic_add!(totalPruned,vehicleResult.boundPruned)
        Threads.atomic_add!(totalDominated,vehicleResult.dominancePruned)
        Threads.atomic_add!(totalPruneQuick,vehicleResult.pruneQuick)
        Threads.atomic_add!(totalPruneTime,vehicleResult.pruneTime)
        Threads.atomic_add!(totalPruneWeight,vehicleResult.pruneWeight)
        Threads.atomic_add!(totalPruneVolume,vehicleResult.pruneVolume)
        Threads.atomic_add!(totalPruneConflict,vehicleResult.pruneConflict)
        Threads.atomic_add!(totalCompatibilityChecks,vehicleResult.compatibilityChecks)
        Threads.atomic_add!(totalCacheClears,vehicleResult.cacheClears)
        while vehicleResult.cachePeak > maxCachePeak[]
            oldPeak = maxCachePeak[]
            oldPeak >= vehicleResult.cachePeak && break
            Threads.atomic_cas!(maxCachePeak,oldPeak,vehicleResult.cachePeak) == oldPeak && break
        end
        Threads.atomic_add!(totalHeuristics,vehicleResult.heuristicCalls)

        dashboard_finish_vehicle!(dashboard,v)
        dashboard_scheduler!(dashboard; running=running,desired=desired)

        ram_usage_fraction() >= ramLevel3 && GC.gc(false)
    end

    negatives = [r for r in results if r !== nothing && r.reduced_cost < -tolRC]
    elapsed = time() - startedAt
    breakdown = "q/t/w/v/c=$(compact_count(totalPruneQuick[]))/$(compact_count(totalPruneTime[]))/$(compact_count(totalPruneWeight[]))/$(compact_count(totalPruneVolume[]))/$(compact_count(totalPruneConflict[]))"
    msg = "Pricing FAST concluido | negativas=$(length(negatives)) | nos=$(compact_count(totalExpanded[])) | podas[$breakdown] | dom=$(compact_count(totalDominated[])) | cachePeak=$(compact_count(maxCachePeak[])) | clr=$(totalCacheClears[]) | $(compact_seconds(elapsed))"
    close_dashboard!(dashboard,msg)

    return (results=results, negatives=negatives, rc_lower_bounds=rcLowerBounds, expanded=totalExpanded[], generated=totalGenerated[], pruned=totalPruned[], pruneQuick=totalPruneQuick[], pruneTime=totalPruneTime[], pruneWeight=totalPruneWeight[], pruneVolume=totalPruneVolume[], pruneConflict=totalPruneConflict[], compatibilityChecks=totalCompatibilityChecks[], dominated=totalDominated[], cacheClears=totalCacheClears[], cachePeak=maxCachePeak[], heuristics=totalHeuristics[], elapsed=elapsed)
end

function run_exact_certification_phase(V, pi, alpha, data, pricingData, pricingStaticData, max_t, t_descarga, timeWindows, existingKeys;
    tolRC=1e-6,
    progressEvery=50000,
    progressSeconds=1.0,
    maxVisibleVehicles=5,
    minParallel=1,
    maxParallel=min(8,Threads.nthreads()),
    ramLevel1=0.55,
    ramLevel2=0.68,
    ramLevel3=0.78,
    ramLevel4=0.88,
    launchDelay=0.10,
    exactHeuristicStarts=48,
    dominanceMaxKeys=50000,
    compatibilityBound=true)

    results = Vector{Any}(undef,length(V)); fill!(results,nothing)
    proven = falses(length(V))
    foundNegatives = Any[]

    totalExpanded = Threads.Atomic{Int}(0)
    totalGenerated = Threads.Atomic{Int}(0)
    totalPruned = Threads.Atomic{Int}(0)
    totalDominated = Threads.Atomic{Int}(0)
    totalPruneQuick = Threads.Atomic{Int}(0)
    totalPruneTime = Threads.Atomic{Int}(0)
    totalPruneWeight = Threads.Atomic{Int}(0)
    totalPruneVolume = Threads.Atomic{Int}(0)
    totalPruneConflict = Threads.Atomic{Int}(0)
    totalCompatibilityChecks = Threads.Atomic{Int}(0)
    totalCacheClears = Threads.Atomic{Int}(0)
    maxCachePeak = Threads.Atomic{Int}(0)
    stopFlag = Threads.Atomic{Int}(0)

    dashboard = PricingProgressDashboard(length(V),"EXATO"; maxVisible=min(maxVisibleVehicles,length(V)))
    finished = Channel{Tuple{Int,Int,Any}}(max(1,length(V)))

    nextIdx = 1
    running = 0
    completed = 0
    started = 0
    startedAt = time()

    while running > 0 || (nextIdx <= length(V) && stopFlag[] == 0)
        desired, _ = desired_pricing_parallelism(; minParallel=minParallel,maxParallel=maxParallel,ramLevel1=ramLevel1,ramLevel2=ramLevel2,ramLevel3=ramLevel3,ramLevel4=ramLevel4)
        dashboard_scheduler!(dashboard; running=running,desired=desired)

        while stopFlag[] == 0 && nextIdx <= length(V) && running < desired
            idx = nextIdx
            v = V[idx]
            nextIdx += 1
            running += 1
            started += 1

            dashboard_start_vehicle!(dashboard,v,"SAVINGS+ | iniciando")
            dashboard_scheduler!(dashboard; running=running,desired=desired)

            # Bind scheduler variables to immutable task-local values. Without
            # this let, concurrent tasks can observe a later idx/v from the while-loop,
            # causing results to be stored in the wrong slot and even overwritten.
            let taskIdx=idx, taskV=v
                Threads.@spawn begin
                    vehicleResult = try
                        solve_exact_certification_vehicle(taskV,pi,alpha[taskV],data,pricingData,pricingStaticData,max_t,t_descarga,timeWindows,existingKeys;
                            tolRC=tolRC, exactHeuristicStarts=exactHeuristicStarts, progressEvery=progressEvery, progressSeconds=progressSeconds,
                            dashboard=dashboard, globalStop=stopFlag, dominanceMaxKeys=dominanceMaxKeys, compatibilityBound=compatibilityBound)
                    catch err
                        (error=err,backtrace=catch_backtrace())
                    end
                    put!(finished,(taskIdx,taskV,vehicleResult))
                end
            end

            # Avoid paying launchDelay for every vehicle when RAM is comfortable.
            # The old 0.10 s default imposed ~10 s of pure scheduler delay for 100 vehicles.
            _, launchRam = desired_pricing_parallelism(; minParallel=minParallel,maxParallel=maxParallel,ramLevel1=ramLevel1,ramLevel2=ramLevel2,ramLevel3=ramLevel3,ramLevel4=ramLevel4)
            if launchDelay > 0 && launchRam >= ramLevel1
                sleep(launchRam >= ramLevel2 ? launchDelay : min(launchDelay,0.01))
            else
                yield()
            end
            desired, _ = desired_pricing_parallelism(; minParallel=minParallel,maxParallel=maxParallel,ramLevel1=ramLevel1,ramLevel2=ramLevel2,ramLevel3=ramLevel3,ramLevel4=ramLevel4)
        end

        running == 0 && break

        idx,v,vehicleResult = take!(finished)
        running -= 1
        completed += 1

        if vehicleResult isa NamedTuple && haskey(vehicleResult,:error)
            close_dashboard!(dashboard,"Pricing EXATO interrompido por erro.")
            Base.showerror(stderr,vehicleResult.error,vehicleResult.backtrace)
            println(stderr)
            throw(vehicleResult.error)
        end

        results[idx] = vehicleResult.result
        proven[idx] = vehicleResult.proven_no_negative

        # IMPORTANT: workers never set the global cancellation flag themselves.
        # The scheduler first stores the negative result, then cancels the other
        # active workers. This avoids the race where all active searches abort
        # but the route that triggered the stop is not yet registered here.
        if vehicleResult.result !== nothing && vehicleResult.result.reduced_cost < -tolRC
            # Keep the triggering result independently of the indexed results array.
            # This makes cancellation robust even if other active workers return
            # immediately after the stop signal.
            push!(foundNegatives,vehicleResult.result)
            stopFlag[] = 1
        end

        Threads.atomic_add!(totalExpanded,vehicleResult.expanded)
        Threads.atomic_add!(totalGenerated,vehicleResult.generated)
        Threads.atomic_add!(totalPruned,vehicleResult.boundPruned)
        Threads.atomic_add!(totalDominated,vehicleResult.dominancePruned)
        Threads.atomic_add!(totalPruneQuick,vehicleResult.pruneQuick)
        Threads.atomic_add!(totalPruneTime,vehicleResult.pruneTime)
        Threads.atomic_add!(totalPruneWeight,vehicleResult.pruneWeight)
        Threads.atomic_add!(totalPruneVolume,vehicleResult.pruneVolume)
        Threads.atomic_add!(totalPruneConflict,vehicleResult.pruneConflict)
        Threads.atomic_add!(totalCompatibilityChecks,vehicleResult.compatibilityChecks)
        Threads.atomic_add!(totalCacheClears,vehicleResult.cacheClears)
        while vehicleResult.cachePeak > maxCachePeak[]
            oldPeak = maxCachePeak[]
            oldPeak >= vehicleResult.cachePeak && break
            Threads.atomic_cas!(maxCachePeak,oldPeak,vehicleResult.cachePeak) == oldPeak && break
        end

        dashboard_finish_vehicle!(dashboard,v)
        dashboard_scheduler!(dashboard; running=running,desired=desired)

        ram_usage_fraction() >= ramLevel3 && GC.gc(false)
    end

    negatives = foundNegatives
    certifiedNoNegative = isempty(negatives) && stopFlag[] == 0 && nextIdx > length(V) && running == 0 && all(proven)
    elapsed = time() - startedAt

    breakdown = "q/t/w/v/c=$(compact_count(totalPruneQuick[]))/$(compact_count(totalPruneTime[]))/$(compact_count(totalPruneWeight[]))/$(compact_count(totalPruneVolume[]))/$(compact_count(totalPruneConflict[]))"
    msg = if certifiedNoNegative
        "Pricing EXATO concluido | CERTIFICADO | nos=$(compact_count(totalExpanded[])) | podas[$breakdown] | dom=$(compact_count(totalDominated[])) | cachePeak=$(compact_count(maxCachePeak[])) | clr=$(totalCacheClears[]) | $(compact_seconds(elapsed))"
    elseif !isempty(negatives)
        "Pricing EXATO encontrou negativa | negativas=$(length(negatives)) | iniciados=$started/$(length(V)) | concluidos=$completed | nos=$(compact_count(totalExpanded[])) | podas[$breakdown] | dom=$(compact_count(totalDominated[])) | cachePeak=$(compact_count(maxCachePeak[])) | $(compact_seconds(elapsed))"
    else
        "Pricing EXATO INCONCLUSIVO | negativas=0 | iniciados=$started/$(length(V)) | concluidos=$completed | stop=$(stopFlag[]) | nos=$(compact_count(totalExpanded[])) | podas[$breakdown] | dom=$(compact_count(totalDominated[])) | cachePeak=$(compact_count(maxCachePeak[])) | $(compact_seconds(elapsed))"
    end
    close_dashboard!(dashboard,msg)

    return (results=results, negatives=negatives, certified_no_negative=certifiedNoNegative, expanded=totalExpanded[], generated=totalGenerated[], pruned=totalPruned[], pruneQuick=totalPruneQuick[], pruneTime=totalPruneTime[], pruneWeight=totalPruneWeight[], pruneVolume=totalPruneVolume[], pruneConflict=totalPruneConflict[], compatibilityChecks=totalCompatibilityChecks[], dominated=totalDominated[], cacheClears=totalCacheClears[], cachePeak=maxCachePeak[], elapsed=elapsed, started=started, completed=completed)
end

const PRICING_BUILD = "STATIC-PRECOMPUTE-V5-TASKCAPTURE-FIX-2026-09-01"

# -----------------------------------------------------------------------------
# Drop-in public entry point
# -----------------------------------------------------------------------------

function solve_all_exact_labelings(V, pi, alpha, data, pricingData, pricingStaticData, max_t, t_descarga, timeWindows, rotasExistentes;
    tolRC=1e-6,
    progressEvery=50000,
    progressSeconds=1.0,
    maxVisibleVehicles=5,
    minParallel=1,
    maxParallel=min(8,Threads.nthreads()),
    ramLevel1=0.55,
    ramLevel2=0.68,
    ramLevel3=0.78,
    ramLevel4=0.88,
    launchDelay=0.10,
    heuristicStarts=16,
    exactHeuristicStarts=48,
    fastNodeLimit=100000,
    fastTimeLimit=1.0,
    dominanceMaxKeysFast=30000,
    dominanceMaxKeysExact=50000,
    compatibilityBoundFast=true,
    compatibilityBoundExact=true,
    heuristicRefreshEvery=0)

    println("Pricing build: $(PRICING_BUILD) | conflitos precomputados | bound q/t/w/v/c ativo")
    existingKeys = Set(route_key(r) for r in rotasExistentes)
    totalStartedAt = time()

    fast = run_fast_phase(V,pi,alpha,data,pricingData,pricingStaticData,max_t,t_descarga,timeWindows,existingKeys;
        tolRC=tolRC, progressEvery=progressEvery, progressSeconds=progressSeconds, maxVisibleVehicles=maxVisibleVehicles,
        minParallel=minParallel, maxParallel=maxParallel, ramLevel1=ramLevel1, ramLevel2=ramLevel2, ramLevel3=ramLevel3,
        ramLevel4=ramLevel4, launchDelay=launchDelay, heuristicStarts=heuristicStarts, fastNodeLimit=fastNodeLimit,
        fastTimeLimit=fastTimeLimit, dominanceMaxKeys=dominanceMaxKeysFast, compatibilityBound=compatibilityBoundFast)

    # A real/safe LP lower bound is available even without exact pricing.
    # rc_lower_bounds[v] <= true minimum reduced cost of vehicle v.
    rcLowerBounds = fast.rc_lower_bounds

    if !isempty(fast.negatives)
        return (
            results=fast.results,
            negatives=fast.negatives,
            min_reduced_costs=rcLowerBounds,
            rc_lower_bounds=rcLowerBounds,
            certified_no_negative=false,
            lb_is_exact=false,
            pricing_stage=:fast,
            elapsed=time()-totalStartedAt
        )
    end

    println("FAST nao encontrou coluna negativa. Iniciando certificacao exata...")

    exact = run_exact_certification_phase(V,pi,alpha,data,pricingData,pricingStaticData,max_t,t_descarga,timeWindows,existingKeys;
        tolRC=tolRC, progressEvery=progressEvery, progressSeconds=progressSeconds, maxVisibleVehicles=maxVisibleVehicles,
        minParallel=minParallel, maxParallel=maxParallel, ramLevel1=ramLevel1, ramLevel2=ramLevel2, ramLevel3=ramLevel3,
        ramLevel4=ramLevel4, launchDelay=launchDelay, exactHeuristicStarts=exactHeuristicStarts, dominanceMaxKeys=dominanceMaxKeysExact, compatibilityBound=compatibilityBoundExact)

    if exact.certified_no_negative
        # If every vehicle was certified RC >= 0, the RMP is the full master LP optimum.
        exactBounds = zeros(Float64,length(V))
        return (
            results=exact.results,
            negatives=Any[],
            min_reduced_costs=exactBounds,
            rc_lower_bounds=exactBounds,
            certified_no_negative=true,
            lb_is_exact=true,
            pricing_stage=:certified,
            elapsed=time()-totalStartedAt
        )
    end

    return (
        results=exact.results,
        negatives=exact.negatives,
        min_reduced_costs=rcLowerBounds,
        rc_lower_bounds=rcLowerBounds,
        certified_no_negative=false,
        lb_is_exact=false,
        pricing_stage=:exact_found_negative,
        elapsed=time()-totalStartedAt
    )
end

# =============================================================================
# V6 - pricing modes controlled by main(...; flag=...)
# =============================================================================
# flag = -1 : FAST normally; if FAST finds none, EXACT certification stops after
#             the first vehicle with a negative column (legacy/current behavior).
# flag =  0 : FAST normally; if FAST finds none, EXACT MIN solves ALL vehicles.
# flag =  1 : same as flag 0 until exact is first needed; from that iteration on,
#             EXACT MIN solves ALL vehicles in every following iteration.
# flag =  2 : EXACT MIN solves ALL vehicles from the first iteration onward.
#
# EXACT MIN below computes min(0, min reduced cost among NEW columns) for each
# vehicle, not merely the first negative route. Since all columns already in the
# RMP have nonnegative reduced cost at an optimal RMP solution (up to tolerance),
# this is exactly what is required by the standard CG lower-bound correction:
#     LB = z_RMP + sum_v min(0, rcmin_v).
# =============================================================================

const PRICING_BUILD_FLAG_V6 = "STATIC-PRECOMPUTE-V6-FLAG-EXACTMIN-2026-09-01"

# Exact depth-first branch-and-bound for one vehicle. Unlike pulse_find_negative!,
# this does not stop at the first RC < 0. It keeps the best negative incumbent and
# exhausts/prunes every branch that could improve it, thereby proving
# min(0, rc*_v) exactly while retaining the low-memory Pulse/DFS architecture.
function pulse_minimize_rc!(prepared, v, pi, alphav, data, max_t, t_descarga, timeWindows, existingKeys;
    tolRC=1e-6,
    progressEvery=50000,
    progressSeconds=1.0,
    dashboard=nothing,
    dominanceMaxKeys=50000,
    compatibilityBound=true,
    incumbentResult=nothing)

    if isempty(prepared.roots)
        return (result=nothing, min_reduced_cost=0.0, expanded=0, generated=0, boundPruned=0, pruneQuick=0, pruneTime=0, pruneWeight=0, pruneVolume=0, pruneConflict=0, compatibilityChecks=0, dominancePruned=0, cacheClears=0, cachePeak=0, elapsed=0.0)
    end

    maskType = typeof(prepared.roots[1][3].visited)
    cache = Dict{Tuple{Int,maskType},Vector{TemporalRecord}}()
    cacheClears = Ref(0)
    cachePeak = Ref(0)

    path = Int[]
    expanded = Ref(0)
    generated = Ref(0)
    pruneQuick = Ref(0)
    pruneTime = Ref(0)
    pruneWeight = Ref(0)
    pruneVolume = Ref(0)
    pruneConflict = Ref(0)
    compatibilityChecks = Ref(0)
    dominancePruned = Ref(0)

    bestRC = Ref(0.0)
    bestResult = Ref{Any}(nothing)

    if incumbentResult !== nothing && incumbentResult.reduced_cost < -tolRC
        bestRC[] = incumbentResult.reduced_cost
        bestResult[] = incumbentResult
    end

    startedAt = time()
    lastProgress = Ref(startedAt)
    currentRoot = Ref(0)
    nRoots = length(prepared.roots)

    function maybe_progress!(depth)
        dashboard === nothing && return
        progressEvery <= 0 && return
        expanded[] % progressEvery != 0 && return

        now = time()
        now - lastProgress[] < progressSeconds && return
        lastProgress[] = now

        elapsed = max(now - startedAt,1e-9)
        speed = expanded[] / elapsed
        rcText = string(round(bestRC[],digits=2))
        cacheText = dominanceMaxKeys > 0 ? "$(compact_count(length(cache)))/$(compact_count(dominanceMaxKeys))" : "off"
        pruneText = "$(compact_count(pruneQuick[]))/$(compact_count(pruneTime[]))/$(compact_count(pruneWeight[]))/$(compact_count(pruneVolume[]))/$(compact_count(pruneConflict[]))"

        dashboard_vehicle!(dashboard,v,"EXATO MIN | raiz=$(currentRoot[])/$nRoots | nos=$(compact_count(expanded[])) | $(compact_count(round(Int,speed)))/s | prof=$depth | melhorRC=$rcText | P(q/t/w/v/c)=$pruneText | dom=$(compact_count(dominancePruned[])) | cache=$cacheText clr=$(cacheClears[])")
    end

    function pulse!(state::PulseState, depth)
        generated[] += 1

        # The pruning threshold is the best feasible NEW-column RC already found.
        # The safe lower bound of this subtree cannot beat it -> discard subtree.
        decision = pulse_prune_decision(state,bestRC[],prepared.totalPositivePi,prepared.orderPi,prepared.orderWeight,prepared.orderVolume,pi,alphav,data,v,max_t,t_descarga,prepared.conflictMasks; tol=tolRC, compatibilityBound=compatibilityBound)
        decision.compatibilityChecked && (compatibilityChecks[] += 1)

        if decision.stage != 0x00
            decision.stage == 0x01 && (pruneQuick[] += 1)
            decision.stage == 0x02 && (pruneTime[] += 1)
            decision.stage == 0x03 && (pruneWeight[] += 1)
            decision.stage == 0x04 && (pruneVolume[] += 1)
            decision.stage == 0x05 && (pruneConflict[] += 1)
            return
        end

        if dominanceMaxKeys > 0 && dominated_or_register!(cache,state,dominanceMaxKeys,cacheClears)
            dominancePruned[] += 1
            return
        end
        length(cache) > cachePeak[] && (cachePeak[] = length(cache))

        expanded[] += 1
        rc = reduced_cost(state,alphav)

        if rc < bestRC[] - tolRC
            rota = [1; path; 1]
            if !(route_key(rota) in existingKeys)
                bestRC[] = rc
                bestResult[] = (reduced_cost=rc, rota=copy(rota), custo=state.custo, veiculo=v)
            end
        end

        maybe_progress!(depth)

        for store in prepared.branchOrder[state.lastStore]
            mask_contains(state.visited,store) && continue
            child = extend_pulse_state(state,store,v,pi,data,max_t,t_descarga,timeWindows,prepared.conflictMasks)
            child === nothing && continue

            push!(path,store)
            pulse!(child,depth + 1)
            pop!(path)
        end
    end

    for (rootIdx,(_,s,state,rootLB)) in enumerate(prepared.roots)
        currentRoot[] = rootIdx

        # rootLB was computed before the incumbent was known, but remains a safe
        # lower bound. If it cannot improve bestRC, the whole root can be skipped.
        if rootLB >= bestRC[] - tolRC
            pruneQuick[] += 1
            continue
        end

        empty!(path)
        push!(path,s)
        pulse!(state,1)
    end

    empty!(path)
    boundPruned = pruneQuick[] + pruneTime[] + pruneWeight[] + pruneVolume[] + pruneConflict[]

    return (
        result=bestResult[], min_reduced_cost=bestRC[], expanded=expanded[], generated=generated[], boundPruned=boundPruned,
        pruneQuick=pruneQuick[], pruneTime=pruneTime[], pruneWeight=pruneWeight[], pruneVolume=pruneVolume[], pruneConflict=pruneConflict[],
        compatibilityChecks=compatibilityChecks[], dominancePruned=dominancePruned[], cacheClears=cacheClears[], cachePeak=cachePeak[], elapsed=time()-startedAt
    )
end

function solve_exact_min_pricing_vehicle(v, pi, alphav, data, pricingData, pricingStaticData, max_t, t_descarga, timeWindows, existingKeys;
    tolRC=1e-6,
    exactHeuristicStarts=48,
    progressEvery=50000,
    progressSeconds=1.0,
    dashboard=nothing,
    dominanceMaxKeys=50000,
    compatibilityBound=true)

    nMaskWords = cld(data.nStores - 1,64)
    return _solve_exact_min_pricing_vehicle(Val(nMaskWords),v,pi,alphav,data,pricingData,pricingStaticData,max_t,t_descarga,timeWindows,existingKeys;
        tolRC=tolRC, exactHeuristicStarts=exactHeuristicStarts, progressEvery=progressEvery, progressSeconds=progressSeconds,
        dashboard=dashboard, dominanceMaxKeys=dominanceMaxKeys, compatibilityBound=compatibilityBound)
end

function _solve_exact_min_pricing_vehicle(::Val{N}, v, pi, alphav, data, pricingData, pricingStaticData::PricingStaticSearchData{N}, max_t, t_descarga, timeWindows, existingKeys;
    tolRC=1e-6,
    exactHeuristicStarts=48,
    progressEvery=50000,
    progressSeconds=1.0,
    dashboard=nothing,
    dominanceMaxKeys=50000,
    compatibilityBound=true) where N

    prepared = prepare_vehicle_search(Val(N),v,pi,alphav,data,pricingData,pricingStaticData,max_t,t_descarga,timeWindows)
    prepared === nothing && return (result=nothing, min_reduced_cost=0.0, expanded=0, generated=0, boundPruned=0, pruneQuick=0, pruneTime=0, pruneWeight=0, pruneVolume=0, pruneConflict=0, compatibilityChecks=0, dominancePruned=0, cacheClears=0, cachePeak=0, heuristicCalls=0, elapsed=0.0)

    startedAt = time()
    incumbent = nothing
    heuristicCalls = 0

    if exactHeuristicStarts > 0
        progressCallback = dashboard === nothing ? nothing : (k,n,bestRC) -> begin
            rcText = isfinite(bestRC) ? string(round(bestRC,digits=2)) : "--"
            dashboard_vehicle!(dashboard,v,"SAVINGS EXATO | seed=$k/$n | melhorRC=$rcText | $(compact_seconds(time()-startedAt))")
        end

        heuristic = run_reduced_cost_savings_heuristic(Val(N),prepared.stores,v,pi,alphav,data,prepared.branchOrder,prepared.conflictMasks,max_t,t_descarga,timeWindows; nStarts=exactHeuristicStarts, progressCallback=progressCallback)
        heuristicCalls = heuristic.calls

        if heuristic.rota !== nothing && heuristic.reduced_cost < -tolRC && !(route_key(heuristic.rota) in existingKeys)
            incumbent = (reduced_cost=heuristic.reduced_cost, rota=heuristic.rota, custo=heuristic.custo, veiculo=v)
        end
    end

    dashboard !== nothing && dashboard_vehicle!(dashboard,v,"EXATO MIN | minimizando RC")

    search = pulse_minimize_rc!(prepared,v,pi,alphav,data,max_t,t_descarga,timeWindows,existingKeys;
        tolRC=tolRC, progressEvery=progressEvery, progressSeconds=progressSeconds, dashboard=dashboard,
        dominanceMaxKeys=dominanceMaxKeys, compatibilityBound=compatibilityBound, incumbentResult=incumbent)

    return (result=search.result, min_reduced_cost=search.min_reduced_cost, expanded=search.expanded, generated=search.generated, boundPruned=search.boundPruned, pruneQuick=search.pruneQuick, pruneTime=search.pruneTime, pruneWeight=search.pruneWeight, pruneVolume=search.pruneVolume, pruneConflict=search.pruneConflict, compatibilityChecks=search.compatibilityChecks, dominancePruned=search.dominancePruned, cacheClears=search.cacheClears, cachePeak=search.cachePeak, heuristicCalls=heuristicCalls, elapsed=time()-startedAt)
end

# Full exact phase: every vehicle is solved to its exact min(0, RC*_v).
# It NEVER cancels the remaining vehicles when one negative route is found.
function run_exact_minimization_phase(V, pi, alpha, data, pricingData, pricingStaticData, max_t, t_descarga, timeWindows, existingKeys;
    tolRC=1e-6,
    progressEvery=50000,
    progressSeconds=1.0,
    maxVisibleVehicles=5,
    minParallel=1,
    maxParallel=min(8,Threads.nthreads()),
    ramLevel1=0.55,
    ramLevel2=0.68,
    ramLevel3=0.78,
    ramLevel4=0.88,
    launchDelay=0.10,
    exactHeuristicStarts=48,
    dominanceMaxKeys=50000,
    compatibilityBound=true)

    results = Vector{Any}(undef,length(V)); fill!(results,nothing)
    minRCs = zeros(Float64,length(V))

    totalExpanded = Threads.Atomic{Int}(0)
    totalGenerated = Threads.Atomic{Int}(0)
    totalPruned = Threads.Atomic{Int}(0)
    totalDominated = Threads.Atomic{Int}(0)
    totalPruneQuick = Threads.Atomic{Int}(0)
    totalPruneTime = Threads.Atomic{Int}(0)
    totalPruneWeight = Threads.Atomic{Int}(0)
    totalPruneVolume = Threads.Atomic{Int}(0)
    totalPruneConflict = Threads.Atomic{Int}(0)
    totalCompatibilityChecks = Threads.Atomic{Int}(0)
    totalCacheClears = Threads.Atomic{Int}(0)
    maxCachePeak = Threads.Atomic{Int}(0)

    dashboard = PricingProgressDashboard(length(V),"EXATO MIN"; maxVisible=min(maxVisibleVehicles,length(V)))
    finished = Channel{Tuple{Int,Int,Any}}(max(1,length(V)))

    nextIdx = 1
    running = 0
    completed = 0
    startedAt = time()

    while running > 0 || nextIdx <= length(V)
        desired, _ = desired_pricing_parallelism(; minParallel=minParallel,maxParallel=maxParallel,ramLevel1=ramLevel1,ramLevel2=ramLevel2,ramLevel3=ramLevel3,ramLevel4=ramLevel4)
        dashboard_scheduler!(dashboard; running=running,desired=desired)

        while nextIdx <= length(V) && running < desired
            idx = nextIdx
            v = V[idx]
            nextIdx += 1
            running += 1

            dashboard_start_vehicle!(dashboard,v,"EXATO MIN | iniciando")
            dashboard_scheduler!(dashboard; running=running,desired=desired)

            let taskIdx=idx, taskV=v
                Threads.@spawn begin
                    vehicleResult = try
                        solve_exact_min_pricing_vehicle(taskV,pi,alpha[taskV],data,pricingData,pricingStaticData,max_t,t_descarga,timeWindows,existingKeys;
                            tolRC=tolRC, exactHeuristicStarts=exactHeuristicStarts, progressEvery=progressEvery, progressSeconds=progressSeconds,
                            dashboard=dashboard, dominanceMaxKeys=dominanceMaxKeys, compatibilityBound=compatibilityBound)
                    catch err
                        (error=err,backtrace=catch_backtrace())
                    end
                    put!(finished,(taskIdx,taskV,vehicleResult))
                end
            end

            _, launchRam = desired_pricing_parallelism(; minParallel=minParallel,maxParallel=maxParallel,ramLevel1=ramLevel1,ramLevel2=ramLevel2,ramLevel3=ramLevel3,ramLevel4=ramLevel4)
            if launchDelay > 0 && launchRam >= ramLevel1
                sleep(launchRam >= ramLevel2 ? launchDelay : min(launchDelay,0.01))
            else
                yield()
            end
        end

        running == 0 && break

        idx,v,vehicleResult = take!(finished)
        running -= 1
        completed += 1

        if vehicleResult isa NamedTuple && haskey(vehicleResult,:error)
            close_dashboard!(dashboard,"Pricing EXATO MIN interrompido por erro.")
            Base.showerror(stderr,vehicleResult.error,vehicleResult.backtrace)
            println(stderr)
            throw(vehicleResult.error)
        end

        results[idx] = vehicleResult.result
        minRCs[idx] = min(0.0,vehicleResult.min_reduced_cost)

        Threads.atomic_add!(totalExpanded,vehicleResult.expanded)
        Threads.atomic_add!(totalGenerated,vehicleResult.generated)
        Threads.atomic_add!(totalPruned,vehicleResult.boundPruned)
        Threads.atomic_add!(totalDominated,vehicleResult.dominancePruned)
        Threads.atomic_add!(totalPruneQuick,vehicleResult.pruneQuick)
        Threads.atomic_add!(totalPruneTime,vehicleResult.pruneTime)
        Threads.atomic_add!(totalPruneWeight,vehicleResult.pruneWeight)
        Threads.atomic_add!(totalPruneVolume,vehicleResult.pruneVolume)
        Threads.atomic_add!(totalPruneConflict,vehicleResult.pruneConflict)
        Threads.atomic_add!(totalCompatibilityChecks,vehicleResult.compatibilityChecks)
        Threads.atomic_add!(totalCacheClears,vehicleResult.cacheClears)

        while vehicleResult.cachePeak > maxCachePeak[]
            oldPeak = maxCachePeak[]
            oldPeak >= vehicleResult.cachePeak && break
            Threads.atomic_cas!(maxCachePeak,oldPeak,vehicleResult.cachePeak) == oldPeak && break
        end

        dashboard_finish_vehicle!(dashboard,v)
        dashboard_scheduler!(dashboard; running=running,desired=desired)
        ram_usage_fraction() >= ramLevel3 && GC.gc(false)
    end

    negatives = [r for r in results if r !== nothing && r.reduced_cost < -tolRC]
    sort!(negatives,by=r -> r.reduced_cost)
    elapsed = time() - startedAt

    breakdown = "q/t/w/v/c=$(compact_count(totalPruneQuick[]))/$(compact_count(totalPruneTime[]))/$(compact_count(totalPruneWeight[]))/$(compact_count(totalPruneVolume[]))/$(compact_count(totalPruneConflict[]))"
    msg = "Pricing EXATO MIN completo | veiculos=$(length(V))/$(length(V)) | negativas=$(length(negatives)) | nos=$(compact_count(totalExpanded[])) | podas[$breakdown] | dom=$(compact_count(totalDominated[])) | cachePeak=$(compact_count(maxCachePeak[])) | clr=$(totalCacheClears[]) | $(compact_seconds(elapsed))"
    close_dashboard!(dashboard,msg)

    return (results=results, negatives=negatives, min_reduced_costs=minRCs, certified_no_negative=isempty(negatives), expanded=totalExpanded[], generated=totalGenerated[], pruned=totalPruned[], pruneQuick=totalPruneQuick[], pruneTime=totalPruneTime[], pruneWeight=totalPruneWeight[], pruneVolume=totalPruneVolume[], pruneConflict=totalPruneConflict[], compatibilityChecks=totalCompatibilityChecks[], dominated=totalDominated[], cacheClears=totalCacheClears[], cachePeak=maxCachePeak[], elapsed=elapsed, completed=completed)
end

# Public V6 entry point. This redefines the previous method with the same
# positional signature and adds pricingFlag / forceExact behavior.
function solve_all_exact_labelings(V, pi, alpha, data, pricingData, pricingStaticData, max_t, t_descarga, timeWindows, rotasExistentes;
    tolRC=1e-6,
    progressEvery=50000,
    progressSeconds=1.0,
    maxVisibleVehicles=5,
    minParallel=1,
    maxParallel=min(8,Threads.nthreads()),
    ramLevel1=0.55,
    ramLevel2=0.68,
    ramLevel3=0.78,
    ramLevel4=0.88,
    launchDelay=0.10,
    heuristicStarts=16,
    exactHeuristicStarts=48,
    fastNodeLimit=100000,
    fastTimeLimit=1.0,
    dominanceMaxKeysFast=30000,
    dominanceMaxKeysExact=50000,
    compatibilityBoundFast=true,
    compatibilityBoundExact=true,
    heuristicRefreshEvery=0,
    pricingFlag=-1,
    forceExact=false)

    pricingFlag in (-1,0,1,2) || error("flag deve ser -1, 0, 1 ou 2. Recebido: $pricingFlag")

    println("Pricing build: $(PRICING_BUILD_FLAG_V6) | flag=$pricingFlag | conflitos precomputados | bound q/t/w/v/c ativo")
    existingKeys = Set(route_key(r) for r in rotasExistentes)
    totalStartedAt = time()

    # flag=2 or flag=1 after activation: no FAST at all. Solve every vehicle to
    # exact min(0,RC*) and obtain an exact corrected LB for this iteration.
    if pricingFlag == 2 || forceExact
        exact = run_exact_minimization_phase(V,pi,alpha,data,pricingData,pricingStaticData,max_t,t_descarga,timeWindows,existingKeys;
            tolRC=tolRC, progressEvery=progressEvery, progressSeconds=progressSeconds, maxVisibleVehicles=maxVisibleVehicles,
            minParallel=minParallel, maxParallel=maxParallel, ramLevel1=ramLevel1, ramLevel2=ramLevel2, ramLevel3=ramLevel3,
            ramLevel4=ramLevel4, launchDelay=launchDelay, exactHeuristicStarts=exactHeuristicStarts,
            dominanceMaxKeys=dominanceMaxKeysExact, compatibilityBound=compatibilityBoundExact)

        return (results=exact.results, negatives=exact.negatives, min_reduced_costs=exact.min_reduced_costs, rc_lower_bounds=exact.min_reduced_costs, certified_no_negative=exact.certified_no_negative, lb_is_exact=true, pricing_stage=exact.certified_no_negative ? :certified : :exact_full, used_exact=true, exact_full=true, elapsed=time()-totalStartedAt)
    end

    # Flags -1, 0 and pre-activation 1 start with the cheap FAST phase.
    fast = run_fast_phase(V,pi,alpha,data,pricingData,pricingStaticData,max_t,t_descarga,timeWindows,existingKeys;
        tolRC=tolRC, progressEvery=progressEvery, progressSeconds=progressSeconds, maxVisibleVehicles=maxVisibleVehicles,
        minParallel=minParallel, maxParallel=maxParallel, ramLevel1=ramLevel1, ramLevel2=ramLevel2, ramLevel3=ramLevel3,
        ramLevel4=ramLevel4, launchDelay=launchDelay, heuristicStarts=heuristicStarts, fastNodeLimit=fastNodeLimit,
        fastTimeLimit=fastTimeLimit, dominanceMaxKeys=dominanceMaxKeysFast, compatibilityBound=compatibilityBoundFast)

    rcLowerBounds = fast.rc_lower_bounds

    if !isempty(fast.negatives)
        return (results=fast.results, negatives=fast.negatives, min_reduced_costs=rcLowerBounds, rc_lower_bounds=rcLowerBounds, certified_no_negative=false, lb_is_exact=false, pricing_stage=:fast, used_exact=false, exact_full=false, elapsed=time()-totalStartedAt)
    end

    # FAST found nothing. flag=-1 preserves the old early-stop certification.
    if pricingFlag == -1
        println("FAST nao encontrou coluna negativa. Iniciando EXATO early-stop (flag=-1)...")

        exact = run_exact_certification_phase(V,pi,alpha,data,pricingData,pricingStaticData,max_t,t_descarga,timeWindows,existingKeys;
            tolRC=tolRC, progressEvery=progressEvery, progressSeconds=progressSeconds, maxVisibleVehicles=maxVisibleVehicles,
            minParallel=minParallel, maxParallel=maxParallel, ramLevel1=ramLevel1, ramLevel2=ramLevel2, ramLevel3=ramLevel3,
            ramLevel4=ramLevel4, launchDelay=launchDelay, exactHeuristicStarts=exactHeuristicStarts,
            dominanceMaxKeys=dominanceMaxKeysExact, compatibilityBound=compatibilityBoundExact)

        if exact.certified_no_negative
            exactBounds = zeros(Float64,length(V))
            return (results=exact.results, negatives=Any[], min_reduced_costs=exactBounds, rc_lower_bounds=exactBounds, certified_no_negative=true, lb_is_exact=true, pricing_stage=:certified, used_exact=true, exact_full=true, elapsed=time()-totalStartedAt)
        end

        return (results=exact.results, negatives=exact.negatives, min_reduced_costs=rcLowerBounds, rc_lower_bounds=rcLowerBounds, certified_no_negative=false, lb_is_exact=false, pricing_stage=:exact_early_stop, used_exact=true, exact_full=false, elapsed=time()-totalStartedAt)
    end

    # flags 0 and 1: when exact is needed, solve ALL vehicles to the exact
    # minimum RC. For flag 1, columnGeneration.jl will activate forceExact from
    # the next iteration onward.
    println("FAST nao encontrou coluna negativa. Iniciando EXATO MIN para TODOS os veiculos (flag=$pricingFlag)...")

    exact = run_exact_minimization_phase(V,pi,alpha,data,pricingData,pricingStaticData,max_t,t_descarga,timeWindows,existingKeys;
        tolRC=tolRC, progressEvery=progressEvery, progressSeconds=progressSeconds, maxVisibleVehicles=maxVisibleVehicles,
        minParallel=minParallel, maxParallel=maxParallel, ramLevel1=ramLevel1, ramLevel2=ramLevel2, ramLevel3=ramLevel3,
        ramLevel4=ramLevel4, launchDelay=launchDelay, exactHeuristicStarts=exactHeuristicStarts,
        dominanceMaxKeys=dominanceMaxKeysExact, compatibilityBound=compatibilityBoundExact)

    return (results=exact.results, negatives=exact.negatives, min_reduced_costs=exact.min_reduced_costs, rc_lower_bounds=exact.min_reduced_costs, certified_no_negative=exact.certified_no_negative, lb_is_exact=true, pricing_stage=exact.certified_no_negative ? :certified : :exact_full, used_exact=true, exact_full=true, elapsed=time()-totalStartedAt)
end
