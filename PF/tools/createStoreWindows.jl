using Random
using Printf

const INTERVALOS_RECEBIMENTO = [
    (7.0, 11.0),
    (7.5, 11.5),
    (8.0, 12.0),
    (8.0, 13.0),
    (8.0, 14.0),
    (8.5, 12.5),
    (9.0, 12.0),
    (9.0, 13.0),
    (9.0, 14.0),
    (9.0, 15.0),
    (9.0, 17.0),
    (10.0, 14.0),
    (10.0, 16.0),
    (11.0, 15.0),
    (12.0, 16.0),
    (12.0, 17.0),
    (13.0, 17.0),
    (13.0, 18.0),
    (14.0, 18.0),
    (8.0, 17.0),
    (9.0, 18.0)
]

function gerar_janelas_recebimento(n::Int; nome_arquivo::String = "janelas_recebimento.txt", seed = nothing)
    if seed !== nothing
        Random.seed!(seed)
    end

    open(nome_arquivo, "w") do arquivo

        println(arquivo, "TIME_WINDOWS")
        println(arquivo, "loja    horario_inicio    horario_fim")

        for loja in 1:n
            inicio, fim = rand(INTERVALOS_RECEBIMENTO)

            @printf(
                arquivo,
                "%4d       %6.2f       %6.2f\n",
                loja,
                inicio,
                fim
            )
        end
    end

    println("Janelas de recebimento geradas para $n lojas.")
    println("Arquivo: $nome_arquivo")
end

for i in [50, 100, 200]
    for j in 1:4
        gerar_janelas_recebimento(i; nome_arquivo = "C:\\Users\\avell\\OneDrive\\Documentos\\GitHub\\PF-RC-VRP\\DatAnonymous\\janelas_$(i)_$(j)lojas.txt", seed = 100*i+j*10)
    end
end