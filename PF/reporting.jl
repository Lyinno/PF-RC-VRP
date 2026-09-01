using Plots

function fmt_obj(x)
    x === nothing && return "--"
    return string(round(x,digits=4))
end

function fmt_elapsed(x)
    x < 60 && return "$(round(x,digits=1))s"
    m = floor(Int,x/60)
    s = floor(Int,x - 60m)
    return "$(m)m$(lpad(s,2,'0'))s"
end

function print_iteration_header(iteracao, nRotas)
    println("\n================ ITERACAO $iteracao | rotas=$nRotas ================")
end

function print_master_lp_status(obj, elapsed)
    println("Master LP | obj=$(fmt_obj(obj)) | tempo=$(fmt_elapsed(elapsed))")
end

function print_master_ip_status(obj, elapsed; improved=false)
    suffix = improved ? " | NOVO UB" : ""
    println("Master IP | obj=$(fmt_obj(obj)) | tempo=$(fmt_elapsed(elapsed))$suffix")
end

function print_bounds(LPAtual, LBCandidato, melhorLB, melhorUB, tempoAtual; lbExact=false)
    lbLabel = lbExact ? "LB exato" : "LB seguro"

    if melhorUB === nothing
        println("Bounds | RMP=$(fmt_obj(LPAtual)) | $lbLabel=$(fmt_obj(LBCandidato)) | melhorLB=$(fmt_obj(melhorLB)) | UB=-- | gap=-- | total=$(fmt_elapsed(tempoAtual))")
    else
        gapAtual = calculate_gap(melhorLB,melhorUB)
        println("Bounds | RMP=$(fmt_obj(LPAtual)) | $lbLabel=$(fmt_obj(LBCandidato)) | melhorLB=$(fmt_obj(melhorLB)) | UB=$(fmt_obj(melhorUB)) | gap=$(round(gapAtual,digits=4))% | total=$(fmt_elapsed(tempoAtual))")
    end
end

function print_pricing_result(resultadosNegativos, pricing, nRotasAntes)
    if isempty(resultadosNegativos)
        println("Pricing | etapa=$(pricing.pricing_stage) | negativas=0 | certificado=$(pricing.certified_no_negative) | tempo=$(fmt_elapsed(pricing.elapsed))")
        return
    end

    melhor = first(sort(copy(resultadosNegativos),by=r -> r.reduced_cost))
    println("Pricing | etapa=$(pricing.pricing_stage) | negativas=$(length(resultadosNegativos)) | melhorRC=$(round(melhor.reduced_cost,digits=4)) | v=$(melhor.veiculo) | tempo=$(fmt_elapsed(pricing.elapsed))")
end

function print_routes_added(nAdded, poolSize)
    println("Colunas | adicionadas=$nAdded | pool=$poolSize")
end

function print_final_summary(LBfinal, melhorUB, tempoFinal, nRotas, iteracao)
    println("\n================ CONCLUIDO ================")
    if melhorUB === nothing
        println("LP completo | LB=$(fmt_obj(LBfinal)) | UB=-- | gap=--")
    else
        println("LP completo | LB=$(fmt_obj(LBfinal)) | UB=$(fmt_obj(melhorUB)) | gap=$(round(calculate_gap(LBfinal,melhorUB),digits=4))%")
    end
    println("Execucao | tempo=$(fmt_elapsed(tempoFinal)) | iteracoes=$iteracao | rotas=$nRotas")
end

function plot_bounds_by_time(times, lbs, ubs)
    p = plot(xlabel="Tempo de execucao (s)", ylabel="Valor objetivo", title="Evolucao de LB e UB por tempo")

    validLB = [i for i in eachindex(times) if isfinite(lbs[i])]
    !isempty(validLB) && plot!(p,times[validLB],lbs[validLB],label="LB",marker=:circle)

    validUB = [i for i in eachindex(times) if isfinite(ubs[i])]
    !isempty(validUB) && plot!(p,times[validUB],ubs[validUB],label="UB",marker=:circle)

    display(p)
    return p
end
