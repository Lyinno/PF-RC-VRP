using JuMP
import MathOptInterface as MOI

function new_negative_results(resultados, rotas; tolRC=1e-6)
    existingKeys = Set(route_key(r) for r in rotas)
    newKeys = Set{Tuple}()
    negatives = Any[]

    for resultado in resultados
        resultado === nothing && continue
        resultado.reduced_cost < -tolRC || continue

        key = route_key(resultado.rota)
        key in existingKeys && continue
        key in newKeys && continue

        push!(negatives,resultado)
        push!(newKeys,key)
    end

    sort!(negatives,by=r -> r.reduced_cost)
    return negatives
end

function add_new_routes!(masterLP, A, Ast, Custos, rotas, resultados, V, data)
    nNew = length(resultados)
    nNew == 0 && return A, Ast, Custos

    newA = zeros(Int8,nNew,size(A,2))
    newAst = zeros(Int8,nNew,size(Ast,2))
    newCustos = zeros(Float64,nNew,size(Custos,2))

    for (k,resultado) in enumerate(resultados)
        novaRota = resultado.rota
        novaA, novaAst, novosCustos = create_route_rows(novaRota,V,data)

        push!(rotas,novaRota)
        newA[k,:] = novaA
        newAst[k,:] = novaAst
        newCustos[k,:] = novosCustos

        add_route_to_master_lp!(masterLP,novaA,novaAst,novosCustos)
    end

    return vcat(A,newA), vcat(Ast,newAst), vcat(Custos,newCustos)
end

