#Função para printar o resultado da otimização
function teste(AOpt, V, R, rl, saidaCD, CHOpt)
    print("\n=================================== RESULTADO ======================================")
    newVeic = true
    newRoute = true
    for v in V
        for r in R
            for l in S
                for s in S
                    if (round(AOpt[l,s,v,r]) == 1)
                    #    print([v,s,(rl[s] == 1 ? 1 : 2),CHOpt[s,v,r],r])
                        if (newVeic)
                            newVeic = false
                            print("\n\nVeic $(v): ")
                            newRoute = false
                            print("\n(Rota $(r)) CD [$(saidaCD[v,r]/4)h] => loja $(s) [$(CHOpt[s,v,r]/4)h,$((rl[s] == 1 ? "Not Roll" : "Roll"))] ")
                        elseif (newRoute)
                            newRoute = false
                            print("\n(Rota $(r)) CD [$(saidaCD[v,r]/4)h] => loja $(s) [$(CHOpt[s,v,r]/4)h,$((rl[s] == 1 ? "Not Roll" : "Roll"))] ")
                        elseif (s == 1)
                            print("| loja $(l) => CD [$(CHOpt[s,v,r]/4)h,$((rl[s] == 1 ? "Not Roll" : "Roll"))] ")
                        else
                            print("| loja $(l) => loja $(s) [$(CHOpt[s,v,r]/4)h,$((rl[s] == 1 ? "Not Roll" : "Roll"))] | ")
                        end
                    end
                end
            end
            newRoute = true
        end
        newVeic = true
    end
    print("\n\n=================================== RESULTADO ======================================")
end



function printaViagem(AOpt, CHOpt, S, V, rl, cp, cv, R)
    lista_caminhao = []
    for i in V
        push!(lista_caminhao, [])
    end

    for v in V
        for r in R
            for l in S
                for s in S
                    if(round(AOpt[l,s,v,r]) == 1)
                        temp = [v,s,(rl[s] == 1 ? 1 : 2),CHOpt[s,v,r],r]
                        push!(lista_caminhao[v], temp)
                    end
                end
            end
        end
    end

  

    #retirando listas vazias
    for rot in lista_caminhao
        if (!isempty(rot))
                sort!(rot, by = x->x[4])
        else
                deleteat!(lista_caminhao, findall(x->x==[],lista_caminhao))
        end
    end

    print("\n\n --------------------------- \n\n")
    print(lista_caminhao)
    

    #convertento horarios para ficar no formato hora.minuto
    for rot in lista_caminhao
        for via in rot
                via[4] = round(via[4], digits=2)
                flo = (round((via[4] - floor(via[4]))*60))/100
                via[4] = floor(via[4]) + flo
        end
    end



    #Calculando carga levada por cada caminhão
    carga_levada = zeros(nVeic, 4, 4)
    for v in V
        peso = 0
        volume = 0
        for r in R
            for s in S
                for l in S
                    if (round(AOpt[l,s,v,r]) == 1)
                            peso += dp[s]
                            volume += dv[s]
                    end
                end
            end
            carga_levada[v,r,1] = peso
            carga_levada[v,r,2] = volume
            carga_levada[v,r,3] = cp[v]
            carga_levada[v,r,4] = cv[v]
        end
    end


    #Calculando porcentagem de carga ocupada e colocando numa matriz + printando caso não use o caminhão
    percentCarga = zeros(nVeic, 4, 2) 

    for v in V
        for r in R
            perCarP = 100*carga_levada[v,r,1]/carga_levada[v,r,3]
            perCarV = 100*carga_levada[v,r,2]/carga_levada[v,r,4]
            percentCarga[v,r,1] = perCarP
            percentCarga[v,r,2] = perCarV
            if (percentCarga[v,r,1] == 0 || percentCarga[v,r,2] == 0)
                    # println("\nO caminhão $v não foi utilizado.")
            else
                println("\nO caminhão $v utilizou $(round.(percentCarga[v,r,1]; digits=2))% de sua carga barométrica e $(round.(percentCarga[v,r,2]; digits=2))% de sua carga volumétrica na rota $(r).")
            end
        end
    end

    println(lista_caminhao)

    # temp = [v,s,(rl[s] == 1 ? 1 : 2),CHOpt[s,v,r]]

    #preparando lista com as rotas para serem printadas
    lista_caminhao_def = []
    for i in lista_caminhao
        loja_de_partida = 1.0
        lista = []
        # println(i)
        for j in i
            loja_de_chegada = j[2]
            horario = j[4]
            if (j[3] == 1)
                row = "Não"
            else
                row = "Sim"
            end
            listaTemp = [j[1], loja_de_partida, loja_de_chegada, row, horario]
            loja_de_partida = loja_de_chegada
            push!(lista, listaTemp)
        end
        push!(lista_caminhao_def, lista)
    end

    #Printando rotas
    println("\n")
    for rota in lista_caminhao_def
        print("\n\n")
        x = 0
        for viagem in rota
                partida = (viagem[2]==1 ? "CD" : "Loja $(idLoja[Int(viagem[2])])")
                chegada = (viagem[3]==1 ? "CD" : "Loja $(idLoja[Int(viagem[3])])")
                if x == 0
                    print("caminhão $(viagem[1]) =>   ")
                    x = 1
                end
                roll = (rota[length(rota)] == viagem ? "" : ", roll: $(viagem[4])")
                sep = (rota[length(rota)] == viagem ? ")" : "  ||  ")
                print("$(partida)  ->  $(chegada) (Hr: $(viagem[5])$(roll)$sep")
        end
    end
