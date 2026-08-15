using DataFrames
using CSV
using LibPQ
using Decimals
using StatsBase
using JuMP, Gurobi, SCIP, HiGHS

include("/home/puc/artigo/CodigOld/acessoBanco.jl")
include("/home/puc/artigo/Optimizer/funcsAux/preProcess/preProcess.jl")
include("/home/puc/artigo/Optimizer/funcsAux/preProcess/testesViabi.jl")
include("/home/puc/artigo/Optimizer/funcsAux/DataFormatacao/expVeic.jl")

#to do retirar veiculos
#to do terceira concatenacao
#to do parar quando não haver negativa


function loadData(statusTR = false, tempoMotor = false, lojasExclu = [])
    sAddressCode = pwd()
    sAddressCode = "$sAddressCode/"

    print("[julia] Importando dados do banco...\n")
    statusTR = (statusTR == false ? retorna_StatusTR() : 0)

    #--------------------------------------Extraindo informações do banco de dados---------------------------------------------------- 
    nLojas = retorna_nLojas()[1, 1]
    if (statusTR == 0)
        nVeicCSV = retorna_nVeic()
        CapaVolCSV = retorna_VolumeCaminhao()
        CapaPesoCSV = retorna_PesoCaminhao()
        CustoCSV = retorna_Custo()
        TipoCSV = retorna_TipologiaDisponivel()
        RowVCSV = retorna_temPlataforma()
        infoCaminhao = retorna_InfoCaminhao()
    else
        nVeicCSV = retorna_TRnVeic()
        CapaVolCSV = retorna_TRVolume()
        CapaPesoCSV = retorna_TRPeso()
        CustoCSV = retorna_TRCusto()
        TipoCSV = retorna_TRTipologiaDisponivel()
        RowVCSV = retorna_TRtemPlataforma()
        infoCaminhao = retorna_InfoCaminhaoTR()
    end
    VolumeCSV = retorna_VolumeLoja()
    PesoCSV = retorna_PesoLoja()
    RowLCSV = retorna_recebeRoll()
    TeCSV = retorna_TempoDescarregamento()
    HoraIniCSV = retorna_HoraIni()
    HoraFimCSV = retorna_HoraFim()
    tDesCSV = CSV.File("$(sAddressCode)tempo_seg_index-lojas.csv") |> DataFrame
    ExecucaoID = retorna_IDSaida()
    dataData = number(retorna_DataEntrega())

    #--------------------------Retirando labels do tDesCSV que vieram da planilha e guardando eles em um array (idLoja e idCaminhao)------------------------
   
    idCaminhao = CapaVolCSV[!, :1]
    idHorario = HoraIniCSV[!, :1]
    idLoja = VolumeCSV[!,:1]

    #---------------------------Ordenando as listas que vieram do banco me baseando no idLoja e idCaminhao-----------------------------------
    #=getIndexes pega os index dos dataframes comparando os ids deles da coluna de labels deles com os ids recolhidos anteriormente
    por exemplo, se o idLoja loja for [A,B,C] e a coluna de labels de VolumeCSV for [C,A,B] getIndexes irá retornar [2,3,1], pois
    [C,A,B][2,3,1] = [A,B,C], caso algum label tenha um id que não está presente no idLoja ou vice-versa dará erro
    =#

    indexesTD = findall(x->x in idLoja, tDesCSV[!,1])
    tDesCSV = tDesCSV[indexesTD,pushfirst!(indexesTD.+1,1)]

    #VolumeCSV = VolumeCSV[getIndexes(VolumeCSV[!, 1], idLoja), :]
    tDesCSV = tDesCSV[getIndexes(tDesCSV[!, 1], idLoja), getIndexes(tDesCSV[!, 1], idLoja).+1]
    PesoCSV = PesoCSV[getIndexes(PesoCSV[!, 1], idLoja), :]
    CustoCSV = CustoCSV[getIndexes(CustoCSV[!, 1], idLoja), :]
    TeCSV = TeCSV[getIndexes(TeCSV[!, 1], idLoja), :]
    TipoCSV = TipoCSV[getIndexes(TipoCSV[!, 1], idLoja), :]
    RowLCSV = RowLCSV[getIndexes(RowLCSV[!, 1], idLoja), :]
    HoraIniCSV = HoraIniCSV[getIndexes(HoraIniCSV[!, 2], idLoja), :]
    HoraFimCSV = HoraFimCSV[getIndexes(HoraFimCSV[!, 2], idLoja), :]

    CapaVolCSV = CapaVolCSV[getIndexes(CapaVolCSV[!, 1], idCaminhao), :]
    CapaPesoCSV = CapaPesoCSV[getIndexes(CapaPesoCSV[!, 1], idCaminhao), :]
    infoCaminhao = infoCaminhao[getIndexes(infoCaminhao[!, 1], idCaminhao), :]
    RowVCSV = RowVCSV[getIndexes(RowVCSV[!, 1], idCaminhao), :]


    #--------------------Retirando labels dos dataframes vindos do BD--------------------------------------------------------------
    print("[julia] Retirando títulos e rótulos que vieram do BD...\n")
    select!(VolumeCSV, Not([:1]))
    select!(PesoCSV, Not([:1]))
    select!(CapaVolCSV, Not([:1]))
    select!(CapaPesoCSV, Not([:1]))
    select!(CustoCSV, Not([:1]))
    select!(TeCSV, Not([:1]))
    select!(TipoCSV, Not([:1]))
    select!(RowLCSV, Not([:1]))
    select!(RowVCSV, Not([:1]))
    select!(HoraIniCSV, Not([:1]))
    select!(HoraFimCSV, Not([:1]))
    select!(HoraIniCSV, Not([:1]))
    select!(HoraFimCSV, Not([:1]))

    CustoCSV = CustoCSV[:, getIndexes([parse(Int64, i) for i in names(CustoCSV)[1:end]], idCaminhao)]
    TipoCSV = TipoCSV[:, getIndexes([parse(Int64, i) for i in names(TipoCSV)[1:end]], idCaminhao)]

    tempoMaxMotor = (tempoMotor == false ? retornaJornadaMotorista() : tempoMotor)

    #=Podemos adicionar indexes de lojas que não queremos que o modelo considere em lojasExclu (por fins de teste) e Saux vai incluir todos os 
    indexes menos esses para retirar as lojas desejadas de todos os dataframes, atualizando os indexes e a quantidade de lojas depois
    =#

    Saux = setdiff(1:nLojas, lojasExclu)
    VolumeCSV = VolumeCSV[Saux, :]
    PesoCSV = PesoCSV[Saux, :]
    CustoCSV = CustoCSV[Saux, :]
    TeCSV = TeCSV[Saux, :]
    TipoCSV = TipoCSV[Saux, :]
    RowLCSV = RowLCSV[Saux, :]
    HoraIniCSV = HoraIniCSV[Saux, :]
    HoraFimCSV = HoraFimCSV[Saux, :]
    tDesCSV = tDesCSV[Saux,Saux]
    idLoja = idLoja[Saux]
    idHorario = idHorario[Saux]

    nLojas = nLojas - length(lojasExclu)
    nLojasOri = nLojas
    nVeic = nVeicCSV[1, 1]
    S = 1:nLojas
    S_cd = 2:nLojas

    V = 1:nVeic

    G = 1:2

    #=Aqui passamos os dados do formato de dataframe para o formato de matrix que é o usado no resto do código, além disso traspondo algumas
    matrizes para ficar no formato usado pelo sistema=#
    dv = Matrix(VolumeCSV)[1:nLojas, :]
    dp = Matrix(PesoCSV)[1:nLojas, :]
    idLoja = idLoja[1:nLojas, :]
    rl = Matrix(RowLCSV)[1:nLojas, :]
    rv = Matrix(RowVCSV)

    cv = transpose(Matrix((CapaVolCSV)))

    #=Aqui descontamos da capacidade volumetrica o valor respectivo que deve ser descontado, no caso do roll atualmente está
    hard-coded para usar somente 0.48% da capacidade e no caso de granel retiramos o percentual do banco, é necessário usar a 
    função number nesse último caso pois o valor que vem do banco está em Decimals e precisamos dele em float ou int=#
    constPercRoll = 0.48
    cvOriginal = copy(cv)
    cv = [rv[v, 1] == 1 ? cv[v] * number(retornaPercentualVolume() / 100) : cv[v] * constPercRoll for v in V]

    cp = transpose(Matrix(CapaPesoCSV))
    cp = [number(i) for i in cp]

    val = Matrix(CustoCSV)
    val[:1, :] = zeros(1, nVeic)
    val = val[1:nLojas, :]
    newVal = zeros(nLojas, nVeic)

    lt = Matrix(tDesCSV)[1:nLojas, 1:nLojas]
    lt = lt[:1, :]

    ti = transpose(Matrix(HoraIniCSV))
    ti = ti[:, 1:nLojas]

    tf = transpose(Matrix(HoraFimCSV))
    tf = tf[:, 1:nLojas]
    tf = [i + 0.15 for i in tf]
    te = Matrix(TeCSV)[1:nLojas, :]

    td = Matrix(tDesCSV) 
    #td = td[1:nLojas, 2:(nLojas+1)] 

    tipo = Matrix(TipoCSV)[1:nLojas, :]

    #Convertendo, se necessário, o tipo dos dados dentro dessas matrizes de Decimals para float (ou int)
    if typeof(ti[1]) == Decimal
        ti = [number(i) for i in ti]
    end
    if typeof(tf[1]) == Decimal
        tf = [number(i) for i in tf]
    end
    if typeof(te[1]) == Decimal
        te = [number(i) for i in te]
    end
    if typeof(cv[1]) == Decimal
        cv = [number(i) for i in cv]
    end
    if typeof(cp[1]) == Decimal
        cp = [number(i) for i in cp]
    end
    if typeof(cvOriginal[1]) == Decimal
        cvOriginal = [number(i) for i in cvOriginal]
    end


    #=Existem casos em que não temos o valor de algumas tipologias para certas lojas e elas vẽm como Missing na matriz, o que 
    ocasiona erros indesejáveis, para evitar isso nós colocamos esse par de loja-tipologia em tipo_aux e trocamos o valor de
    Missing para 0, depois pegamos todas esses pares de loja-tipologia em tipo_aux e colocamos o tipo deles como 0, dessa forma
    a loja será impedida de ser atribuída à esse veículo devido restrições na fase de criação de rotas, portanto o valor do veiculo 
    ser 0 para essa loja não influencia em nada o resultado final da otimização=#
    tipo_aux = []
    for i in S
        for j in V
            if !(ismissing(val[i, j]))
                newVal[i, j] = val[i, j]
            else
                newVal[i, j] = 0
                push!(tipo_aux, [i, j])
            end
        end
    end

    val = newVal

    tipo = Matrix(TipoCSV)[1:nLojas, :]
    for tipo_a in tipo_aux
        tipo[tipo_a[1], tipo_a[2]] = 0
    end

    #Convertendo a demanda das lojas que eram em roll para adicionar o volume de rolls necessário para entrega delas e o peso deles
    #dp, dv = converteRoll(dp, dv, S)
    tipo2 = copy(tipo)

    #=Checando se tem lojas que são impossíveis de entregar devido a demanda muito grande e se tiver, dividindo a demanda delas 
    para que possam ser entregues e atualizando as matrizes de dados com as divisões que foram necessárias, também atualizando
    o numero de lojas=#
    rl, dv, dp, tipo, idLoja, nLojas, td, te, ti, tf, lt, val, indexesLojasEx = testeVolumePesoUPCSV2(rl, cv, cp, dv, dp, tipo, idLoja, nLojas, nVeic, td, te, ti, tf, lt, val,rv)
    S = 1:nLojas
    S_cd = 2:nLojas

    #=Caso o retorna_StatusTR for igual a 1 (o modelo tiver sendo executado em modo tipologia recomendada/infinita) o multiplicaVeiculo
      vai ser igual ao nLojas para multiplicar deixar um veiculo de cada tipologia para cada loja, nFicaMatrix é uma função que multiplica
      a matrix pelo valor em multiplicaVeiculo, caso retorna_StatusTR seja 0, multiplicaVeiculo será 1 e as matrizes continuaram iguais
    =#
    multiplicaVeiculo = (statusTR == 1 ? nLojas : 1)

    tipo = nFicaMatrix(multiplicaVeiculo, tipo, 0)
    rv = nFicaMatrix(multiplicaVeiculo, rv, 1)
    cp = nFicaMatrix(multiplicaVeiculo, cp, 0)
    cv = nFicaMatrix(multiplicaVeiculo, cv, 1)
    cvOriginal = nFicaMatrix(multiplicaVeiculo, cvOriginal, 0)'
    idCaminhao = nFicaMatrix(multiplicaVeiculo, idCaminhao, 0)'
    val = nFicaMatrix(multiplicaVeiculo, val, 0)
    nVeic = nVeic * multiplicaVeiculo
    V = 1:nVeic

    #=Essa parte muda o tipo[s,v] para 0 caso o veiculo v não seja capaz de levar a demanda da loja s, o formataTipoB considera que veiculos
    de roll podem levar carga granel, o A considera que caminhao de roll so pode levar lojas roll
    =#
    if retornaCompartilha() == 1
        tipo = formataTipoB(tipo, S_cd, rl, dp, dv, V, rv, cp, cv)
    else
        tipo = formataTipoA(tipo, S_cd, rl, dp, dv, V, rv, cp, cv)
    end


    #Se houver alguma loja que não possua caminhao capaz de levar a demanda dela irá printar essa mensagem de erro 
    for s in S
        if !(1 in tipo[s, :])
            println("Problemas com a loja de indice $s, id $(idLoja[s]), dv=$(dv[s]), dp=$(dp[s]), roll=$(rl[s,1]==1 ? "No" : "Yes")")
        end
    end


    dp = [(rl[s, 1] == 1 ? dp[s, 1] : dp[s, 2]) for s in S]
    dv = [(rl[s, 1] == 1 ? dv[s, 1] : dv[s, 2]) for s in S]
    te = [(rl[s, 1] == 1 ? te[s, 1] : te[s, 2]) for s in S]
    cp = [(rv[v, 2] == 1 ? 1 : 1) * cp[v] for v in V]

    #Se for impossível entregar em alguma loja e voltar pro CD antes do horario final do CD o testeHorario irá aumenar o horario final do CD
    tf = testeHorario(ti, td, te, tf, nLojas, idLoja)

    #retorna o tempo de carregamento das lojas
    tempoCarga = zeros(nLojas)
    for i in S
        if rl[i, 1] == 1
            tempoCarga[i] = 2
        else
            tempoCarga[i] = 0.5
        end
    end

    return idLoja, idCaminhao, idHorario, nLojas, nLojasOri, nVeic, S, S_cd, V, G, dv, dp, rl, rv, cv, cvOriginal, cp, val, lt, ti, tf, te, td, tipo, tempoMaxMotor, tempoCarga, ExecucaoID, indexesLojasEx, dataData, infoCaminhao, tipo2
end