path = pwd()

include("$(path)/artigo/Optimizer/funcsAux/preProcess/preProcess.jl")
include("$(path)/artigo/Optimizer/funcsAux/Greedy/guloso.jl")


function fixaLojas(idLoja, idCaminhao, S, V, dv, dp, rl, rv, cv, cvOriginal, cp, val, lt, ti, tf, te, td, tipo)
    nodesFix = []
    dictNode = Dict()
    STemp = copy(S)
    VTemp = copy(V)
    for s in S
        v = findall(v->tipo[s,v]==1,V)
        if length(v) == 1
            push!(nodesFix, (s,v[1]))
        end
    end
    
    for node in nodesFix
        s = node[1]
        v = node[2]
        dictNode[node] = (idLoja[s], idCaminhao[v], dv[s], dp[s], rl[s,:], rv[v,:], cv[v], cvOriginal[v], cp[v], val[s,v],lt[s],ti[s],tf[s],te[s],td[s,:],td[:,s])
        setdiff(STemp,s)
        setdiff(VTemp,v)
    end
    S = STemp
    V = VTemp

    return idLoja[S], idCaminhao[V], dv[S], dp[S], rl[S,:], rv[V,:], cv[V], cvOriginal[V], cp[V], val[S,V],lt[S], ti[S], tf[S], te[S], td[S,S], S, V, nodesFix, dictNode
end

function makeArcos(S, S_cd, V, dv, dp, rl, cv, cp, ti, tf, te, td, tipo, tempoMaxMotor)
    listHeu, H = makeHeuA(S_cd, td, dv, dp, rl, tf, ti, te)

    setdiff([[i, j] for i in S for j in S], listHeu)


    arcos = arcosPermitidos(S, te, ti, td, dp, rl, cp, cv, tipo, V, tf, tempoMaxMotor, dv)


    adjAntes = Dict()
    adjDepois = Dict()

    for arco in arcos
        primeiraLoja = arco[1]
        segundaLoja = arco[2]
        if !(primeiraLoja in keys(adjDepois))
            adjDepois[primeiraLoja] = []
        end
        push!(adjDepois[primeiraLoja], segundaLoja)
        if !(segundaLoja in keys(adjAntes))
            adjAntes[segundaLoja] = []
        end
        push!(adjAntes[segundaLoja], primeiraLoja)

    end
    return adjDepois, arcos
end

function validaRota(rota, td, ti, tf, te, cp, cv, V, tempoMaxMotor, dp, dv, tipo)
    tempoTotal = 0
    pesoDemanda = 0
    volDemanda = 0
    lenRota = length(rota)

    pesoDemanda = sum([dp[s] for s in rota])
    volDemanda = sum([dv[s] for s in rota])

    temIntersecao = []
    temCapacidade = false
    veicVal = []
    for v in V
        if (sum(tipo[rota, :][:, v]) == lenRota)
            if cp[v] >= pesoDemanda && cv[v] >= volDemanda
                temCapacidade = true
                push!(temIntersecao, true)
                push!(veicVal, v)
            else
                push!(temIntersecao, false)
            end
        else
            push!(temIntersecao, false)
        end
    end
    horaIniMin = 0
    horaFimMin = 0
    horaIniMax = 0
    horaFimMax = 0
    aux = horaMinMax(ti, tf, rota, td, te, tempoMaxMotor)
    if aux != false
        (horaIniMin, horaIniMax, horaFimMin, horaFimMax) = aux
    else
        return (false, false)
    end
    tempoTotal = max(horaFimMax - horaIniMax, horaFimMin - horaIniMin)

    RotaValida = (temCapacidade && (any(temIntersecao))) #&& (horaIniMin > ti[rota[1]]) && (horaIniMin < tf[rota[1]]))
    dados = [tempoTotal, pesoDemanda, volDemanda, temIntersecao, horaIniMin, horaFimMax, horaIniMax, horaFimMin, veicVal]
    return (RotaValida, dados)
end

function enumerar(adjDepois, componentePeq, td, ti, tf, te, cp, cv, V, tempoMaxMotor, dp, dv, tipo, tamRota=15)
    rotaDados = Dict()
    rotas = [[loja] for loja in componentePeq]
    rotasAnteriores = copy(rotas)
    for len in 2:tamRota #2:length(componentePeq)
        novasRotas = []
        for rota in rotasAnteriores
            if rota[end] != 1
                for lojaSaindo in adjDepois[rota[end]]
                    if !(lojaSaindo in rota)
                        novaRota = copy(rota)
                        push!(novaRota, lojaSaindo)
                        (rotaValida, dados) = validaRota(novaRota, td, ti, tf, te, cp, cv, V, tempoMaxMotor, dp, dv, tipo)
                        if rotaValida
                            rotaDados[novaRota] = dados
                            push!(novasRotas, novaRota)
                        end
                    end
                end
            end
        end
        rotasAnteriores = copy(novasRotas)
        rotas = vcat(rotas, novasRotas)
    end
    rotasFilt = [rota for rota in rotas if rota[end] == 1]
    return (rotasFilt, rotaDados)
end

function makeVeicPerRota(rotasFilt, rotaDados)
    veicPerRota = []

    for rota in rotasFilt
        push!(veicPerRota, rotaDados[rota][end])
    end
    return veicPerRota
end

function makeNewTipo(rotasFilt, nVeic, veicPerRota, V)
    newTipo = zeros(length(rotasFilt), nVeic)
    for i in 1:length(rotasFilt)
        for v in V
            if v in veicPerRota[i]
                newTipo[i, v] = 1
            end
        end
    end
    return newTipo
end

