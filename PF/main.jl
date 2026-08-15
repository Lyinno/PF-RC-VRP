include("createRoutes.jl")
include("solvers.jl")
include("pricing.jl")
include("createRCRoutes.jl")
include("gap.jl")

using JuMP
using HiGHS
using Plots
import MathOptInterface as MOI


function get_integer_solution(x, rotas)
    selecionadas = []

    for r in axes(x,1), v in axes(x,2)
        if value(x[r,v]) > 0.5
            push!(selecionadas, (rota_index=r, veiculo=v, rota=rotas[r]))
        end
    end

    return selecionadas
end


function main(path, max_t, t_descarga, n_routes)
    allLB = []
    A, Ast, Custos, rotas, vehiclesByStore, tempo, fretes, df_demanda, df_capacidade = makeRoutes(path, max_t, t_descarga, n_routes)

    demandaPeso = Dict(row.store => row.demanda_peso for row in eachrow(df_demanda))
    demandaVolume = Dict(row.store => row.demanda_volume for row in eachrow(df_demanda))

    capPeso = Dict(row.vehicles => row.capacidade_peso for row in eachrow(df_capacidade))
    capVolume = Dict(row.vehicles => row.capacidade_volume for row in eachrow(df_capacidade))

    V = collect(axes(A, 2))

    iteracao = 1
    melhorUB = nothing
    melhorSolucao = nothing

    while true
        println("\n======================================================")
        println("ITERAÇÃO $iteracao")
        println("Rotas disponíveis: $(length(rotas))")
        println("======================================================")

        modelLP, xLP, atendimento, veiculo = solve_master_lp(A, Ast, Custos)

        if termination_status(modelLP) != MOI.OPTIMAL
            error("Master relaxado atual não é viável. Será necessária uma Phase I.")
        end

        LPAtual = objective_value(modelLP)
        π = dual.(atendimento)
        α = dual.(veiculo)

        modelIP, xIP = solve_master_integer(A, Ast, Custos)

        UBAtual = nothing

        if has_values(modelIP)
            UBAtual = objective_value(modelIP)

            if melhorUB === nothing || UBAtual < melhorUB
                melhorUB = UBAtual
                melhorSolucao = get_integer_solution(xIP, rotas)
            end
        end

        push!(allLB, LPAtual)
        gapAtual = calculate_gap(LPAtual, melhorUB)

        if melhorUB === nothing
            println("LB*: $LPAtual | UB: indisponível | Gap*: indisponível")
        else
            println("LB*: $LPAtual | UB: $melhorUB | Gap*: $(round(gapAtual, digits=4))%")
        end

        resultados = solve_all_pricings(V, π, α, vehiclesByStore, tempo, fretes, demandaPeso, demandaVolume, capPeso, capVolume, max_t, t_descarga, rotas)

        tolRC = 1e-6
        resultadosNegativos = [resultado for resultado in resultados if resultado !== nothing && resultado.reduced_cost < -tolRC]

        if isempty(resultadosNegativos)
            LB = LPAtual

            println("\n======================================================")
            println("COLUMN GENERATION CONCLUÍDO")
            println("======================================================")
            println("Nenhuma nova rota possui reduced cost negativo.")
            println("O ótimo da relaxação LP completa foi atingido.")

            println("\n---------------- BOUNDS FINAIS ----------------")
            println("LB: $LB")

            if melhorUB === nothing
                println("UB: indisponível")
                println("Gap: indisponível")
            else
                gapFinal = calculate_gap(LB, melhorUB)
                println("UB: $melhorUB")
                println("Gap: $(round(gapFinal, digits=4))%")
            end

            println("------------------------------------------------")
            println("Total de rotas no pool: $(length(rotas))")
            println("Número de iterações: $iteracao")

            if melhorSolucao !== nothing
                println("\nSolução inteira escolhida:")

                for sol in melhorSolucao
                    println("Veículo $(sol.veiculo) | Rota $(sol.rota_index) | $(sol.rota)")
                end
            end

            p = plot(allLB, xlabel="Iteração", ylabel="LB", title="Evolução do LB", marker=:circle)
            display(p)

            return (A=A, Ast=Ast, Custos=Custos, rotas=rotas, lower_bound=LB, upper_bound=melhorUB, gap=melhorUB === nothing ? nothing : calculate_gap(LB, melhorUB), solution=melhorSolucao, lp_model=modelLP, lp_x=xLP, integer_model=modelIP, integer_x=xIP)
        end

        # Remove duplicatas entre as novas rotas.
        resultadosUnicos = []
        chavesNovas = Set()

        for resultado in resultadosNegativos
            chave = route_key(resultado.rota)

            if !(chave in chavesNovas)
                push!(resultadosUnicos, resultado)
                push!(chavesNovas, chave)
            end
        end

        println("Rotas negativas únicas: $(length(resultadosUnicos))")

        # Adiciona TODAS as rotas negativas únicas.
        for resultado in resultadosUnicos
            novaRota = resultado.rota

            novaA, novaAst, novosCustos = create_route_rows(novaRota, V, size(Ast,2), vehiclesByStore, fretes, demandaPeso, demandaVolume, capPeso, capVolume)

            push!(rotas, novaRota)

            A = vcat(A, reshape(novaA, 1, :))
            Ast = vcat(Ast, reshape(novaAst, 1, :))
            Custos = vcat(Custos, reshape(novosCustos, 1, :))
        end

        iteracao += 1
    end
    
end


main("DatAnonymous\\Teste_50_num1.txt", 8, 1, 500)