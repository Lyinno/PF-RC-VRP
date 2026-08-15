using JuMP
using HiGHS
import MathOptInterface as MOI

function solve_master_lp(A, Ast, Custos)
    R = axes(A, 1)
    V = axes(A, 2)
    S = 2:size(Ast, 2)

    model = Model(HiGHS.Optimizer)
    set_silent(model)

    @variable(model, x[R, V] >= 0)

    # Se o veiculo não pode atender a rota, x[r,v] tem que ser 0
    for r in R, v in V
        if A[r,v] == 0
            fix(x[r,v], 0.0; force=true)
        end
    end

    # Toda loja tem que pertencer a uma e somente uma rota atendida por algum veiculo
    @constraint(model, atendimento[s in S], sum(Ast[r,s] * x[r,v] for r in R, v in V) == 1)
    # Aqui x <= 1, ou seja, x pertence ao intervalo [0, 1] não necessariamente inteiro
    @constraint(model, veiculo[v in V], sum(x[r,v] for r in R) <= 1)

    @objective(model, Min, sum(Custos[r,v] * x[r,v] for r in R, v in V if A[r,v] == 1))

    optimize!(model)

    return model, x, atendimento, veiculo
end


function solve_master_integer(A, Ast, Custos)
    R = axes(A, 1)
    V = axes(A, 2)
    S = 2:size(Ast, 2)

    model = Model(HiGHS.Optimizer)
    set_silent(model)

    @variable(model, x[R, V], Bin)

    for r in R, v in V
        if A[r,v] == 0
            fix(x[r,v], 0.0; force=true)
        end
    end

    @constraint(model, atendimento[s in S], sum(Ast[r,s] * x[r,v] for r in R, v in V) == 1)
    @constraint(model, veiculo[v in V], sum(x[r,v] for r in R) <= 1)

    @objective(model, Min, sum(Custos[r,v] * x[r,v] for r in R, v in V if A[r,v] == 1))

    optimize!(model)

    return model, x
end