function makeCustosRota(rotasFilt, V, val)
    custosRota = zeros((length(rotasFilt), V))
    for r in 1:length(rotasFilt)
        for v in V
            custosRota[r, v] = maximum([val[s, v] for s in rotasFilt[r]])
        end
    end
    return custosRota
end

function validaConcat(primeRota, secondRota, rotaDados, tempoCarga, rotasFiltSet, r, lenRotas1F, r2, custosRota, lenRotas2F, V)

    dadosSecondRota = rotaDados[secondRota]
    dadosPrimeRota = rotaDados[primeRota]
    horaFimMinPrimeRota = dadosPrimeRota[end-1]

    horaIniMaxSecondRota = dadosSecondRota[end-2]

    if !(horaIniMaxSecondRota - horaFimMinPrimeRota > tempoCarga[secondRota[1]])
        return (false, false, false, false)
    end

    veicValr1 = dadosPrimeRota[end]
    veicValr2 = dadosSecondRota[end]
    veicAceBoth = intersect(Set(veicValr1), Set(veicValr2))

    if isempty(veicAceBoth)
        return (false, false, false, false)
    end


    if (intersect(Set(primeRota), Set(secondRota)) != Set([1]))
        return (false, false, false, false)
    end

    teste = Set(vcat(primeRota, secondRota))

    if teste in rotasFiltSet
        return (false, false, false, false)
    end
    peso = [dadosPrimeRota[2], dadosSecondRota[2]]
    peso = vcat(peso...)
    vol = [dadosPrimeRota[3], dadosSecondRota[3]]
    vol = vcat(vol...)
    newRowNewTipo = [i in veicAceBoth ? 1 : 0 for i in V]
    dadosNewRotaCon = [0, peso, vol, [true], dadosPrimeRota[5], dadosSecondRota[6], dadosPrimeRota[end-2], dadosSecondRota[end-1], veicAceBoth]
    custosRota1 = custosRota[r, :]
    custosRota2 = 0.85 .* custosRota[r2, :]
    custosNewRota = custosRota1 + custosRota2
    return (true, newRowNewTipo, dadosNewRotaCon, custosNewRota)
end

function makeConcat(rotasFilt, rotaDados, tempoCarga, tempoMaxMotor, newTipo, custosRota, tf, V)
    rotasFiltOriginal = copy(rotasFilt)

    rotasFiltSet = [Set(rota) for rota in rotasFilt]



    #concatenacao
    rotasFilt1 = [(r, rota) for (r, rota) in enumerate(rotasFilt)]
    rotasFilt2 = [(r, rota) for (r, rota) in enumerate(rotasFilt) if ((rotaDados[rota][1] + tempoCarga[rota[1]] <= tempoMaxMotor) && (rotaDados[rota][end-1] < tf[1]) && (length(rota) < 5))]

    lenRotas1F = length(rotasFilt1)
    lenRotas2F = length(rotasFilt2)

    rotasConcat = [[vcat(primeRota, secondRota), X[2], X[3], X[4]] for (r, primeRota) in rotasFilt1 for (r2, secondRota) in rotasFilt2 for X in [validaConcat(primeRota, secondRota, rotaDados, tempoCarga, rotasFiltSet, r, lenRotas1F, r2, custosRota, lenRotas2F, V)] if X[1] == true]

    rotasValConca = [r[1] for r in rotasConcat]
    rotasValConcaTipo = [r[2] for r in rotasConcat]
    rotasValConcaDados = [r[3] for r in rotasConcat]
    rotasValConcaCustos = [r[4] for r in rotasConcat]

    rotasValConcaTipo = reduce(hcat, rotasValConcaTipo)'
    newTipo = vcat(newTipo, rotasValConcaTipo)

    rotasValConcaCustos = reduce(hcat, rotasValConcaCustos)'

    custosRota = vcat(custosRota, rotasValConcaCustos)

    dictRotasConcat = Dict(zip(rotasValConca, rotasValConcaDados))

    merge!(rotaDados, dictRotasConcat)

    rotasFilt = vcat(rotasFilt, rotasValConca)


    dictAuxDup = Dict()
    for (i, r) in enumerate(rotasFilt)
        dictAuxDup[Set(r)] = i
    end

    custosDict2 = Dict()
    for (i, r) in enumerate(rotasFilt)
        custosDict2[r] = copy(custosRota[i, :])
    end

    rotasFiltAux = [Set(r) for r in rotasFilt]
    rotasFiltAux = Set(rotasFiltAux)
    indicesRotasUnicas = sort([dictAuxDup[sr] for sr in rotasFiltAux])

    rotasFilt = rotasFilt[indicesRotasUnicas]
    newTipo = newTipo[indicesRotasUnicas, :]
    custosRota = custosRota[indicesRotasUnicas, :]


    custosDict = Dict()
    for (i, r) in enumerate(rotasFilt)
        custosDict[r] = custosRota[i, :]
    end
    custosRotaDictAux = copy(custosDict)

    for r in rotasFilt
        custosDict[r] = sort!([(custosDict[r][i], i) for i in V if i in rotaDados[r][end]], by=x -> x[1])
    end
    return newTipo, custosRota, rotasFilt, custosDict
end

function makeA(rotasFilt, nLojas)
    A = zeros((length(rotasFilt), nLojas))
    for r in 1:length(rotasFilt)
        for loja in rotasFilt[r]
            A[r, loja] = 1
        end
    end
    return A
end

function makeNodes(newTipo, R, V)
    nodes = []
    for r in R
        for v in V
            if newTipo[r, v] == 1
                push!(nodes, (r, v))
            end
        end
    end
    return nodes
end

function attPeso(rotasSort,rotas)
    deleteat!(rotasSort,findall(x->x in rotas, rotasSort))
    rotasSort = vcat(rotasSort,rotas)
    return rotasSort
end
