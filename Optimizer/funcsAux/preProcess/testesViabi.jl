using Decimals

#expande a matriz, colocando a linha e/ou coluna passada como parametro nas extremidades da função
#m = matriz, l = linha, c = coluna, nCol = numero de colunas, nLin = numero de linhas, v = bin pra dizer se é pra concatenar verticalmente, h = bin pra dizer se é pra concatenar horizontalmente
function expMatrix(m, l, c, nCol, nLin, v, h)
    if v
        linha = transpose([m[l, e] for e in range(1, nCol)])
        m = vcat(m, linha)
    end
    
    if h
        linha = [m[e, c] for e in range(1, nLin+1)]
        m = hcat(m, linha)
    end

    return m
end

#Verifica se existe caminhoes disponiveis que aguentam a demanda da loja, caso n existam, divide a demanda da loja o minimo de vezes necessarias para ela poder ser entregue 
function testeVolumePesoUP(rl, cv, cp, dv, dp, tipo, idLoja, nLojas, nVeic, temEntLoj, te, ti, tf, lt, val, idHorario,rv)
    oldNlojas = nLojas #numero original de lojas
    for s in range(1, oldNlojas)
        g = (rl[s,1] == 1 ? 1 : 2) #descobrindo se a loja usa roll ou nao
        temQueDiv = 1  #constante pra saber se tem que dividir ou nao a demanda
        for v in range(1, nVeic)
            if (tipo[s,v] == 1 && cv[v] >= dv[s,g] && cp[v] >= dp[s,g] && rv[v,g] == 1)
                temQueDiv = 0 # se tiver pelo menos um caminhao que pode carregar a demanda da loja, ela n precisa ser dividida
                break
            end
        end
        if temQueDiv == 1
            println("A demanda da loja $(idLoja[s]) terá que ser dividida")
            tipoAce = [i for i in range(1, nVeic) if (tipo[s,i] == 1 && rv[i,g]==1)] #lista com indices de todos os caminhoes que atendem a loja
            cpAce = [i for i in 1:nVeic if (i in tipoAce)]
            cpAce = findmax([cp[i] for i in cpAce]) # capacidade do caminhao com maior capacidade barometrica
            cvAce = [i for i in 1:nVeic if (i in tipoAce)]
            cvAce = findmax([cv[i] for i in cvAce]) # capacidade do caminhao com maior capacidade volumetrica
            # teste para descobrir se a loja precisa de um caminhao com maior capacidade volumetrica ou barometrica e pegando a outra capacidade do caminhao escolhido
            if dv[s,g]/cvAce[1] > dp[s,g]/cpAce[1]
                cpAce=[cp[tipoAce[cvAce[2]]]]
            else
                cvAce=[cv[tipoAce[cpAce[2]]]]
            end
            # Fazendo a divisao da demanda olhando para o que a loja precisa dividir mais, capacidade volumetrica ou barometrica
            if dv[s,g]/cvAce[1] > dp[s,g]/cpAce[1]
                nDiv = floor(dv[s,g]/cvAce[1]) #vendo a quantidades de caminhoes necessarios para levar a demanda da loja
                restoV = dv[s,g] - nDiv*cvAce[1] #pegando o resto da demanda volumetrica que vai sobrar apos dividir nos caminhoes
                restoP = dp[s,g]*restoV/dv[s,g] #o msm de cima, so que com o peso da demanda
                for i in range(1, nDiv)
                    dv = vcat(dv, [cvAce[1] cvAce[1]])
                    dp = vcat(dp, [dp[s,g]*cvAce[1]/dv[s,g] dp[s,g]*cvAce[1]/dv[s,g]])
                    rl = vcat(rl, [rl[s,1] rl[s,2]])
                    tipo = vcat(tipo, transpose(tipo[s,:]))
                    idLoja = [idLoja[i,1] for i in range(1, nLojas)]
                    idLoja = push!(idLoja, idLoja[s])
                    temEntLoj = hcat(temEntLoj, temEntLoj[:,s])
                    temEntLoj = vcat(temEntLoj, transpose(temEntLoj[s,:]))
                    te = vcat(te, [te[s,1] te[s,2]])
                    ti = hcat(ti, ti[s])
                    tf = hcat(tf, tf[s])
                    lt = push!(lt, lt[s])
                    val = vcat(val, transpose(val[s,:]))
                    idHorario = [idHorario[i,1] for i in range(1, nLojas)]
                    idHorario = push!(idHorario, idHorario[s])
                    nLojas += 1
                end
                dv[s,g] = restoV 
                dp[s,g] = restoP
            else
                nDiv = floor(typeof(dp[s,g]/cpAce[1]) == Decimal ? number(dp[s,g]/cpAce[1]) : dp[s,g]/cpAce[1])
                restoP = dp[s,g] - nDiv*cpAce[1]
                restoV = dv[s,g]*restoP/dp[s,g]
                for i in range(1, nDiv)
                    dp = vcat(dp, [cpAce[1] cpAce[1]])
                    dv = vcat(dv, [dv[s,g]*cpAce[1]/dp[s,g] dv[s,g]*cpAce[1]/dp[s,g]])
                    rl = vcat(rl, [rl[s,1] rl[s,2]])
                    tipo = vcat(tipo, transpose(tipo[s,:]))
                    idLoja = [idLoja[i,1] for i in range(1, nLojas)]
                    idLoja = push!(idLoja, idLoja[s])
                    temEntLoj = hcat(temEntLoj, temEntLoj[:,s])
                    temEntLoj = vcat(temEntLoj, transpose(temEntLoj[s,:]))
                    te = vcat(te, [te[s,1] te[s,2]])
                    ti = hcat(ti, ti[s])
                    tf = hcat(tf, tf[s])
                    lt = push!(lt, lt[s])
                    val = vcat(val, transpose(val[s,:]))
                    idHorario = [idHorario[i,1] for i in range(1, nLojas)]
                    idHorario = push!(idHorario, idHorario[s])
                    nLojas += 1
                end
                dv[s,g] = restoV 
                dp[s,g] = restoP
            end
        end
    end
    return rl, [(typeof(i) == Decimal) ? number(i) : i for i in dv], [typeof(i) == Decimal ? number(i) : i for i in dp], tipo, idLoja, nLojas, temEntLoj, te, ti, tf, lt, val, idHorario
