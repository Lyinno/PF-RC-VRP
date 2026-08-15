using DataFrames
using CSV
using LibPQ
using Decimals
using StatsBase
using JuMP, Gurobi, HiGHS, Pkg
using PyCall

py"""
import pandas

def write_txt(data_csv, name, mode, title, sub):
    data = pandas.read_table(data_csv)

    df = pandas.DataFrame(data)

    df_str = df.to_string(index=False, justify='center')

    with open(name, mode) as file:
        if title != "F":
            file.write(title+"\n\n")
        if sub != "F":
            file.write(sub+"\n")
        lines = df_str.split("\n")
        for line in lines:
            file.write(line[1:]+"\n")
        file.write("\n")
"""

path = pwd()

include("$(path)/artigo/Optimizer/funcsAux/loadData/loadData.jl")

# function tipoAnonimizado(tipo2, qtd, rl, rv, cp, cv, dp, dv, S, V)
#     tipoAnoAux11 = sample(S, qtd, replace=true)
#     tipoAnoAux21 = sample(V, qtd, replace=true)
#     tipoAno1 = tipo2[tipoAnoAux11,tipoAnoAux21]
#     tipoAnoAux12 = sample(S, qtd, replace=true)
#     tipoAnoAux22 = sample(V, qtd, replace=true)
#     tipoAno2 = tipo2[tipoAnoAux12,tipoAnoAux22]
#     tipoAnoDef = zeros(qtd,qtd)
#     for i in 1:qtd
#         for j in 1:qtd
#             randomChoice = rand()
#             if randomChoice < 0.5
#                 tipoAnoDef[i,j] = tipoAno1[i,j]
#             else
#                 tipoAnoDef[i,j] = tipoAno2[i,j]
#             end
#             if rl[]
#         end
#     end
# end

sAddressCode = pwd()
sAddressCode = "$sAddressCode/"

StatusTr = number(retorna_StatusTR()) 
(idLoja, idCaminhao, idHorario, nLojas, nLojasOri, nVeic, S, S_cd, V, G, dv, dp, rl, rv, cv, cvOriginal, cp, val, lt, ti, tf, te, td, tipo, tempoMaxMotor, tempoCarga, ExecucaoID, indexesLojasEx, dataData, infoCaminhao, tipo2) = loadData("N", 10, [])

modKg = (1+randn()/5)
modVol = (1+randn()/5)
modVal = (1+randn()/5)
modTime = 1

dv *= modVol
cv *= modVol
dp *= modKg
cp *= modKg
val *= modVal
td *= modTime


dv = [(1+randn()/5)*i for i in dv]
cv = [(1+randn()/5)*i for i in cv]
dp = [(1+randn()/5)*i for i in dp]
cp = [(1+randn()/5)*i for i in cp]
tdRuido = zeros(size(td))
for i in 1:size(td)[1]
    for j in 1:size(td)[2]
        tdRuido[i,j] = td[i,j]*(1+randn()/5)
    end
end
td = tdRuido

for i in 1:size(val)[1]
    for j in 1:size(val)[2]
        val[i,j] *= rand()
    end
end

for i in 1:size(td)[1]
    for j in 1:size(td)[2]
        td[i,j] *= rand()
    end
end

td = round.(td, digits=2)
val = round.(val, digits=2)
cp = round.(cp, digits=2)
dp = round.(dp, digits=2)
cv = round.(cv, digits=2)
dv = round.(dv, digits=2)

for n in 1:4
    for i in [50, 100, 200]
        tipoAno = ones(i,i)

        arquivo = open("Teste_$(i)_num$(n).csv", "w")
        caminho_arquivo = "Teste_$(i)_num$(n).csv"
        veicsSample = sample(V,i,replace=true)
        lojasSample = sample(S,i,replace=true)
        # tpSample1 = sample(S,i,replace=true)
        # tpSample2 = sample(V,i,replace=true)
        # tpSample = tp
        
        tdSample = td[lojasSample,lojasSample]
        valSample = val[lojasSample,veicsSample]
        cpSample = cp[veicsSample]
        dpSample = dp[lojasSample]
        cvSample = cv[veicsSample]
        dvSample = dv[lojasSample]

        for s in 1:i
            for v in 1:i
                if (rand() >=0.8 || dpSample[s] > cpSample[v] || dvSample[s] > cvSample[v]) && (s!=1)
                    tipoAno[s,v] = 0
                end
            end
        end

        valSample[1,:] = zeros(i)
        for lis in [dpSample, dvSample]
            lis[1] = 0
        end
        for si in 1:size(tdSample)[1]
            for sj in 1:size(tdSample)[2]
                if si != sj && tdSample[si, sj] == 0
                    tdSample[si, sj] += 0.15
                end
                if si == sj && tdSample[si,sj] != 0
                    tdSample[si,sj] = 0
                end
            end
        end

        for s in 1:i
            for v in 1:i
                if tipoAno[s,v] == 0
                    valSample[s,v] = Inf
                end
            end
        end

        lojas = [l for l in 1:i]
        lojas2 = [l for l in 1:i]
        veics = [v for v in 1:i]
        distancias = [tdSample[l1,l2] for l1 in lojas for l2 in lojas2]
        coluna1 = [l for l in lojas for _ in 1:i]
        coluna2 = [l for _ in 1:i for l in lojas]
        colunaValor1 = [l for l in lojas for _ in 1:i]
        colunaValor2 = [v for _ in 1:i for v in veics]
        valor = [valSample[l,v] for l in lojas for v in veics]

        df = DataFrame(store1=coluna1, store2=coluna2, tempo_deslocamento=distancias)
        CSV.write(caminho_arquivo, df, delim = '\t', header = true, append = true)
        py"write_txt"("Teste_$(i)_num$(n).csv", "$(path)/artigo/DatAnonymous/Teste_$(i)_num$(n).txt", "w", "Alis", "CUSTOMERS")

        df = DataFrame(store=lojas, demanda_peso=dpSample, demanda_volume=dvSample)
        CSV.write(caminho_arquivo, df, delim = '\t', header = true)
        py"write_txt"("Teste_$(i)_num$(n).csv", "$(path)/artigo/DatAnonymous/Teste_$(i)_num$(n).txt", "a", "F", "F")
        
        df = DataFrame(vehicles=veics, capacidade_peso=cpSample, capacidade_volume=cvSample)
        CSV.write(caminho_arquivo, df, delim = '\t', header = true)
        py"write_txt"("Teste_$(i)_num$(n).csv", "$(path)/artigo/DatAnonymous/Teste_$(i)_num$(n).txt", "a", "F", "VEHICLES")
        
        df = DataFrame(store=colunaValor1, vehicle=colunaValor2, valor_frete=valor)
        CSV.write(caminho_arquivo, df, delim = '\t', header = true)
        py"write_txt"("Teste_$(i)_num$(n).csv", "$(path)/artigo/DatAnonymous/Teste_$(i)_num$(n).txt", "a", "F", "F")

        rm(caminho_arquivo)
    end
end

