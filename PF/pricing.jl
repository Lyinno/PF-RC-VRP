using JuMP
using HiGHS
import MathOptInterface as MOI


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


function solve_all_pricings(V, π, α, vehiclesByStore, tempo, fretes, demandaPeso, demandaVolume, capPeso, capVolume, max_t, t_descarga, rotas, timeWindows)
    resultados = Vector{Any}(undef, length(V))
    fill!(resultados, nothing)

    println("Realizando pricing para criação de novas rotas")
    println("Veículos: $(length(V)) | Threads Julia: $(Threads.nthreads())")

    concluidos = Threads.Atomic{Int}(0)
    printLock = ReentrantLock()
    total = length(V)

    print("Progresso pricing: 0/$total | Faltam: $total")
    flush(stdout)

    Threads.@threads for i in eachindex(V)
        v = V[i]
        resultados[i] = solve_pricing_vehicle(v, π, α[v], vehiclesByStore, tempo, fretes, demandaPeso, demandaVolume, capPeso, capVolume, max_t, t_descarga, rotas, timeWindows)

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