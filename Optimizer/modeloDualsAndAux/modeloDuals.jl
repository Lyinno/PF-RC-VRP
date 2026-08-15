path = pwd()
include("$(path)/artigo/Optimizer/funcsAux/Greedy/guloso.jl")

function montarModelMatricial(A, custosRota, newTipo, R, V, S_cd, optimizer=Gurobi.Optimizer)
    model = Model(optimizer)
    @variable(model, X[r=(1:length(R)), v=V], Bin)
    @constraint(model, setPartition[s in S_cd], sum(sum(A[r, s] * X[r, v] for r in R) for v in V) == 1)
    @constraint(model, vehicleTypeFixation[r in R, v in V], X[r, v] <= newTipo[r, v])
    @constraint(model, vehicleAssignment[v in V], sum(X[r, v] for r in R) <= 1)
    @objective(model, Min, sum(X .* custosRota))
    return model, X, setPartition, vehicleTypeFixation, vehicleAssignment
end

function montarModelMatricial2(A, custosRota, newTipo, R, V, S_cd, MatrixRC,startSol,optimizer=Gurobi.Optimizer)
    model = Model(optimizer)
    @variable(model, X[r=R, v=V], Bin)
    set_start_value.(X,startSol)
    @constraint(model, setPartition[s in S_cd], sum(sum(A[r, s] * X[r, v] for r in R) for v in V) == 1)
    @constraint(model, RCfixation[r in R, v in V], X[r,v] <= MatrixRC[r,v])
    @constraint(model, vehicleTypeFixation[r in R, v in V], X[r, v] <= newTipo[r, v])
    @constraint(model, vehicleAssignment[v in V], sum(X[r, v] for r in R) <= 1)
    @objective(model, Min, sum(X .* custosRota))
    return model, X, setPartition, vehicleTypeFixation, vehicleAssignment
end

function findSols(rotasFilt, S, custosRota, newTipo, custosDict)
    pesoRotas = Dict()
    for (i,r) in enumerate(rotasFilt)
        pesoRotas[r] = (minimum(custosRota[i,:]))/(length(Set(r)))
    end
    pesoRotasAnt = copy(pesoRotas)
    allSols = []
    rotasTotais = Set()
    veicsTotais = Set()
    rotasIndex = Dict(r=>i for (i,r) in enumerate(rotasFilt))
    count = 1
    while (count <= 500 && length(rotasTotais) <= 500)
        rotasFiltSort = sort(rotasFilt, by=x->pesoRotas[x])
        if (count%10 == 0)
            println("$(100*count/500)%")
        end
        count += 1
        solAtual = Set()
        firstRoute = false
        
        lojasAtendidas = Set([1])
        index = 1
        while lojasAtendidas != Set(S)
            while intersect(lojasAtendidas,rotasFiltSort[index]) != Set([1])
                index += 1
            end
            if firstRoute==false
                firstRoute = rotasFiltSort[index]
            end
            lojasAtendidas = union(lojasAtendidas,Set(rotasFiltSort[index]))
            push!(solAtual, rotasIndex[rotasFiltSort[index]])
        end
        rotasSolAtual = [rotasFilt[i] for i in solAtual]
        sol = hungarianAlgSimples(rotasSolAtual, custosDict)
        if sol[1] == false
            if solAtual in allSols
                for i in solAtual
                    pesoRotasAnt[rotasFilt[i]] *= rotasFilt[i]==firstRoute ? 4 : 2
                end
                pesoRotas = pesoRotasAnt
                firstRoute = false
                continue
            end
            rotasSemVeic = [rotasSolAtual[i] for i in sol[2]]
            for r in rotasSemVeic
                pesoRotas[r] *= 10
            end
            push!(allSols, solAtual)
            continue
        end
        if sol[1] == true
            if solAtual in allSols
                for i in solAtual
                    pesoRotasAnt[rotasFilt[i]] *= rotasFilt[i]==firstRoute ? 3 : 1.5
                end
                pesoRotas = pesoRotasAnt
                firstRoute = false
                continue
            end
            for i in solAtual
                route = rotasFilt[i]
                push!(rotasTotais,rotasIndex[route])
                pesoRotas[route] = sol[3]/length(S)
                pesoRotasAnt[route] = sol[3]/length(S)
                push!(veicsTotais, sol[2][route])
            end
            push!(allSols, solAtual)
            println(sol[3])
        end
    end
    return rotasTotais,veicsTotais
end

            







