using DataFrames
using CSV
using LibPQ
using Decimals
using StatsBase
using JuMP, Gurobi, HiGHS

include("testesViabi.jl")
include("preProcess.jl")
include("expVeic.jl")
include("formataResul.jl")
include("funcsAuxDoc.jl")
include("acessoBanco.jl")

function makeTable()
    (idLoja, idCaminhao, idHorario, nLojas, nLojasOri, nVeic, S, S_cd, V, G, dv, dp, rl, rv, cv, cvOriginal, cp, val, lt, ti, tf, te, td, tipo, tempoMaxMotor, tempoCarga, ExecucaoID, indexesLojasEx, dataData, infoCaminhao) = loadData("N", 10, [])
    idLojaAno = [index for (index, key) in enumerate(idLoja)]
    df = DataFrame(id_Client1=Int64[], id_Client2=Int64[], Distance=Float64[])    
    for i in 1:100
        for j in 1:100
            line = zeros(1,3)
            line[1] = i
            line[2] = j
            line[3] = td[i,j]
            push!(df,line)
        end
    end

    sAddressCode = pwd()
    sAddressCode = "$sAddressCode/"


    CSV.write("$sAddressCode/data.csv", df)

end

