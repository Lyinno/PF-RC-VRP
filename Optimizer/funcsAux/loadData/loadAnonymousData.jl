using PyCall

py"""
def txtToArray(testeTXT):
    indicesDF = []
    lines = testeTXT.split("\n")
    inicio = 0
    fim = 0
    for line in lines:
        if (line in ["Alis", "", "CUSTOMERS", "VEHICLES"])

"""

function nameTestes(tam, qtd, importar=-1)
    fileNames = []
    if (importar == -1)
        for i in 1:qtd
            push!(fileNames, "Teste_$(tam)_num$(i).txt")
        end
    else
        push!(fileNames, "Teste_$(tam)_num$(importar).txt")
    end
    return fileNames
end

function readTestesToDF(tam, qtd, importar=-1)
    fileNames = nameTestes(tam,qtd,importar)
    dfs = []

    for fn in fileNames
        pathToThisDir = pwd()
        pathToFn = pathToThisDir * "/artigo" * "/DatAnonymous/" * fn
        f = open(pathToFn, "r")
        testeTXT = read(f, String)


    end
    return dfs
end