function main(i, j, max_t, t_descarga, n_routes;
    ipEvery=5,
    labelingProgressEvery=50000,
    pricingProgressSeconds=1.0,
    pricingMinParallel=1,
    pricingMaxParallel=min(8,Threads.nthreads()),
    ramLevel1=0.55,
    ramLevel2=0.68,
    ramLevel3=0.78,
    ramLevel4=0.88,
    pricingLaunchDelay=0.10,
    heuristicStarts=16,
    exactHeuristicStarts=48,
    fastNodeLimit=100000,
    fastTimeLimit=1.0,
    dominanceMaxKeysFast=30000,
    dominanceMaxKeysExact=50000,
    compatibilityBoundFast=true,
    compatibilityBoundExact=true,
    flag=-1)

    flag in (-1,0,1,2) || error("flag deve ser -1, 0, 1 ou 2. Recebido: $flag")

    flagDescricao = flag == -1 ? "FAST + EXATO early-stop" : flag == 0 ? "FAST; EXATO completo quando necessario" : flag == 1 ? "FAST ate primeiro EXATO; depois EXATO sempre" : "EXATO completo desde o inicio"
    println("Modo pricing | flag=$flag | $flagDescricao")

    path = "DatAnonymous\\Teste_$(i)_num$(j).txt"
    timeWindowPath = "DatAnonymous\\janelas_$(i)_$(j)lojas.txt"

    inicioPrograma = time()

    melhorLB = -Inf
    melhorUB = nothing
    melhorSolucao = nothing
    warmStartIP = nothing

    temposBounds = Float64[]
    historicoLB = Float64[]
    historicoUB = Float64[]

    A, Ast, Custos, rotas, data, timeWindows = makeRoutes(path,timeWindowPath,max_t,t_descarga,n_routes)

    V = collect(1:data.nVehicles)
    masterLP = create_master_lp(A,Ast,Custos)
    pricingData = build_pricing_preprocess_data(V,data,max_t,t_descarga,timeWindows)

    # Expensive structural pricing data is independent of the master duals.
    # Build it ONCE and reuse it in every CG iteration (FAST and EXACT).
    pricingStaticData = build_pricing_static_search_data(V,data,pricingData,max_t,t_descarga,timeWindows)

    iteracao = 1
    ultimoModelIP = nothing
    ultimoXIP = nothing
    exactActivated = (flag == 2)

    while true
        print_iteration_header(iteracao,length(rotas))

        # Master LP
        tLP = time()
        solve_master_lp!(masterLP)
        termination_status(masterLP.model) == MOI.OPTIMAL || error("Master LP nao terminou como otimo. Status: $(termination_status(masterLP.model))")
        LPAtual = objective_value(masterLP.model)
        pi, alpha = get_master_lp_duals(masterLP)
        print_master_lp_status(LPAtual,time()-tLP)

        # Master IP / UB only periodically
        if iteracao == 1 || iteracao % ipEvery == 0
            tIP = time()
            modelIP, xIP = solve_master_integer(A,Ast,Custos; warmStart=warmStartIP)
            ultimoModelIP = modelIP
            ultimoXIP = xIP

            if has_values(modelIP)
                UBAtual = objective_value(modelIP)
                improved = melhorUB === nothing || UBAtual < melhorUB

                if improved
                    melhorUB = UBAtual
                    melhorSolucao = get_integer_solution(xIP,rotas)
                end

                warmStartIP = get_ip_warm_start(modelIP,xIP)
                print_master_ip_status(UBAtual,time()-tIP; improved=improved)
            else
                println("Master IP | sem solucao | tempo=$(fmt_elapsed(time()-tIP))")
            end
        end

        # Hybrid pricing:
        # FAST finds columns cheaply. EXACT runs only if FAST finds none.
        pricing = solve_all_exact_labelings(V,pi,alpha,data,pricingData,pricingStaticData,max_t,t_descarga,timeWindows,rotas;
            progressEvery=labelingProgressEvery,
            progressSeconds=pricingProgressSeconds,
            minParallel=pricingMinParallel,
            maxParallel=pricingMaxParallel,
            ramLevel1=ramLevel1,
            ramLevel2=ramLevel2,
            ramLevel3=ramLevel3,
            ramLevel4=ramLevel4,
            launchDelay=pricingLaunchDelay,
            heuristicStarts=heuristicStarts,
            exactHeuristicStarts=exactHeuristicStarts,
            fastNodeLimit=fastNodeLimit,
            fastTimeLimit=fastTimeLimit,
            dominanceMaxKeysFast=dominanceMaxKeysFast,
            dominanceMaxKeysExact=dominanceMaxKeysExact,
            compatibilityBoundFast=compatibilityBoundFast,
            compatibilityBoundExact=compatibilityBoundExact,
            pricingFlag=flag,
            forceExact=(flag == 2 || (flag == 1 && exactActivated)))

        if flag == 1 && pricing.used_exact && !exactActivated
            exactActivated = true
            println("Flag 1 ativada | a partir da proxima iteracao o pricing sera EXATO MIN para todos os veiculos.")
        end

        # Always a REAL lower bound. In FAST/flag=-1 early-stop it can be loose
        # because safe relaxed RC lower bounds are used. In EXATO MIN, each term
        # is the exact min(0,RC*_v), so this is the exact corrected CG bound for
        # the current RMP dual solution. At convergence it becomes LB = RMP.
        LBCandidato = LPAtual + sum(pricing.min_reduced_costs)
        melhorLB = max(melhorLB,LBCandidato)

        resultadosNegativos = new_negative_results(pricing.results,rotas)
        tempoAtual = time() - inicioPrograma

        push!(temposBounds,tempoAtual)
        push!(historicoLB,melhorLB)
        push!(historicoUB,melhorUB === nothing ? NaN : melhorUB)

        print_pricing_result(resultadosNegativos,pricing,length(rotas))
        print_bounds(LPAtual,LBCandidato,melhorLB,melhorUB,tempoAtual; lbExact=pricing.lb_is_exact)

        # Convergence is safe only because solve_all_exact_labelings internally
        # launches exact certification whenever FAST finds no negative column.
        if pricing.certified_no_negative
            LBfinal = LPAtual
            melhorLB = max(melhorLB,LBfinal)

            tIP = time()
            modelIP, xIP = solve_master_integer(A,Ast,Custos; warmStart=warmStartIP)
            ultimoModelIP = modelIP
            ultimoXIP = xIP

            if has_values(modelIP)
                UBAtual = objective_value(modelIP)
                improved = melhorUB === nothing || UBAtual < melhorUB

                if improved
                    melhorUB = UBAtual
                    melhorSolucao = get_integer_solution(xIP,rotas)
                end

                print_master_ip_status(UBAtual,time()-tIP; improved=improved)
            end

            tempoFinal = time() - inicioPrograma
            push!(temposBounds,tempoFinal)
            push!(historicoLB,melhorLB)
            push!(historicoUB,melhorUB === nothing ? NaN : melhorUB)

            print_final_summary(LBfinal,melhorUB,tempoFinal,length(rotas),iteracao)

            if melhorSolucao !== nothing
                println("Solucao inteira:")
                for sol in melhorSolucao
                    println("  v=$(sol.veiculo) | rota=$(sol.rota_index) | $(sol.rota)")
                end
            end

            p = plot_bounds_by_time(temposBounds,historicoLB,historicoUB)

            return (
                A=A,
                Ast=Ast,
                Custos=Custos,
                rotas=rotas,
                lower_bound=LBfinal,
                best_lower_bound=melhorLB,
                upper_bound=melhorUB,
                gap=melhorUB === nothing ? nothing : calculate_gap(LBfinal,melhorUB),
                solution=melhorSolucao,
                lp_model=masterLP.model,
                integer_model=ultimoModelIP,
                integer_x=ultimoXIP,
                bound_times=temposBounds,
                lb_history=historicoLB,
                ub_history=historicoUB,
                plot=p
            )
        end

        isempty(resultadosNegativos) && error("Pricing terminou sem coluna negativa, mas sem certificacao. Isso nao deveria acontecer.")

        A, Ast, Custos = add_new_routes!(masterLP,A,Ast,Custos,rotas,resultadosNegativos,V,data)
        print_routes_added(length(resultadosNegativos),length(rotas))

        iteracao += 1
    end
end


# Optional positional form, if preferred:
# main(200,1,8,1,500,0) is equivalent to main(200,1,8,1,500; flag=0).
function main(i, j, max_t, t_descarga, n_routes, flag; kwargs...)
    return main(i,j,max_t,t_descarga,n_routes; flag=flag,kwargs...)
end