function findOneSol(rotasFilt, S, custosRota,newTipo, custosDict)
    pesoRotas = Dict()
    rotasIndex = Dict()
    count = 0
    for (i,r) in enumerate(rotasFilt)
        rotasIndex[Set(r)] = i
        pesoRotas[Set(r)] = minimum(custosRota[i,:])/(length(Set(r)))
    end
    rotasFiltSet = [Set(x) for x in rotasFilt]
    rotasFiltSort = sort(rotasFiltSet, by=x->pesoRotas[x])
    rotasSolTotal = Set([])
    veicsTotal = Set([])
    while (count < 500 && length(rotasSolTotal) < 500)    
        rotasEsc = Set([])
        if count%10 == 0
            println("$(count/5)%")
        end
        firstRoute = []
        aux = true
        count+=1
        lojasAtendidas = Set()
        index = 1
        while true
            while intersect(lojasAtendidas, rotasFiltSort[index]) != Set([1]) && !isempty(lojasAtendidas)
                index += 1
            end
            push!(rotasEsc, rotasIndex[rotasFiltSort[index]])
            if aux
                aux = false
                firstRoute = copy(rotasFiltSort[index])
            end
            for s in rotasFiltSort[index]
                push!(lojasAtendidas, s)
            end
            if length(lojasAtendidas) == length(S)
                break
            end
        end
        rotasEscList = [rotasFilt[i] for i in rotasEsc]
        sol = hungarianAlgSimples(rotasEscList, custosDict)
        if sol[1] == false
            println(sol[2])
            rotasSemVeic = [rotasEscList[i] for i in sol[2]]
            rotasFiltSort = attPeso(rotasFiltSort,[rotasFiltSet[ri] for ri in rotasSemVeic])
            continue
        end
        rotasFiltSort = attPeso(rotasFiltSort,[firstRoute])
        for (i,v) in enumerate(rotasEscList)
            push!(rotasSolTotal,v)
            push!(veicsTotal,sol[2][rotasFilt[v]])
        end
    end    
    return rotasSolTotal,veicsTotal
end

function calcDuals(model, X, setPartition, vehicleAssignment)
    undo = relax_integrality(model)

    optimize!(model)


    Zlp = JuMP.objective_value(model)

    RC = reduced_cost.(X)

    π = dual.(setPartition)
    α = dual.(vehicleAssignment)

    undo()

    optimize!(model)

    Zh = JuMP.objective_value(model)

    gap = Zh - Zlp

    XOpt = JuMP.value.(X)

    return model,Zlp,Zh,gap,π,α,RC,XOpt

end

function retornaRC(rota, veic, alpha, pi, custosRota, rotasFilt, newTipo)
    RC = custosRota[rota, veic] - sum([pi[loja] for loja in rotasFilt[rota] if (loja != 1) && (newTipo[rota, veic] == 1)]) - alpha[veic]
    return RC
end

function makeMatrixRC(R,V,pi,alpha,custosRota,rotasFilt,newTipo)
    matrixRC = ones(1:length(rotasFilt),V)
    for r in R
          for v in V
                matrixRC[r,v] = retornaRC(r,v,alpha,pi,custosRota,rotasFilt,newTipo)
          end
    end
    return matrixRC
end

# function modeloDuals(S,R,V,custosRota,rotasFilt,newTipo,custosDict,A,S_cd)
#     (rotasSol, veicsTotais) = findOneSol(rotasFilt,S,custosRota,newTipo,custosDict)
#     for i in R
#         if length(rotasFilt[i]) < 3
#             push!(rotasSol, i)
#         end
#     end
#     veicsTotais = [i for i in veicsTotais]
#     rotasSol = [i for i in rotasSol]
#     rotasSol = vcat(rotasSol, sample(R,max(1,1000-length(rotasSol)),replace=false))
#     rotasDel = Set()
#     rotasUsadas = []
#     XOpt = []
#     matrixRC = zeros(R,V)
#     rotasRodada = []
#     gap = 0
#     countAux = 0
#     sort!(veicsTotais)
#     sort!(rotasSol)
    