end


function printaResult(XOpt, R, V, rotasFilt, cvOriginal, cp, custosRota,idLoja)
    volGraOut = []
    volRollOut = []

    pesoGraOut = []
    pesoRollOut = []

    for r in R
        for v in V
            if XOpt[r, v] == 1
                strRota = ""
                for s in 1:length(rotasFilt[r])
                    strRota = strRota * " -> $(idLoja[rotasFilt[r][s]])"
                end
                percVol = 100 * rotaDados[rotasFilt[r]][3] / cvOriginal[v]
                percPeso = 100 * rotaDados[rotasFilt[r]][2] / cp[v]
                lojaTeste = rotasFilt[r][1]
                if rl[lojaTeste, 1] == 1
                    volGraOut = vcat(volGraOut, percVol)
                    pesoGraOut = vcat(pesoGraOut, percPeso)
                else
                    volRollOut = vcat(volRollOut, percVol)
                    pesoRollOut = vcat(pesoRollOut, percPeso)
                end
                println("veic : $v ===> rota: 0_CDRJ$strRota")
                println("Ocupacao de volume: $percVol")
                println("Ocupacao de peso: $percPeso")
                println("Custo da rota = $(custosRota[r,v])")
                println("")
            end
        end
    end
end

# function insereResulNoBanco(sAddressCode, V, S, AOpt, ExecucaoID, idCaminhao, idHorario, idLoja, CHOpt, SaidaCDOpt)
#     print("[julia] Montando o dataframe de saída...\n")

#     status_tr = retorna_StatusTR()

#     if status_tr == 0

#         df = DataFrame(rota=Int[], execucao_id=Int[], caminhao_id=Int[], horario_id=Int[], loja_id=String[], hora_chegada=Float64[], hora_saida_cd=Float64[])

#         CSV.write("$sAddressCode/resultado.csv", df)

#         for v in V
#             for l in S
#                 for s in S
#                     for r in 1:2
#                         if AOpt[l, s, v, r] == 1
#                             row = [r, ExecucaoID[1, 1], idCaminhao[mod(v, 10)+1], idHorario[s], idLoja[s], CHOpt[s, v, r], saidaCDOpt[v, r]]
#                             push!(df, row)
#                         end
#                     end
#                 end
#             end
#         end
#     else
#         df = DataFrame(rota=Int[], execucao_id=Int[], caminhao_id=Int[], horario_id=Int[], loja_id=String[], hora_chegada=Float64[], caminhao_id_index=Int[], hora_saida_cd=Float64[])

#         CSV.write("$sAddressCode/resultado.csv", df)

#         for v in V
#             for l in S
#                 for s in S
#                     for r in 1:2
#                         if AOpt[l, s, v, r] == 1
#                             row = [r, ExecucaoID[1, 1], idCaminhao[mod(v, 10)+1], idHorario[s], idLoja[s], CHOpt[s, v, r], v, SaidaCDOpt[v, r]]
#                             push!(df, row)
#                         end
#                     end
#                 end
#             end
#         end
#     end

#     print(df)
#     # using CSV
#     # CSV.write("$sAddressCode/resultado.csv", df)

#     #-----------------------------Inserção no Banco----------------------------------------------------------------
#     print("\n")
#     print("[julia] Inserindo no banco...")
#     insereNoBanco(df)
#     atualizaExecucaoID()
#     print("[julia] Fim da execução.")

# end

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


