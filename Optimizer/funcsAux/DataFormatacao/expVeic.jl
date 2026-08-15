# função para multiplicar o numero de linhas e colunas de uma matriz, duplicando elas n vezes
# "nficar" = multiplicar por n vezes
# n = numero de vezes que sera nficada, m = matriz, hv = 1 se a matriz tiver que ser nficada verticalmente, e qualquer outro valor se for horizontalmente
function nFicaMatrix(n, m, hv)
    nm = m #variavel que ira guardar a nova matriz com linhas e/ou colunas nficadas 
    om = m #variavel para guardar a matriz original 
    for i in range(1, n-1) 
        if hv == 1
            nm = vcat(nm, om)
        else
            nm = hcat(nm, om)
        end        
    end
    return nm
end