#     while true
#         rotasDel = Set()
#         #(model, X, setPartition, vehicleTypeFixation, vehicleAssignment) = (isempty(matrixRC) ? montarModelMatricial(nodes, A[rotasSol,:], custosRota[rotasSol,:], newTipo[rotasSol,:], 1:length(rotasSol), V, S_cd) : montarModelMatricial2(nodes, A[rotasSol,:], custosRota[rotasSol,:], newTipo[rotasSol,:], 1:length(rotasSol), V, S_cd,matrixRC[rotasSol,:]))
#         (model, X, setPartition, vehicleTypeFixation, vehicleAssignment) = montarModelMatricial2(A[rotasSol,:], custosRota[rotasSol,veicsTotais], newTipo[rotasSol,veicsTotais], 1:length(rotasSol), 1:length(veicsTotais), S_cd, ((round.(matrixRC[rotasSol,veicsTotais])).<=(round(gap))))
#         rotasRodada = rotasSol
#         (model,Zlp,Zh,gap,π,α,RC,XOpt) = calcDuals(model,X,setPartition,vehicleAssignment)
#         if countAux < 3
#             gap = 0
#         end
#         α = [(v in veicsTotais ? α[findall(x->x==v, veicsTotais)[1]] : 0) for v in V]
#         matrixRC= makeMatrixRC(R,V,π,α,custosRota,rotasFilt,newTipo)
#         matrixRCGap = (round.(matrixRC)).<=round(gap)
        
#         rotasUsadas = [rotasSol[r] for r in 1:length(rotasSol) if (1 in ((XOpt[r,:]).>0))]
        
#         if (length(findall(x->x<0, matrixRC)) == 0)
#             println("\n\n\n\n\n\ngap = $gap; len RU = $(length(rotasUsadas)); len RS = $(length(rotasSol)); len RF = $(length(setdiff(R,rotasDel)))\n\n\n\n\n\n")
#             break
#         end

#         for r in R
#             if !(1 in matrixRCGap[r,:])
#                 push!(rotasDel,r)
#             end
#         end

#         veicsTotais = []

#         for v in V
#             if 1 in matrixRCGap[:,v]
#                 push!(veicsTotais,v)
#             end
#         end

#         if length(rotasDel) == length(R)
#             rotasDel = sample(R,10000,replace=false)
#         end

#         for (i,r) in enumerate(rotasSol)
#             v = findall(x->x==1,[j for j in XOpt[i,:]])
#             if !(isempty(v))
#                 matrixRC[r,v[1]] = round(gap-10)
#             end
#         end

#         rotasSol = rotasUsadas
#         minimumRC = minimum(matrixRC)
#         maximumRC = gap

#         f(x) = (x < 0 ? -x : (countAux < 3 ? 1/(x+1) : (x > gap ? 0 : 1/(x+1))))
#         wghts = f.([minimum(matrixRC[i,:]) for i in setdiff(R,rotasDel)])
#         rotasSol = vcat(rotasSol,sample(setdiff(R,rotasDel),Weights(wghts), min(500-length(rotasSol),length(setdiff(R,rotasDel))),replace=false))

#         println("\n\n\n\n\n\ngap = $gap; len RU = $(length(rotasUsadas)); len RS = $(length(rotasSol)); len RF = $(length(setdiff(R,rotasDel)))\n\n\n\n\n\n")
#         countAux += 1
#     end
#     return (rotasRodada, XOpt)
# end