end

function testeVolumePesoUPCSV(rl, cv, cp, dv, dp, tipo, idLoja, nLojas, nVeic, temEntLoj, te, ti, tf, lt, val,rv)
    oldNlojas = nLojas #numero original de lojas
    indexesLojasEx = []
    for s in range(1, oldNlojas)
        g = (rl[s,1] == 1 ? 1 : 2) #descobrindo se a loja usa roll ou nao
        temQueDiv = 1  #constante pra saber se tem que dividir ou nao a demanda
        for v in range(1, nVeic)
            if (tipo[s,v] == 1 && cv[v] >= dv[s,g] && cp[v] >= dp[s,g] && rv[v,g] == 1)
                temQueDiv = 0 # se tiver pelo menos um caminhao que pode carregar a demanda da loja, ela n precisa ser dividida
                break
            end
        end
        if temQueDiv == 1
            println("A demanda da loja $(idLoja[s]) terá que ser dividida")
            tipoAce = [i for i in range(1, nVeic) if (tipo[s,i] == 1 && rv[i,g]==1)] #lista com indices de todos os caminhoes que atendem a loja
            cpAce = [i for i in 1:nVeic if (i in tipoAce)]
            cpAce = findmax([cp[i] for i in cpAce]) # capacidade do caminhao com maior capacidade barometrica
            cvAce = [i for i in 1:nVeic if (i in tipoAce)]
            cvAce = findmax([cv[i] for i in cvAce]) # capacidade do caminhao com maior capacidade volumetrica
            # teste para descobrir se a loja precisa de um caminhao com maior capacidade volumetrica ou barometrica e pegando a outra capacidade do caminhao escolhido
            if dv[s,g]/cvAce[1] > dp[s,g]/cpAce[1]
                cpAce=[cp[tipoAce[cvAce[2]]]]
            else
                cvAce=[cv[tipoAce[cpAce[2]]]]
            end
            # Fazendo a divisao da demanda olhando para o que a loja precisa dividir mais, capacidade volumetrica ou barometrica
            if dv[s,g]/cvAce[1] > dp[s,g]/cpAce[1]
                nDiv = floor(dv[s,g]/cvAce[1]) #vendo a quantidades de caminhoes necessarios para levar a demanda da loja
                restoV = dv[s,g] - nDiv*cvAce[1] #pegando o resto da demanda volumetrica que vai sobrar apos dividir nos caminhoes
                restoP = dp[s,g]*restoV/dv[s,g] #o msm de cima, so que com o peso da demanda
                for i in range(1, nDiv)
                    dv = vcat(dv, [cvAce[1] cvAce[1]])
                    dp = vcat(dp, [dp[s,g]*cvAce[1]/dv[s,g] dp[s,g]*cvAce[1]/dv[s,g]])
                    rl = vcat(rl, [rl[s,1] rl[s,2]])
                    tipo = vcat(tipo, transpose(tipo[s,:]))
                    idLoja = [idLoja[i,1] for i in range(1, nLojas)]
                    idLoja = push!(idLoja, idLoja[s])
                    temEntLoj = hcat(temEntLoj, temEntLoj[:,s])
                    temEntLoj = vcat(temEntLoj, transpose(temEntLoj[s,:]))
                    te = vcat(te, [te[s,1] te[s,2]])
                    ti = hcat(ti, ti[s])
                    tf = hcat(tf, tf[s])
                    lt = push!(lt, lt[s])
                    val = vcat(val, transpose(val[s,:]))
                    nLojas += 1
                    push!(indexesLojasEx, nLojas)
                end
                dv[s,g] = restoV 
                dp[s,g] = restoP
            else
                nDiv = floor(dp[s,g]/cpAce[1])
                restoP = dp[s,g] - nDiv*cpAce[1]
                restoV = dv[s,g]*restoP/dp[s,g]
                for i in range(1, nDiv)
                    dp = vcat(dp, [cpAce[1] cpAce[1]])
                    dv = vcat(dv, [dv[s,g]*cpAce[1]/dp[s,g] dv[s,g]*cpAce[1]/dp[s,g]])
                    rl = vcat(rl, [rl[s,1] rl[s,2]])
                    tipo = vcat(tipo, transpose(tipo[s,:]))
                    idLoja = [idLoja[i,1] for i in range(1, nLojas)]
                    idLoja = push!(idLoja, idLoja[s])
                    temEntLoj = hcat(temEntLoj, temEntLoj[:,s])
                    temEntLoj = vcat(temEntLoj, transpose(temEntLoj[s,:]))
                    te = vcat(te, [te[s,1] te[s,2]])
                    ti = hcat(ti, ti[s])
                    tf = hcat(tf, tf[s])
                    lt = push!(lt, lt[s])
                    val = vcat(val, transpose(val[s,:]))
                    nLojas += 1
                    push!(indexesLojasEx, nLojas)
                end
                dv[s,g] = restoV 
                dp[s,g] = restoP
            end
        end
    end
    return rl, [i for i in dv], [i for i in dp], tipo, idLoja, nLojas, temEntLoj, te, ti, tf, lt, val, indexesLojasEx
