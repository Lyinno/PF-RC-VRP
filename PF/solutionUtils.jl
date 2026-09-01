using JuMP

function get_integer_solution(x, rotas)
    selecionadas = []

    for ((r,v),var) in x
        if value(var) > 0.5
            push!(selecionadas, (rota_index=r, veiculo=v, rota=rotas[r]))
        end
    end

    sort!(selecionadas, by=x -> x.veiculo)
    return selecionadas
end
