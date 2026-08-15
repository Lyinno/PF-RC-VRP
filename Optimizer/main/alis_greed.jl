using DataFrames
using CSV
using LibPQ
using Decimals
using StatsBase
using JuMP, Gurobi, HiGHS

path = pwd()

include("$(path)/artigo/CodigOld/acessoBanco.jl")
include("$(path)/artigo/Optimizer/modeloDualsAndAux/dualsAux.jl")
include("$(path)/artigo/Optimizer/modeloDualsAndAux/modeloDuals.jl")
include("$(path)/artigo/Optimizer/funcsAux/montaResul/montaResul.jl")
include("$(path)/artigo/Optimizer/funcsAux/testaResul/testaResul.jl")
include("$(path)/artigo/Optimizer/funcsAux/loadData/loadData.jl")

#todo duplicar idHorario na divisao de demanda
#lojas 50(L010), 55(1012), 56(L858) usam o mesmo veic (96), 105(52 após divisão)(L653), 106(54 após divisão)(L281) usam o msm veic (49)

#todo voltar convert roll e 55%
#57% e 39%

function main()
    sAddressCode = pwd()
    sAddressCode = "$sAddressCode/"

    StatusTr = number(retorna_StatusTR()) 
    (idLoja, idCaminhao, idHorario, nLojas, nLojasOri, nVeic, S, S_cd, V, G, dv, dp, rl, rv, cv, cvOriginal, cp, val, lt, ti, tf, te, td, tipo, tempoMaxMotor, tempoCarga, ExecucaoID, indexesLojasEx, dataData, infoCaminhao) = loadData("N", 10, [])

    ExecucaoID = number(ExecucaoID[1,1])

    (adjDepois, arcos) = makeArcos(S, S_cd, V, dv, dp, rl, cv, cp, ti, tf, te, td, tipo, tempoMaxMotor)
    (rotasFilt, rotaDados) = enumerar(adjDepois, 2:nLojas, td, ti, tf, te, cp, cv, V, tempoMaxMotor, dp, dv, tipo, 4)

    veicPerRota = makeVeicPerRota(rotasFilt, rotaDados)
    custosRota = makeCustosRota(rotasFilt, V, val)
    newTipo = makeNewTipo(rotasFilt, nVeic, veicPerRota, V)

    (newTipo, custosRota, rotasFilt, custosDict) = makeConcat(rotasFilt, rotaDados, tempoCarga, tempoMaxMotor, newTipo, custosRota, tf, V)

    R = 1:length(rotasFilt)

    nodes = makeNodes(newTipo, R, V)
    A = makeA(rotasFilt, nLojas)

    (RU, XOpt) = modeloDuals(S,R,V,custosRota,rotasFilt,newTipo,custosDict,A,S_cd)
    
    #(model, X, setPartition, vehicleTypeFixation, vehicleAssignment) = montarModelMatricial(nodes,A,custosRota,newTipo,R,V,S_cd)

    nodeXOpt = []
    hsize = 1:(size(XOpt)[1])
    vsize = 1:(size(XOpt)[2])

    for line in hsize
        if 1 in (XOpt[line,:].>0)
            push!(nodeXOpt,[RU[line],findall(x->x==1,[i for i in (XOpt[line,:].>0)])[1]])
        end
    end

    XOpt = zeros(R,V)

    for node in nodeXOpt
        XOpt[node[1],node[2]] = 1
    end



    #printaResult(XOpt, R, V, rotasFilt, cvOriginal, cp, custosRota, idLoja)

    (rotas, dictRotas) = getSelectedRoutes(XOpt, rotasFilt)
    (CHOpt, SaidaCDOpt) = makeChOptSaidaCDOpt(rotas, td, nLojas, nVeic, dictRotas, rotaDados, ti, te)

    AOpt = makeAOpt(nLojas, nVeic, nodeXOpt, rotasFilt)

    testaPesoVol(AOpt, V, cp, cv, dp, dv)
    testaTipo(AOpt, tipo, V, S)
    testaAtenLoja(AOpt, V, S, nLojas)
    testeTempDes(AOpt, td, S, V, CHOpt, SaidaCDOpt)
    testaJanela(rotas, ti, tf, CHOpt, dictRotas)
    testaLoadTime(rotas, tempoCarga, CHOpt, SaidaCDOpt, dictRotas)
    test_driverTimeLimit(CHOpt, SaidaCDOpt, tempoMaxMotor, V, 1:2, tempoCarga, rv)

    
    df = DataFrame(execucao_id=Int64[], data_entrega=String[], loja=String[], hora_recebimento=String[], demanda_volume=Float64[], demanda_peso=Float64[], tipo_entrega=String[], jornada=Int64[], placa=String[], tipologia=String[], volume_entregue=Float64[], peso_entregue=Float64[], capacidade_volume=Float64[],capacidade_peso=Float64[],valorFrete=Float64[],hora_saida=String[])

    dadosCamCSV = infoCaminhao
    dictIdPlaca = Dict(dadosCamCSV[:, 1] .=> dadosCamCSV[:, 2])
    dictTipoName = Dict(dadosCamCSV[:, 1] .=> dadosCamCSV[:, 3])

    veicRotaDemanda = zeros(V,4)
    valorFrete = []
    for v in V
        for r in 1:2
            col = (r==1 ? 1 : 3)
            rotaAtual = Set()
            for l in S
                for s in S
                    if AOpt[l,s,v,r] == 1
                        push!(rotaAtual,s)
                        veicRotaDemanda[v,col] += dv[s]
                        veicRotaDemanda[v,col+1] += dp[s]
                    end
                end
            end
            if !isempty(rotaAtual)
                push!(valorFrete,(rotaAtual,v,r))
            end
        end
    end

    setCustosDict = Dict()
    for r in keys(custosDict)
        setCustosDict[Set(r)] = custosDict[r]
    end

    dictValor = Dict()
    for vf in valorFrete
        dictValor[(vf[2],vf[3])] = setCustosDict[vf[1]][findall(x->x[2]==vf[2], setCustosDict[vf[1]])][1][1]*(vf[3] > 1 ? 0.85 : 1)
    end


    StatusTr = 0
    for v in V
        for l in S
            for s in S
                for r in 1:2
                    if AOpt[l, s, v, r] == 1
                        dataCopy = "$dataData"
                        year = dataCopy[1:4]
                        month = dataCopy[5:6]
                        day = dataCopy[7:8]
                        if CHOpt[s,v,r] >= 24
                            day = "$(parse(Int64,day) + 1)"
                            CHOpt[s,v,r] -= 24
                        end
                        if SaidaCDOpt[v,r] >= 24
                            SaidaCDOpt[s,v,r] -= 24
                        end
                        horaCheg = convertDecimalToSeg(CHOpt[s,v,r])
                        horaSaida = convertDecimalToSeg(SaidaCDOpt[v,r])
                        placa = dictIdPlaca[v]
                        tipologia = dictTipoName[v]
                        date = "$year-$month-$day"
                        tipoEntrega = (rl[s,1] == 1 ? "G" : "R")
                        volumeEntregue = veicRotaDemanda[v,(r==1 ? 1 : 3)]
                        pesoEntregue = veicRotaDemanda[v,(r==1 ? 1 : 3)+1]
                        valorFreteAtual = dictValor[(v,r)]
                        row = [ExecucaoID,date,idLoja[s],horaCheg,dv[s],dp[s],tipoEntrega,r,(StatusTr == 0 ? placa : v),tipologia,volumeEntregue,pesoEntregue,cvOriginal[v],cp[v],valorFreteAtual,horaSaida]
                        push!(df, row)
                    end
                end
            end
        end
    end

    # sort!(df, [order(:placa), order(:jornada), order(:hora_recebimento)])

    # CSV.write("$sAddressCode/resultadoBoto.csv", df)
    
    # if StatusTr == 0
    #     insereNoBanco(df)
    # else
    #     insereNoBancoTR(df)
    # end
end





