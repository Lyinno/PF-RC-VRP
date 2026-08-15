using JuMP
using HiGHS
import MathOptInterface as MOI


function route_key(rota)
    return Tuple(sort(unique(rota[2:end-1])))
end


function extract_route(z, nodes)
    CD = 1
    rota = [CD]
    atual = CD

    for _ in 1:(length(nodes) + 1)
        proximo = nothing

        for j in nodes
            if j != atual && value(z[atual,j]) > 0.5
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


function solve_pricing_vehicle(v, π, αv, vehiclesByStore, tempo, fretes, demandaPeso, demandaVolume, capPeso, capVolume, max_t, t_descarga, rotasExistentes)
    CD = 1
    lojas = [s for s in 2:size(tempo, 1) if v in vehiclesByStore[s]]
    nodes = [CD; lojas]
    N = length(lojas)

    model = Model(HiGHS.Optimizer)
    set_silent(model)
    set_attribute(model, MOI.NumberOfThreads(), 1)

    # Variável para criar a rota, se y[k] = 1 quer dizer que a rota visita a loja k
    @variable(model, y[lojas], Bin)
    # Variável para informar os arcos que a rota fez se z[k1, k2] = 1 quer dizer que a rota faz o arco k1 -> k2
    @variable(model, z[nodes, nodes], Bin)
    # Frete da rota
    @variable(model, custo >= 0)
    # Variavel auxiliar para impedir subtours, tipo 1->2->3->1 4->5 ela indica a ordem que as lojas são visitadas na rota
    @variable(model, 1 <= u[lojas] <= N)

    # Impedir que a rota faça algo como k->k
    for i in nodes
        fix(z[i,i], 0.0; force=true)
    end

    # tem que haver um arco saindo do CD e um chegando no CD
    @constraint(model, sum(z[CD,j] for j in lojas) == 1)
    @constraint(model, sum(z[i,CD] for i in lojas) == 1)

    # Se visitou a loja tem que ter um arco entrando e saindo dela
    @constraint(model, entrada[s in lojas], sum(z[i,s] for i in nodes if i != s) == y[s])
    @constraint(model, saida[s in lojas], sum(z[s,j] for j in nodes if j != s) == y[s])

    @constraint(model, [i in lojas, j in lojas; i != j], u[i] - u[j] + N * z[i,j] <= N - 1)

    @constraint(model, sum(demandaPeso[s] * y[s] for s in lojas) <= capPeso[v])
    @constraint(model, sum(demandaVolume[s] * y[s] for s in lojas) <= capVolume[v])

    @constraint(model, sum(tempo[i,j] * z[i,j] for i in nodes, j in nodes if i != j) + t_descarga * sum(y[s] for s in lojas) <= max_t)

    for s in lojas
        @constraint(model, custo >= fretes[(s,v)] * y[s])
    end

    @objective(model, Min, custo - sum(π[s] * y[s] for s in lojas) - αv)

    optimize!(model)

    if termination_status(model) != MOI.OPTIMAL || !has_values(model)
        return nothing
    end

    rota = extract_route(z, nodes)

    return (reduced_cost=objective_value(model), rota=rota, custo=value(custo), veiculo=v)
end


function solve_all_pricings(V, π, α, vehiclesByStore, tempo, fretes, demandaPeso, demandaVolume, capPeso, capVolume, max_t, t_descarga, rotas)
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
        resultados[i] = solve_pricing_vehicle(v, π, α[v], vehiclesByStore, tempo, fretes, demandaPeso, demandaVolume, capPeso, capVolume, max_t, t_descarga, rotas)

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