end

function testeVolumePesoUPCSV2(rl, cv, cp, dv, dp, tipo, idLoja, nLojas, nVeic, temEntLoj, te, ti, tf, lt, val,rv)
    oldNlojas = nLojas #numero original de lojas
    indexesLojasEx = []
    for s in range(1, oldNlojas)
        g = (rl[s,1] == 1 ? 1 : 2) #descobrindo se a loja usa roll ou nao
        temQueDiv = 1  #constante pra saber se tem que dividir ou nao a demanda
        for v in range(1, nVeic)
            if (tipo[s,v] == 1 && cv[v] >= dv[s,g] && cp[v] >= dp[s,g] && rv[v,g] == 1)
                temQueDiv = 0 # se tiver pelo menos um caminhao que pode carregar a demanda da loja, ela n precisa ser dividida
                break
            end
        end
        if temQueDiv == 1
            println("A demanda da loja $(idLoja[s]) terá que ser dividida")
            tipoAce = [i for i in range(1, nVeic) if (tipo[s,i] == 1 && rv[i,g]==1)] #lista com indices de todos os caminhoes que atendem a loja
            cpAce = [i for i in 1:nVeic if (i in tipoAce)]
            cpAce = findmax([cp[i] for i in cpAce]) # capacidade do caminhao com maior capacidade barometrica
            cvAce = [i for i in 1:nVeic if (i in tipoAce)]
            cvAce = findmax([cv[i] for i in cvAce]) # capacidade do caminhao com maior capacidade volumetrica
            if length(tipoAce) > 1
                indexPesoMax = cpAce[2]
                indexVolMax = cvAce[2]
                if length(tipoAce) > 2
                    tipoAce = setdiff(tipoAce, [indexPesoMax,indexVolMax])
                else
                    tipoAce = setdiff(tipoAce,[indexVolMax])
                end
                cpAce = [i for i in 1:nVeic if (i in tipoAce)]
                cpAce = findmax([cp[i] for i in cpAce]) # capacidade do caminhao com maior capacidade barometrica
                cvAce = [i for i in 1:nVeic if (i in tipoAce)]
                cvAce = findmax([cv[i] for i in cvAce]) # capacidade do caminhao com maior capacidade volumetrica
            end
            # teste para descobrir se a loja precisa de um caminhao com maior capacidade volumetrica ou barometrica e pegando a outra capacidade do caminhao escolhido
            if dv[s,g]/cvAce[1] > dp[s,g]/cpAce[1]
                cpAce=[cp[tipoAce[cvAce[2]]]]
            else
                cvAce=[cv[tipoAce[cpAce[2]]]]
            end
            # Fazendo a divisao da demanda olhando para o que a loja precisa dividir mais, capacidade volumetrica ou barometrica
            if dv[s,g]/cvAce[1] > dp[s,g]/cpAce[1]
                nDiv = floor(dv[s,g]/cvAce[1]) #vendo a quantidades de caminhoes necessarios para levar a demanda da loja
                restoV = dv[s,g] - nDiv*cvAce[1] #pegando o resto da demanda volumetrica que vai sobrar apos dividir nos caminhoes
                restoP = dp[s,g]*restoV/dv[s,g] #o msm de cima, so que com o peso da demanda
                for i in range(1, nDiv)
                    dv = vcat(dv, [cvAce[1] cvAce[1]])
                    dp = vcat(dp, [dp[s,g]*cvAce[1]/dv[s,g] dp[s,g]*cvAce[1]/dv[s,g]])
                    rl = vcat(rl, [rl[s,1] rl[s,2]])
                    tipo = vcat(tipo, transpose(tipo[s,:]))
                    idLoja = [idLoja[i,1] for i in range(1, nLojas)]
                    idLoja = push!(idLoja, idLoja[s])
                    temEntLoj = hcat(temEntLoj, temEntLoj[:,s])
                    temEntLoj = vcat(temEntLoj, transpose(temEntLoj[s,:]))
                    te = vcat(te, [te[s,1] te[s,2]])
                    ti = hcat(ti, ti[s])
                    tf = hcat(tf, tf[s])
                    lt = push!(lt, lt[s])
                    val = vcat(val, transpose(val[s,:]))
                    nLojas += 1
                    push!(indexesLojasEx, nLojas)
                end
                dv[s,g] = restoV 
                dp[s,g] = restoP
            else
                nDiv = floor(dp[s,g]/cpAce[1])
                restoP = dp[s,g] - nDiv*cpAce[1]
                restoV = dv[s,g]*restoP/dp[s,g]
                for i in range(1, nDiv)
                    dp = vcat(dp, [cpAce[1] cpAce[1]])
                    dv = vcat(dv, [dv[s,g]*cpAce[1]/dp[s,g] dv[s,g]*cpAce[1]/dp[s,g]])
                    rl = vcat(rl, [rl[s,1] rl[s,2]])
                    tipo = vcat(tipo, transpose(tipo[s,:]))
                    idLoja = [idLoja[i,1] for i in range(1, nLojas)]
                    idLoja = push!(idLoja, idLoja[s])
                    temEntLoj = hcat(temEntLoj, temEntLoj[:,s])
                    temEntLoj = vcat(temEntLoj, transpose(temEntLoj[s,:]))
                    te = vcat(te, [te[s,1] te[s,2]])
                    ti = hcat(ti, ti[s])
                    tf = hcat(tf, tf[s])
                    lt = push!(lt, lt[s])
                    val = vcat(val, transpose(val[s,:]))
                    nLojas += 1
                    push!(indexesLojasEx, nLojas)
                end
                dv[s,g] = restoV 
                dp[s,g] = restoP
            end
        end
    end
    return rl, [i for i in dv], [i for i in dp], tipo, idLoja, nLojas, temEntLoj, te, ti, tf, lt, val, indexesLojasEx
end

#Função para expandir o horario maximo de retorno ao cd caso necessário
function testeHorario(ti, td, te, tf, nLojas, idLoja)
    for i in range(1, nLojas)
        if ti[i] + td[1,i] + te[i] + td[i, 1] > tf[1] #se o tempo de descarregar a carga e se locomover ate o cd for maior que o horario que o cd fecha, extendemos esse horario
            x = (ti[i] + td[1,i] + te[i] + td[i,1]) - tf[1] + 0.15
            println("É impossivel entregar na loja $(idLoja[i]) e retornar ao CD até $(tf[1]), portanto iremos aumentar o horário limite de retorno ao CD em $x horas")
            tf[1] = tf[1] + x
        end
    end
    return tf
end
