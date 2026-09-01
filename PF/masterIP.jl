using JuMP
using HiGHS

function solve_master_integer(A, Ast, Custos; warmStart=nothing)
    R = axes(A,1)
    V = axes(A,2)
    S = 2:size(Ast,2)

    model = Model(HiGHS.Optimizer)
    set_silent(model)

    x = Dict{Tuple{Int,Int},VariableRef}()

    for r in R, v in V
        A[r,v] == 1 || continue

        var = @variable(model, binary=true, base_name="x_$(r)_$(v)")
        x[(r,v)] = var

        if warmStart !== nothing && haskey(warmStart, (r,v))
            set_start_value(var, warmStart[(r,v)])
        end
    end

    @constraint(model, atendimento[s in S], sum(Ast[r,s] * x[(r,v)] for r in R, v in V if haskey(x,(r,v))) == 1)
    @constraint(model, veiculo[v in V], sum(x[(r,v)] for r in R if haskey(x,(r,v))) <= 1)
    @objective(model, Min, sum(Custos[r,v] * x[(r,v)] for r in R, v in V if haskey(x,(r,v))))

    optimize!(model)
    return model, x
end

function get_ip_warm_start(modelIP, xIP)
    has_values(modelIP) || return nothing

    start = Dict{Tuple{Int,Int},Float64}()
    for (key,var) in xIP
        start[key] = value(var) > 0.5 ? 1.0 : 0.0
    end

    return start
end
