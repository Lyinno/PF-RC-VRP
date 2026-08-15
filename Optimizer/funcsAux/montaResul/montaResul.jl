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

function convertDecimalToSeg(time)
    hour = floor(Int,time)
    minutesDecimal = time - hour
    minutes = round(Int,60*minutesDecimal)
    timeConverted = "$(lpad(hour,2,"0")):$(lpad(minutes,2,"0"))"
    return timeConverted
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
