function testaAtenLoja(AOpt, V, S, nLojas)
    lojasSaida = zeros(nLojas)
    lojasChegada = zeros(nLojas)
    for s in S
        for l in S
            for v in V
                for r in 1:2
                    if AOpt[s,l,v,r] == 1
                        lojasSaida[s] += 1
                        lojasChegada[l] += 1    
                    end
                end
            end
        end
    end
    lojasSaidaSemCD = lojasSaida
    lojasChegadaSemCD = lojasChegada
    for i in 2:nLojas
        if lojasSaidaSemCD[i] > 1 || lojasChegadaSemCD[i] > 1
            println("loja $i foi atendida mais de uma vez")
        end
    end
end

function testeTempDes(AOpt, td, S, V, CHOpt, SaidaCDOpt)
    for s in S
        for l in S
            for v in V
                for r in 1:2
                    if AOpt[s,l,v,r] == 1
                        aux = 0
                        if s == 1
                            aux = CHOpt[l,v,r] - SaidaCDOpt[v,r]
                        else
                            aux = CHOpt[l,v,r] - CHOpt[s,v,r]
                        end
                        if aux + 0.1 < td[s,l] + te[s]
                            println("O tempo de deslocamento entre a loja $s e $l foi desrespeitado em $(td[s,l]-aux), jornada $r, saiu do CD em $(SaidaCDOpt[v,r]), chegou na loja em $(CHOpt[l,v,r]), td = $(td[s,l])")
                        end
                    end
                end
            end
        end
    end
end

function testaJanela(rotas, ti, tf, CHOpt, dictRotas)
    for r in rotas
        veic = dictRotas[r]
        for (i,s) in enumerate(r)
            jornada = (length(findall(x -> x == 1, r)) == 1 ? 1 : 3 - length(findall(x -> x == 1, r[i:end])))
            if s != 1
                if CHOpt[s,veic,jornada] > tf[s]
                    println("A loja $s recebeu demanda depois do horario final dela (diferença de $(CHOpt[s,veic,jornada] - tf[s]))")
                elseif CHOpt[s,veic,jornada] < ti[s]
                    println("A loja $s recebeu demanda antes do horario inicial dela (diferença de $(ti[s] - CHOpt[s,veic,jornada]))")
                end
            end
        end
    end
end

function testaLoadTime(rotas, tempoCarga, CHOpt, SaidaCDOpt, dictRotas)
    rotasSegJourney = [r for r in rotas if (length(findall(x->x==1, r)) == 2)]
    for r in rotasSegJourney
        loadTime = tempoCarga[r[1]]
        veic = dictRotas[r]
        if SaidaCDOpt[veic,2] - CHOpt[1,veic,1] < loadTime
            println("O tempo de carregamento na rota $r não foi respeitado por $(loadTime - (SaidaCDOpt[veic,2] - CHOpt[1,veic,1]))")
        end
    end 
end

function test_driverTimeLimit(CHOpt, saidaCDOpt, lim_motorista, V, R, tempoCarga, rv)
    validate = true
    for v in V
        for r in R
            aux = (r == 1 ? 0 : (rv[v, 1] == 1 ? maximum(tempoCarga) : minimum(tempoCarga)))
            horasTrabalhadas = CHOpt[1, v, r] - saidaCDOpt[v, r] + aux
            if horasTrabalhadas > lim_motorista
                println("[TEST FAIL] A rota composta pelo veículo $v em sua jornada $r não respeita o limite do motorista | Tempo rodando: $horasTrabalhadas | $aux, $(saidaCDOpt[v,r]), $(CHOpt[1,v,r])")
                validate = false
            end
        end
    end
    return validate
end

function testaPesoVol(AOpt, V, cp, cv, dp, dv)
    for v in V
        for i in 1:2
            lojasMatrix = AOpt[:,:,v,i]
            lojasAtendidas = findall(x->x==1, lojasMatrix)
            if isempty(lojasAtendidas)
                continue
            end
            lojas = Set()
            for arco in lojasAtendidas
                push!(lojas,arco[1])
                push!(lojas,arco[2])
            end
            volumeUsado = sum([dv[s] for s in lojas])
            pesoUsado = sum([dp[s] for s in lojas])
            capaVol = cv[v]
            capaPeso = cp[v]
            if volumeUsado > capaVol
                println("Limite de volume do veic $v foi extrapolado em $(volumeUsado-capaVol) na jornada $i")
            end

            if pesoUsado > capaPeso
                println("Limite de peso do veic $v foi extrapolado em $(pesoUsado-capaPeso) na jornada $i")
            end
        end
    end
end

function testaTipo(AOpt, tipo, V, S)
    for s in S
        for l in S
            for v in V
                for r in 1:2
                    if AOpt[s,l,v,r] == 1
                        if tipo[s,v] != 1
                            println("Restrição de tipologia violada com loja $s e veic $v")
                        end
                        if tipo[l,v] != 1
                            println("Restrição de tipologia violada com loja $l e veic $v")
                        end
                    end
                end
            end
        end
    end                 
end

