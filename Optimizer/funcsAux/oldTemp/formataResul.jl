using Hungarian


function convertTimeResult(A, XOpt, nLojas, nVeic, V, S, td, te, tempoCarga, rotaDados, rotasFilt)
    ChOpt = zeros(nLojas, nVeic, 2)
    saidaCDOpt = zeros(nVeic, 2)

    AXOpt = (A') * XOpt

    for v in V
        for s in S
            if (AXOpt[s, v] == 1)
                rota = rotasFilt[findall(x -> (x == 1.0), vcat(XOpt[:, v]...))[1]]
                indexCDRota = findall(x -> x == 1.0, rota)
                qtdJornadas = length(indexCDRota)
                jornadas = []
                if qtdJornadas == 2
                    rota1 = rota[1:indexCDRota[1]]
                    rota2 = rota[(indexCDRota[1]+1):end]
                    jornadas = [(rota1, 0), (rota2, tempoCarga[rota2[1]])]
                else
                    jornadas = [(rota, 0)]
                end
                for (i, r) in enumerate(jornadas)
                    horaSaidaCD = rotaDados[rota][end-4]
                    if i == 2
                        horaSaidaCD += rotaDados[r[1]][1] + tempoCarga[r[1][1]]
                    end
                    saidaCDOpt[v, i] = horaSaidaCD
                    for (index1, loja) in enumerate(r[1])
                        horaSaidaCD = horaSaidaCD + (index1 == 1 ? td[1, r[1][1]] : td[r[1][index1-1], r[1][index1]] + te[r[1][index1-1]])
                        ChOpt[loja, v, i] = horaSaidaCD
                    end
                end
                break
            end
        end
    end
    return (ChOpt, saidaCDOpt)
end

function getSelectedRoutes(XOpt, rotas)
    selectedRoutes = []
    dicRouteVeic = Dict()
    for r in 1:length(rotas)
        for v in V
            if XOpt[r,v] == 1
                push!(selectedRoutes, rotas[r])
                dicRouteVeic[rotas[r]] = v
            end
        end
    end
    return selectedRoutes, dicRouteVeic
end

function makeChOptSaidaCDOpt(rotas, td, nLojas, nVeic, dictRotas, rotaDados, ti, te)
    CHOpt = zeros(nLojas, nVeic, 2)
    SaidaCDOpt = zeros(nVeic, 2)
    for r in rotas
        veic = dictRotas[r]
        SaidaCDOpt[veic,1] = rotaDados[r][end-4]
        aux = 1
        hora = SaidaCDOpt[veic,1]
        for (i,s) in enumerate(r)
            jornada = (length(findall(x -> x == 1, r)) == 1 ? 1 : 3 - length(findall(x -> x == 1, r[i:end])))
            if ((jornada == 2) && (aux == 1))
                secondRoute = r[i:end]
                SaidaCDOpt[veic,2] = rotaDados[secondRoute][end-2]
                hora = SaidaCDOpt[veic,2]
                CHOpt[s,veic,2] = max(hora+td[1,s],ti[s])
                hora = CHOpt[s,veic,2] + te[s]
                aux = 0
                continue
            end
            if i == 1
                CHOpt[s,veic,1] = max(hora+td[1,s],ti[s])
                hora = CHOpt[s,veic,1] + te[s]
            else
                CHOpt[s,veic,jornada] = max(hora+td[r[i-1],s],ti[s])
                hora = CHOpt[s,veic,jornada] + te[s]
            end
        end
    end
    return (CHOpt,SaidaCDOpt)
end 

function makeAOpt(nLojas, nVeic, nodes, rotasFilt)
    AOpt = zeros(nLojas, nLojas, nVeic, 2)
    for (r, v) in nodes
        if XOpt[r, v] == 1
            rota = rotasFilt[r]
            for (i, s) in enumerate(rota)
                jornada = (length(findall(x -> x == 1, rota)) == 1 ? 1 : 3 - length(findall(x -> x == 1, rota[i:end])))
                if i == 1
                    AOpt[1, s, v, jornada] = 1
                else
                    AOpt[rota[i-1], s, v, jornada] = 1
                end
            end
        end
    end
    return AOpt
end

function showRoutes(AOpt)
    for v in V
        println("\nVeículo $v ---------------------------")
        for r in 1:2
            println("\nRota $r:\n")
            for s in S
                for l in S
                    if AOpt[s,l,v,r] == 1
                        print("$s -> $l | ")
                    end
                end
            end
            println("\n")
        end
    end
end

function timeWindow(hrIni, ti, tf, td, te, rota, tempoMaxMotor)
    rotaAux = vcat([1], rota)
    if rotaAux[end] != 1
        push!(rotaAux, 1)
    end
    horaFim = hrIni
    for (i,s) in enumerate(rotaAux[1:end-1])
        horaFim += te[s]
        sSeg = rotaAux[i+1]
        horaFim += td[s,sSeg]
        if horaFim > tf[sSeg]
            return false
        end
        horaFim = max(horaFim, ti[sSeg])
        if horaFim - hrIni > tempoMaxMotor
            return -1
        end
    end
    return horaFim
end

function horaMinMax(ti, tf, rota, td, te, tempoMaxMotor)
    if (length(rota) == 2) && (rota[end] == 1)
        firstS = rota[1]
        tdCDS = td[1, firstS]
        hrIMin = ti[firstS] - tdCDS
        hrIMax = tf[firstS] - tdCDS
        tdSCD = td[firstS,1]
        hrFMin = hrIMin + tdCDS + te[firstS] + tdSCD
        hrFMax = hrIMax + tdCDS + te[firstS] + tdSCD  
        return (hrIMin, hrIMax, hrFMin, hrFMax)
    end
    hrIMin = 1000
    hrIMax = -1000
    hrFMin = 1000
    hrFMax = -1000
    aux = false
    firstS = rota[1]
    secondS = rota[2]
    ini = ti[firstS] - td[1,firstS]
    fim = min(tf[firstS], tf[secondS]-td[firstS,secondS])
    if ini > fim
        return false
    end
    for hrIni in ini:0.01:fim
        hrFim = timeWindow(hrIni, ti, tf, td, te, rota, tempoMaxMotor)
        if hrFim == -1
            continue
        elseif hrFim == false
            break
        end
        if hrIni <= hrIMin
            hrIMin = hrIni
            hrFMin = hrFim
            aux = true
        end
        if hrIni >= hrIMax
            hrIMax = hrIni
            hrFMax = hrFim
        end
    end
    if aux == false
        return false
    else
        return (hrIMin, hrIMax, hrFMin, hrFMax)
    end
end




function computaPesoRota(rotas, S, custosDict) 
    pesoRota = Dict()
    for r in rotas
        #pesoRota[r] = length(intersect(Set(r),S))/custosDict[r][1][1]
        pesoRota[r] = custosDict[r][1][1]/length(intersect(Set(r),S))
        pesoRota[r] *= (1 + 0.5/length(custosDict[r]))
    end
    return pesoRota
end


function chooseVeic2(solucao, custosDict, nBuscasVeic)
    achouSol = false
    contador = 0
    pesoRotaVeic = Dict()
    for r in solucao
        pesoRotaVeic[r] = custosDict[r][1][1]/length(custosDict[r])
    end
    sol = Dict()
    auxSemSol = Dict()
    rotaSemVeic = []
    
    while ((achouSol == false) && (contador <= nBuscasVeic))
        contador += 1
        veicUtil = Set()
        sol = Dict()
        auxSemSol = Dict()
        rotas = sort!(solucao, by = x->pesoRotaVeic[x], rev=true)
        for r in rotas
            aux = false
            for tup in custosDict[r] 
                veic = tup[2]
                if !(veic in veicUtil)
                    aux = true
                    push!(veicUtil,veic)
                    sol[r] = veic
                    auxSemSol[veic] = r
                    break
                end
            end
            if aux == false
                pesoRotaVeic[r] = pesoRotaVeic[r]*1.5
                rotaSemVeic = r
                break
            end
            if r == rotas[end]
                achouSol = true
            end
        end
    end
    if achouSol == true
        return (true, sol)
    else
        rotaSemVeicAux = []
        push!(rotaSemVeicAux, rotaSemVeic)
        for veic in [tup[2] for tup in custosDict[rotaSemVeic]]
            push!(rotaSemVeicAux, auxSemSol[veic])
        end
        return (false, rotaSemVeicAux)
    end
end


function hungarianAlg(routes, custosDict, mod)
    nodes = Dict()
    veics = Set()
    custosDict = copy(custosDict)

    if mod == true
        for k in keys(custosDict)
            for tup in custosDict[k]
                tup = (tup[1]/length(Set(k)), tup[2])
            end
        end
    end

    for (i,r) in enumerate(routes)
        for tup in custosDict[r]
            push!(veics, tup[2])
            nodes[(i,veics)] = tup[1]
        end
    end

    lenV = maximum(veics)

    matrixHung = Matrix{Union{Missing,Float64}}(missing,length(routes),lenV)
    for (i,r) in enumerate(routes)
        for tup in custosDict[r]
            matrixHung[i,tup[2]] = tup[1]
        end
    end

    ass, val = hungarian(matrixHung)
    if 0 in ass
        if mod == true
            return (false,[r for (i,r) in enumerate(routes) if ass[i]==0])
        else
            return hungarianAlg(copy(routes), custosDict, true)
        end
    else
        sol = Dict()
        for (i,s) in enumerate(ass)
            sol[routes[i]] = s
        end
        return (true, sol)
    end
end

function hungarianAlgSimples(routes, custosDict)
    nodes = Dict()
    veics = Set()
    custosDict = copy(custosDict)

    for (i,r) in enumerate(routes)
        for tup in custosDict[r]
            push!(veics, tup[2])
            nodes[(i,veics)] = tup[1]
        end
    end

    lenV = maximum(veics)

    matrixHung = Matrix{Union{Missing,Float64}}(missing,length(routes),lenV)
    for (i,r) in enumerate(routes)
        for tup in custosDict[r]
            matrixHung[i,tup[2]] = tup[1]
        end
    end

    ass, val = hungarian(matrixHung)
    if 0 in ass
        return (false, findall(x->x<1,ass))
    else
        sol = Dict()
        for (i,s) in enumerate(ass)
            sol[routes[i]] = s
        end
        return (true, sol, val)
    end
end


function greed6(rotas, S, custosDict, nBuscasRota, nBuscasVeic, custosRotaDictAux, modSemSol, hungarMode)
    pesoRota = computaPesoRota(rotas, setdiff(S,[1]), custosDict)
    pesoRotaAux = copy(pesoRota)
    pesoRotaOri = copy(pesoRota)
    sSet = Set(S)
    setAux = Set([1])
    bestSol = []
    allSol = Vector{Vector{Vector{Int64}}}(undef,0)  
    gen = 1
    nLojas = length(S)-1
    len = length(S)

    while gen <= nBuscasRota
        gen += 1
        actualSol = Vector{Vector{Int64}}(undef,0) 
        lojasAtendidas = Set([1])
        rotasSorted = sort(rotas, by = x->pesoRotaAux[x])
        rotaEscInd = 1
        firstRoute = rotasSorted[rotaEscInd]
        rotaEscInd += 1
        push!(actualSol, firstRoute)
        union!(lojasAtendidas, Set(firstRoute))
        rotasSorted = sort(rotas, by = x->pesoRota[x])
        while lojasAtendidas != sSet
            while intersect(Set(rotasSorted[rotaEscInd]),lojasAtendidas) != setAux
                rotaEscInd += 1
            end
            rotaEscolhida = rotasSorted[rotaEscInd]
            push!(actualSol,rotaEscolhida)
            union!(lojasAtendidas, Set(rotaEscolhida))
            #rotasSorted = [r for r in rotasSorted if intersect(Set(r),lojasAtendidas) == setAux]
        end
        #(achouSol, solVeic) = chooseVeic2(copy(actualSol),copy(custosDict),nBuscasVeic)
        #(achouSol, solVeic) = hungarianAlg(copy(actualSol),copy(custosDict),false)
        if actualSol in allSol
            #nLojas = length(S)
            #for r in actualSol
            #    pesoRota[r] *= (1 + modSolRep/nLojas)
            #    nLojas = length(setdiff(sSet, Set(r)))
            #end
            pesoRotaAux[actualSol[1]] *= 10
            pesoRota = copy(pesoRotaOri)
            println("Sol repetida, $(actualSol[1])")
        else
            (achouSol, solVeic) = (0,0)
            if hungarMode == true
                (achouSol, solVeic) = hungarianAlg(copy(actualSol),copy(custosDict),false)
            else
                (achouSol, solVeic) = chooseVeic2(copy(actualSol),copy(custosDict),nBuscasVeic)
            end    
            push!(allSol, actualSol)
            if achouSol == false
                #worstRoute = argmin(x->length(x), solVeic)
                #pesoRota[worstRoute] *= modSemSol
                #println("Sem Sol, $worstRoute")
                if hungarMode == true
                    for route in solVeic
                        pesoRota[route] *= modSemSol
                    end
                else
                    pesoRota[solVeic[1]] *= modSemSol
                end
                println("Sem Sol, $solVeic")
            else
                custoSol = sum([custosRotaDictAux[r][solVeic[r]] for r in actualSol])
                nLojas = len
                pesoRotaAux[actualSol[1]] = custoSol/nLojas
                nLojas -= (length(Set(actualSol[1])) - 1)
                for r in actualSol
                    pesoRota[r] = (pesoRota[r] + custoSol/nLojas)/2
                    nLojas -= (length(Set(r)) - 1)
                end
                pesoRota = pesoRotaAux
                if isempty(bestSol) || custoSol < bestSol[2]
                    bestSol = [actualSol,custoSol,solVeic]
                    println("bestSol: $custoSol")
                else
                    println("Other sol: $custoSol")
                end
            end
        end 
    end        
    return bestSol
end 

function greedShippuden(rotas, S, custosDict, nBuscasRota, nBuscasVeic, custosRotaDictAux, modSemSol, hungarMode, nFirsts, alpha, modSolRep)
    pesoRota = computaPesoRota(rotas, setdiff(S,[1]), custosDict)
    sSet = Set(S)
    setAux = Set([1])
    bestSol = []
    gen = 1
    nLojas = length(S)-1
    allSol = []
    while gen <= nBuscasRota
        pesoRotaSum = Dict()
        gen += 1
        rotasSorted = sort(rotas, by = x->pesoRota[x])
        for firstRoute in rotasSorted[1:nFirsts]
            lojasAtendidas = Set([1])
            actualSol = Vector{Vector{Int64}}(undef,0) 

            rotaEscInd = 1
            push!(actualSol, firstRoute)
            union!(lojasAtendidas, Set(firstRoute))

            while lojasAtendidas != sSet
                while intersect(Set(rotasSorted[rotaEscInd]),lojasAtendidas) != setAux
                    rotaEscInd += 1
                end
                rotaEscolhida = rotasSorted[rotaEscInd]
                push!(actualSol,rotaEscolhida)
                union!(lojasAtendidas, Set(rotaEscolhida))
                #rotasSorted = [r for r in rotasSorted if intersect(Set(r),lojasAtendidas) == setAux]
            end
            #(achouSol, solVeic) = chooseVeic2(copy(actualSol),copy(custosDict),nBuscasVeic)
            #(achouSol, solVeic) = hungarianAlg(copy(actualSol),copy(custosDict),false)
            if actualSol in allSol
                for r in actualSol[1]
                    if haskey(pesoRotaSum,r)
                        push!(pesoRotaSum[r], pesoRota[r]*modSolRep)
                    else
                        pesoRotaSum[r] = [pesoRota[r]*modSolRep]
                    end
                end
                ##nLojas = length(S)
                ##for r in actualSol
                ##    pesoRota[r] *= (1 + modSolRep/nLojas)
                ##    nLojas = length(setdiff(sSet, Set(r)))
                ##end
                #pesoRotaAux[actualSol[1]] *= 10
                #pesoRota = copy(pesoRotaOri)
                println("Sol repetida, $(actualSol[1])")
            else
                push!(allSol, actualSol)
                (achouSol, solVeic) = (0,0)
                if hungarMode == true
                    (achouSol, solVeic) = hungarianAlg(copy(actualSol),copy(custosDict),false)
                else
                    (achouSol, solVeic) = chooseVeic2(copy(actualSol),copy(custosDict),nBuscasVeic)
                end    
                if achouSol == false
                    #worstRoute = argmin(x->length(x), solVeic)
                    #pesoRota[worstRoute] *= modSemSol
                    #println("Sem Sol, $worstRoute")
                    if hungarMode == true
                        for route in solVeic
                            if haskey(pesoRotaSum,route)
                                push!(pesoRotaSum[route], pesoRota[route]*modSemSol)
                            else
                                pesoRotaSum[route] = [pesoRota[route]*modSemSol]
                            end 
                        end
                    else
                        worstRoute = solVeic[1]
                        if haskey(pesoRotaSum,worstRoute)
                            push!(pesoRotaSum[worstRoute], pesoRota[worstRoute]*modSemSol)
                        else
                            pesoRotaSum[worstRoute] = [pesoRota[worstRoute]*modSemSol]
                        end
                    end
                    println("Sem Sol, $solVeic,    $(actualSol[1])")
                else
                    custoSol = sum([custosRotaDictAux[r][solVeic[r]] for r in actualSol])
                    for r in actualSol
                        if haskey(pesoRotaSum,r)
                            push!(pesoRotaSum[r], custoSol/nLojas)
                        else
                            pesoRotaSum[r] = [custoSol/nLojas]
                        end
                    end
                    if isempty(bestSol) || custoSol < bestSol[2]
                        bestSol = [actualSol,custoSol,solVeic]
                        println("bestSol: $custoSol")
                    else
                        println("Other sol: $custoSol")
                    end
                end
            end
        end
        for route in keys(pesoRotaSum)
            pesoRota[route] = alpha*pesoRota[route] + (1-alpha)*(sum(pesoRotaSum[route])/length(pesoRotaSum[route]))
        end
    end        
    return bestSol
end 

