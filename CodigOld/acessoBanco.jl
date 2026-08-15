using LibPQ
using DataFrames
using Decimals

begin
    database = "alis"
    user = "postgres"
    host = "localhost"
    port = "5432"
    password = "jaap4055"

   conn =  LibPQ.Connection("host=$(host)
                      port=$(port)
                      dbname=$(database)
                      user=$(user)
                      password=$(password)
                      "; throw_error=true)
end

function retorna_DiaSemana()
    dia_semana = execute(conn, "SELECT valor FROM constantes WHERE chave = 'dia_semana';") |> DataFrame
    return dia_semana[1, 1]
end

function retorna_nLojas()
    dia_semana = retorna_DiaSemana()
    nLojas = execute(conn, "SELECT count(*) FROM loja_dia($dia_semana);") |> DataFrame
    return nLojas
end

function retorna_nVeic()
    nVeic = execute(conn, "SELECT count(*) FROM caminhoes_disponiveis();") |> DataFrame
    return nVeic
end

function retorna_DataEntrega()
    DataEntrega = execute(conn, "SELECT valor FROM constantes WHERE chave = 'data_execucao';") |> DataFrame
    data = DataEntrega[1, 1]
    # Está no formato em float em que é AAAAMMDD. É sempre assim porque atualmente a tabela de constantes aceita valores em float.
    return DataEntrega[1, 1]
end

function retorna_TRnVeic()
    nVeic = execute(conn, "SELECT count(*) FROM tipologia;") |> DataFrame
    return nVeic
end

function retorna_VolumeLoja()
    dia_semana = retorna_DiaSemana()
    VolumeLoja = execute(conn, "SELECT loja_id, cast(volume as float) as volume_sem_roll, cast(volume as float) as volume_com_roll FROM demanda d, loja_dia($dia_semana) l WHERE d.loja_id = l.id ORDER BY loja_id;") |> DataFrame;
    return VolumeLoja
end

function retorna_PesoLoja()
    dia_semana = retorna_DiaSemana()
    PesoLoja = execute(conn, "SELECT loja_id, cast(peso as float) as peso_sem_roll, cast(peso as float) as peso_com_roll FROM demanda d, loja_dia($dia_semana) l WHERE d.loja_id = l.id ORDER BY loja_id;") |> DataFrame; 
    return PesoLoja
end

function retorna_InfoCaminhao()
    InfoCaminhao = execute(conn, "SELECT caminhao.id, caminhao.placa, tipologia.nome FROM caminhoes_disponiveis() as caminhao, tipologia WHERE caminhao.tipologia_id = tipologia.id ORDER BY caminhao.id;") |> DataFrame; 
    return InfoCaminhao
end

function retorna_InfoCaminhaoTR()
    InfoCaminhao = execute(conn, "SELECT tipologia.id, tipologia.nome FROM tipologia ORDER BY tipologia.id;") |> DataFrame; 
    return InfoCaminhao
end

function retorna_VolumeCaminhao()
    VolumeCaminhao = execute(conn, "SELECT caminhao.id, caminhao.capacidade_volume FROM caminhoes_disponiveis() as caminhao, tipologia WHERE caminhao.tipologia_id = tipologia.id ORDER BY caminhao.id;") |> DataFrame;
    return VolumeCaminhao
end

function retorna_PesoCaminhao()
    PesoCaminhao = execute(conn, "SELECT caminhao.id, caminhao.capacidade_peso FROM caminhoes_disponiveis() as caminhao, tipologia WHERE caminhao.tipologia_id = tipologia.id ORDER BY caminhao.id;") |> DataFrame; 
    return PesoCaminhao
end

function retorna_Custo()
    dia_semana = retorna_DiaSemana()
    CaminhoesDisponiveis = execute(conn, "SELECT caminhao.id FROM caminhoes_disponiveis() caminhao ORDER BY caminhao.id;") |> DataFrame;
    query = "
    SELECT * FROM crosstab(
    'SELECT loja.id, caminhao.id, preco.valor
    FROM caminhoes_disponiveis() caminhao join preco on caminhao.tipologia_id = preco.tipologia_id join loja_dia($dia_semana) loja on preco.loja_id = loja.id
    ORDER BY loja.id, caminhao.id'
    ) as (loja_id varchar"
    for i in eachrow(CaminhoesDisponiveis)
        caminhao_id = i[1]
        query = query * ", \"$caminhao_id\" numeric"
    end
    query = query * ");"
    CustoFrete = execute(conn, query) |> DataFrame;
    return CustoFrete
end

function retorna_TRCusto()
    dia_semana = retorna_DiaSemana()
    CaminhoesDisponiveis = execute(conn, "SELECT tipologia.id FROM tipologia") |> DataFrame;
    query = "
    SELECT * FROM crosstab(
    'SELECT loja.id, tipologia.id, preco.valor
    FROM tipologia join preco on tipologia.id = preco.tipologia_id join loja_dia($dia_semana) loja on preco.loja_id = loja.id
    ORDER BY loja.id, tipologia.id'
    ) as (loja_id varchar"
    for i in eachrow(CaminhoesDisponiveis)
        caminhao_id = i[1]
        query = query * ", \"$caminhao_id\" numeric"
    end
    query = query * ");"
    CustoFrete = execute(conn, query) |> DataFrame;
    return CustoFrete
end

function retorna_TempoDescarregamento()
    dia_semana = retorna_DiaSemana()
    TempoDescarregamento = execute(conn, "SELECT *
    FROM crosstab(
    'SELECT id, chave, cast(valor as numeric) / 60
    FROM loja_dia($dia_semana), constantes
    WHERE (chave = ''descarregamento_granel'' or chave = ''descarregamento_roll'')
    ORDER BY 1,2;') as (id varchar, descarregamento_granel numeric, descarregamento_roll numeric);") |> DataFrame;
    return TempoDescarregamento
end

function retorna_TipologiaDisponivel()
    dia_semana = retorna_DiaSemana()
    CaminhoesDisponiveis = execute(conn, "SELECT caminhao.id FROM caminhoes_disponiveis() caminhao ORDER BY caminhao.id;") |> DataFrame;
    query = "SELECT *
    FROM crosstab('SELECT loja.id as loja_id, caminhao.id, case when tipologia.capacidade_volume <= cte.capacidade_volume then 1 else 0 end as aceita_caminhao
    FROM loja, tipologia,(SELECT loja.id as loja_id, capacidade_volume, tipologia.id as tipologia_id FROM loja_dia($dia_semana) loja, tipologia WHERE loja.tipologia_maxima = tipologia.id) cte, caminhoes_disponiveis() caminhao
    WHERE cte.loja_id = loja.id
    and tipologia.id = caminhao.tipologia_id
    ORDER BY 1, 2;
    ') as (loja_id varchar"
    for i in eachrow(CaminhoesDisponiveis)
        caminhao_id = i[1]
        query = query * ", \"$caminhao_id\" int"
    end
    query = query * ");"
    TipologiaDisponivel = execute(conn, query) |> DataFrame;
    return TipologiaDisponivel
end

function retorna_TRTipologiaDisponivel()
    dia_semana = retorna_DiaSemana()
    CaminhoesDisponiveis = execute(conn, "SELECT tipologia.id FROM tipologia ORDER BY id;") |> DataFrame;
    query = "SELECT *
    FROM crosstab('SELECT loja.id as loja_id, tipologia.id, case when tipologia.capacidade_volume <= cte.capacidade_volume then 1 else 0 end as aceita_caminhao
    FROM loja, tipologia,(SELECT loja.id as loja_id, capacidade_volume, tipologia.id as tipologia_id FROM loja_dia($dia_semana) loja, tipologia WHERE loja.tipologia_maxima = tipologia.id) cte
    WHERE cte.loja_id = loja.id
    ORDER BY 1, 2;
    ') as (loja_id varchar"
    for i in eachrow(CaminhoesDisponiveis)
        caminhao_id = i[1]
        query = query * ", \"$caminhao_id\" int"
    end
    query = query * ");"
    TipologiaDisponivel = execute(conn, query) |> DataFrame;
    return TipologiaDisponivel
end


function retorna_recebeRoll()
    dia_semana = retorna_DiaSemana()
    recebeRoll = execute(conn, "SELECT loja.id, case when (recebe_roll = false) then 1 when (loja.id = '0_CDRJ') then 1 else 0 end as recebe_granel
    ,case when (recebe_roll = true) then 1 when (loja.id = 'O_CDRJ') then 1 else 0 end as recebe_roll
    FROM loja_dia($dia_semana) loja ORDER BY loja.id;") |> DataFrame;
    return recebeRoll
end


function retorna_temPlataforma()
    temPlataforma = execute(conn, "SELECT caminhao.id, case when caminhao.tem_plataforma = true then 0 else 1 end as nao_tem_plataforma,
        case when caminhao.tem_plataforma = true then 1 else 0 end as tem_plataforma FROM caminhoes_disponiveis() caminhao, tipologia
    WHERE caminhao.tipologia_id = tipologia.id ORDER BY caminhao.id;") |> DataFrame;
    return temPlataforma
end

function retorna_TRtemPlataforma()
    temPlataforma = execute(conn, "SELECT id, case when tem_plataforma = true then 0 else 1 end as nao_tem_plataforma,
        case when tem_plataforma = true then 1 else 0 end as tem_plataforma FROM tipologia
        ORDER BY id;") |> DataFrame;
    return temPlataforma
end

function retorna_HoraIni()
    HoraIni = execute(conn, "SELECT horarios.id as horario_id, loja.id as loja_id, hora_inicial FROM horarios, loja, demanda
    WHERE horarios.loja_id = loja.id and horarios.dia = 1 and demanda.loja_id = loja.id ORDER BY loja_id;") |> DataFrame;
    return HoraIni
end

function retorna_HoraFim()
    HoraFim = execute(conn, "SELECT horarios.id as horario_id, loja.id as loja_id, hora_final FROM horarios, loja, demanda
    WHERE horarios.loja_id = loja.id and horarios.dia = 1 and demanda.loja_id = loja.id ORDER BY loja_id;") |> DataFrame;
    return HoraFim
end

function retorna_tempoLojaLoja()
    dia_semana = retorna_DiaSemana()
    LojasDisponiveis = execute(conn, "SELECT distinct loja.id FROM loja_dia($dia_semana) loja, distancia_lojas WHERE (loja.id IN (SELECT loja_a FROM distancia_lojas) OR loja.id IN (SELECT loja_b FROM distancia_lojas)) ORDER BY loja.id;") |> DataFrame;
    query = "SELECT * FROM crosstab('SELECT loja_a, loja_b, cast(tempo as numeric) / 60 FROM distancia_lojas ORDER BY 1,2')
    as (loja_a varchar"
    for i in eachrow(LojasDisponiveis)
        loja_id = i[1]
        query = query * ", \"$loja_id\" numeric"
    end
    query = query * ");"
    tempoLojaLoja = execute(conn, query) |> DataFrame;
    return tempoLojaLoja
end

function retorna_IDSaida()
    saida_id = execute(conn, "SELECT valor FROM constantes WHERE chave = 'execucao_id';") |> DataFrame;
    return saida_id
end

function retorna_TRVolume()
    TipologiaDF = execute(conn, "SELECT id, capacidade_volume FROM tipologia ORDER BY id;") |> DataFrame; 
    return TipologiaDF
end

function retorna_TRPeso()
    TipologiaDF = execute(conn, "SELECT id, capacidade_peso FROM tipologia ORDER BY id;") |> DataFrame; 
    return TipologiaDF
end

function retornaDescontoJornadaSeguinte()
    desconto_jornada_seguinte = execute(conn, "SELECT valor FROM constantes WHERE chave = 'desconto_da_jornada_seguinte';") |> DataFrame; 
    return desconto_jornada_seguinte[1, 1]
end

function retornaCarregamentoRoll()
    carregamento_roll = execute(conn, "SELECT valor FROM constantes WHERE chave = 'carregamento_roll';") |> DataFrame; 
    return carregamento_roll[1, 1]
end

function retornaCarregamentoGranel()
    carregamento_granel = execute(conn, "SELECT valor FROM constantes WHERE chave = 'carregamento_granel';") |> DataFrame; 
    return carregamento_granel[1, 1]
end

function retornaVolumeRollInterno()
    vol_roll_interno = execute(conn, "SELECT valor FROM constantes WHERE chave = 'vol_roll_interno';") |> DataFrame; 
    return vol_roll_interno[1, 1]
end

function retornaPercentualVolume()
    percentual_volume = execute(conn, "SELECT valor FROM constantes WHERE chave = 'percentual_volume';") |> DataFrame; 
    return percentual_volume[1, 1]
end

function retornaNumRotas()
    num_rotas = execute(conn, "SELECT valor FROM constantes WHERE chave = 'num_rotas';") |> DataFrame; 
    return num_rotas[1, 1]
end

function retornaJornadaMotorista()
    jornada_motorista = execute(conn, "SELECT valor FROM constantes WHERE chave = 'jornada_motorista';") |> DataFrame; 
    return jornada_motorista[1, 1]
end

function retornaDescarregamentoRoll()
    descarregamento_roll = execute(conn, "SELECT valor FROM constantes WHERE chave = 'descarregamento_roll';") |> DataFrame; 
    return descarregamento_roll[1, 1]
end

function retornaDescarregamentoGranel()
    descarregamento_granel = execute(conn, "SELECT valor FROM constantes WHERE chave = 'descarregamento_granel';") |> DataFrame; 
    return descarregamento_granel[1, 1]
end

function retornaVolumeRollExterno()
    vol_roll_externo = execute(conn, "SELECT valor FROM constantes WHERE chave = 'vol_roll_externo';") |> DataFrame; 
    return vol_roll_externo[1, 1]
end

function retornaPesoRoll()
    peso_roll = execute(conn, "SELECT valor FROM constantes WHERE chave = 'peso_roll';") |> DataFrame; 
    return peso_roll[1, 1]
end

function retornaCompartilha()
    compartilha = execute(conn, "SELECT valor FROM constantes WHERE chave = 'compartilha';") |> DataFrame; 
    return round(Int, number(compartilha[1, 1]))
end

function retorna_StatusTR()
    status_TR = execute(conn, "SELECT valor FROM constantes WHERE chave = 'status_tr';") |> DataFrame;
    return status_TR[1,1]
end

function insereNoBanco(df)
    execute(conn, "BEGIN")
    query = """INSERT INTO saida(execucao_id, data_entrega, loja, hora_recebimento, demanda_volume, demanda_peso, tipo_entrega, jornada, placa, tipologia, volume_entregue, peso_entregue, capacidade_volume, capacidade_peso, valor_frete, hora_saida, operacao)
               VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, \$11, \$12, \$13, \$14, \$15, \$16, 'D');"""
    LibPQ.load!(df, conn, query)
    execute(conn, "COMMIT;")
    return
end

function insereNoBancoTR(df)
    execute(conn, "BEGIN")
    query = """INSERT INTO saida(execucao_id, data_entrega, loja, hora_recebimento, demanda_volume, demanda_peso, tipo_entrega, jornada, caminhao_id, tipologia, volume_entregue, peso_entregue, capacidade_volume, capacidade_peso, valor_frete, hora_saida, operacao)
               VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, \$11, \$12, \$13, \$14, \$15, \$16, 'R');"""
    LibPQ.load!(df, conn, query)
    execute(conn, "COMMIT;")
    return
end

function atualizaExecucaoID()
    execute(conn, "BEGIN")
    atualizacao = "UPDATE constantes SET valor = valor + 1 WHERE chave = \'execucao_id\'"
    execute(conn, atualizacao)
    execute(conn, "COMMIT;")
    return
end