function modeloDuals(S,R,V,custosRota,rotasFilt,newTipo,custosDict,A,S_cd)
    dictLojaRota = Dict(s=>[r for r in R if A[r,s] == 1] for s in S)
    (rotasSol, veicsTotais) = findSols(rotasFilt,S,custosRota,newTipo,custosDict)
    #for i in R
    #    if length(rotasFilt[i]) < 3
    #        push!(rotasSol, i)
    #    end
    #end

    #veicsTotais = V

    #rotasSol = union(rotasSol, Set(sample(R,max(1,500-length(rotasSol)),replace=false)))
    rotasRodada = 0
    countAux = 0
    rotasSol = sort!([r for r in rotasSol])
    veicsTotais = sort!([v for v in veicsTotais])

    (model, X, setPartition, vehicleTypeFixation, vehicleAssignment) = (0,0,0,0,0)
    (model,Zlp,Zh,gap,π,α,RC,XOpt) = (0,0,0,0,0,0,0,0)
    matrixRC = 0
    startSol = zeros(R,V)
    # boolAux = false
    #wghts = ones(R)
    countRoutes = ones(R)

    solutionAtual = 0
    solutionAnt = 0
    a = 700
    b = 300
    countRep = 0
    countRotasExtrasDel = 0
    listaRCIte = zeros(R,V)
    listaExclAcu = []
    while true
        solutionAnt = solutionAtual
        vRoutesDisp = copy(R)
        iRoutesDel = 0

        if countAux == 0
            (model, X, setPartition, vehicleTypeFixation, vehicleAssignment) = montarModelMatricial(A[rotasSol,:], custosRota[rotasSol,veicsTotais], newTipo[rotasSol,veicsTotais], 1:length(rotasSol), 1:length(veicsTotais), S_cd, HiGHS.Optimizer)
            (model,Zlp,Zh,gap,π,α,RC,XOpt) = calcDuals(model,X,setPartition,vehicleAssignment)
        else
            (model, X, setPartition, vehicleTypeFixation, vehicleAssignment) = montarModelMatricial2(A[rotasSol,:], custosRota[rotasSol,veicsTotais], newTipo[rotasSol,veicsTotais], 1:length(rotasSol), 1:length(veicsTotais), S_cd, ((round.(matrixRC[rotasSol,veicsTotais])).<=(round(gap))), startSol, HiGHS.Optimizer)
            (model,Zlp,Zh,gap,π,α,RC,XOpt) = calcDuals(model,X,setPartition,vehicleAssignment)
        end

        nodesUsados = [(rotasSol[r],veicsTotais[v]) for r in 1:length(rotasSol), v in 1:length(veicsTotais) if (XOpt[r,v] > 0.1)]

        # if(round(gap) == 0)
        #     boolAux = true
        #     gap -= countAux^2
        # end

        auxAlpha = zeros(V)
        for (i,v) in enumerate(veicsTotais)
            auxAlpha[v] = α[i]
        end
        α = auxAlpha

        matrixRC = makeMatrixRC(R,V,π,α,custosRota,rotasFilt,newTipo)

        solutionAtual = sum(XOpt.*custosRota[rotasSol,veicsTotais])
        if (abs(round(solutionAtual-solutionAnt)) <= 1)
            countRep += 1
            listaRCIte .+= matrixRC
            matrixRCAux = listaRCIte./countRep
            countRotasExtrasDel = sum(matrixRCAux.>=gap) - sum(matrixRC.>=gap)
            matrixRC = matrixRCAux
            if countRep%15==0
                listaExclAcu = []
            end
            if a + b < 1401
                a = round(Int,1.1*a)
                b = round(Int,1.2*b)
            end
            if countRep > 5
                for r in setdiff(R,listaExclAcu)
                    if minimum(matrixRC[r,:]) > gap
                        push!(listaExclAcu,r)
                    end
                end
                for r in listaExclAcu
                    matrixRC[r,:] = ones(V).*(gap+10000)
                end
            end
        else
            listaRCIte = zeros(R,V)
            countRep = 0
            a = 500
            b = 500
            countRotasExtrasDel = 0
            listaExclAcu = []
        end



        #rotasPerS = Set([sort(dictLojaRota[s], by=x->minimum([matrixRC[x,v] for v in V]))[1] for s in S])

        rotasPerS = Set([])

        rotasUsadas = [node[1] for node in nodesUsados]

        veicsUteis = [v for v in V if sum(((matrixRC.*newTipo).<gap)[:,v]) > 0]
        veicsUsados = [node[2] for node in nodesUsados]
        veicsTotais = sort([v for v in Set(vcat(veicsUteis,veicsUsados))])

        α = α[veicsTotais]
        
        # nodesNovos = []

        matrixRCPot = (round.(copy(matrixRC))).<gap
        matrixRCPot = matrixRCPot.*newTipo
        matrixRCPot = matrixRCPot.>0.1
        vRoutesUtility = [maximum(matrixRCPot[r,:]) for r in R]

        matrixRCNeg = (round.(copy(matrixRC))).<0
        matrixRCNeg = matrixRCNeg.*newTipo
        matrixRCNeg = matrixRCNeg.>0.1
        rNeg = sum([maximum(matrixRCNeg[r,:]) for r in R])


        if sum(((copy(matrixRC)).*(newTipo.>0.1)).<0) == 0
            break
        else
            println("\n\n$(100-100*(sum(((copy(matrixRC)).*(newTipo.>0.1)).<0))/(length(R)*length(V)))%\n\n")
        end

        iLenRoutesDispAnt = length(vRoutesDisp)
        vRoutesDisp = [r for r in vRoutesDisp if vRoutesUtility[r] != 0]
        iLenRoutesDispAft = length(vRoutesDisp)
        iRoutesDel += (iLenRoutesDispAnt-iLenRoutesDispAft)

        # for r in R, v in V
        #     if matrixRCPot[r,v] == 1
        #         push!(nodesNovos,(r,v))
        #     end
        # end

        rotasNegPerType = Set([argmin(matrixRC[vRoutesDisp,v]) for v in veicsTotais if minimum(matrixRC[vRoutesDisp,v]) < gap && newTipo[argmin(matrixRC[vRoutesDisp,v]), v] > 0.1])
        # rotasNegPerSDict = Dict()
        # lojasCheck = Set()
        
        # for r in vRoutesDisp
        #     for v in V
        #         for s in rotasFilt[r]
        #             if newTipo[r,v]>0.1
        #                 if (!(s in lojasCheck) || matrixRC[r,v] < rotasNegPerSDict[s][1])
        #                     push!(lojasCheck,s)
        #                     rotasNegPerSDict[s] = (matrixRC[r,v], r)
        #                 end
        #             end
        #         end
        #     end
        # end

        # for s in sort([s for s in lojasCheck])
        #     rotasNegPerS[s] = rotasNegPerSDict[s][2]
        # end

        # rotasNegPerS = [r for r in Set(rotasNegPerS) if r != 0]

        # rotasNegAdd = [r for r in Set(vcat(rotasNegPerS, [r for r in rotasNegPerType]))]
        rotasNegAdd = [r for r in union(Set([r for r in rotasNegPerType]), rotasPerS)]
        rotasNegAdd = round.(Int,rotasNegAdd)



        rotasSol = vcat(rotasUsadas,rotasNegAdd)

        # nodesAdd = sample(1:length(nodesNovos), min(1000, length(nodesNovos)), replace=false)
        # for n in nodesAdd
        #     push!(rotasSol, nodesNovos[n][1])
        #     push!(veicsTotais, nodesNovos[n][2])
        # end
        vRoutesDispNotUsed = setdiff(vRoutesDisp,rotasUsadas)
        #wghtsAux = wghts[vRoutesDispNotUsed]
        vRoutesAdd = sample(vRoutesDispNotUsed,min(round(Int,a),length(vRoutesDispNotUsed)), replace=false)

        newTipoMod = (newTipo.==0).+1000000
        matrixRCWithTipo = matrixRC.*newTipoMod
        sort!(vRoutesDispNotUsed,by=x->minimum(matrixRCWithTipo[x,:]))
        vRoutesDispNotUsed = setdiff(vRoutesDispNotUsed,vRoutesAdd)
        vRoutesAdd = vcat(vRoutesAdd,vRoutesDispNotUsed[1:min(length(vRoutesDispNotUsed), round(Int, b))])

        rotasSol = vcat(rotasSol,vRoutesAdd)

        vRoutesDispNotUsed = setdiff(vRoutesDispNotUsed,rotasSol)
        #rotasSol = length(vRoutesDispNotUsed) > 0 ? vcat(rotasSol,vRoutesDispNotUsed[1:min(round(Int,400+(10+countAux/2)*(countAux^1.2)),length(vRoutesDispNotUsed))]) : rotasSol

        for r in rotasSol
            countRoutes[r] += countAux
        end

        #wghts = wghts./countRoutes

        # if length(vRoutesDisp)-length(rotasSol) > 0
        #     rotasNeg = sort([r for r in vRoutesDisp if !(r in rotasSol)], by=x->minimum(matrixRC[x,:]))[1:min(500,length(vRoutesDisp)-length(rotasSol))]
        #     rotasSol = vcat(rotasSol,rotasNeg)
        # end
        sort!(rotasSol)
        # veicsTotais = sort([v for v in veicsTotais])

        # veicsTotais = V

        println("\ngapMod=$(gap)\n")

        # if boolAux
        #     gap += countAux^2
        #     boolAux = false
        # end
        startSol = zeros(length(rotasSol), length(veicsTotais))
        nodesUsados = [(findall(x->x==nod[1], rotasSol)[1], findall(x->x==nod[2], veicsTotais)[1]) for nod in nodesUsados]
        for nod in nodesUsados
            startSol[nod[1], nod[2]] = 1
            matrixRC[rotasSol[nod[1]], veicsTotais[nod[2]]] = gap-1
        end


        countAux += 1
        println("\n\n\n\n")
        println("gap=$gap qtdNodesNeg=$(sum(matrixRCNeg)) Rdel=$(iRoutesDel) R=$(length(R)) V=$(length(veicsTotais)) qtdRotaNeg=$(rNeg)")
        println("\n")
        println("rotasDisponiveis=$(length(vRoutesDisp)) lenRotasSol=$(length(rotasSol)) rodada=$(countAux) rotasExtDel=$(countRotasExtrasDel)")
        println("\n\n\n\n")
    end
    return (rotasRodada, XOpt)
end
