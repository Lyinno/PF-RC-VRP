using JuMP
using HiGHS

mutable struct MasterLPState
    model::Model
    x::Dict{Tuple{Int,Int},VariableRef}
    atendimento::Dict{Int,ConstraintRef}
    veiculo::Dict{Int,ConstraintRef}
    n_routes::Int
    n_vehicles::Int
    n_stores::Int
end

function create_master_lp(A, Ast, Custos)
    R = axes(A,1)
    V = axes(A,2)
    S = 2:size(Ast,2)

    model = Model(HiGHS.Optimizer)
    set_silent(model)

    x = Dict{Tuple{Int,Int},VariableRef}()

    for r in R, v in V
        A[r,v] == 1 || continue
        x[(r,v)] = @variable(model, lower_bound=0.0, base_name="x_$(r)_$(v)")
    end

    atendimento = Dict{Int,ConstraintRef}()
    for s in S
        atendimento[s] = @constraint(model, sum(Ast[r,s] * x[(r,v)] for r in R, v in V if haskey(x,(r,v))) == 1)
    end

    veiculo = Dict{Int,ConstraintRef}()
    for v in V
        veiculo[v] = @constraint(model, sum(x[(r,v)] for r in R if haskey(x,(r,v))) <= 1)
    end

    @objective(model, Min, sum(Custos[r,v] * x[(r,v)] for r in R, v in V if haskey(x,(r,v))))

    return MasterLPState(model, x, atendimento, veiculo, size(A,1), size(A,2), size(Ast,2))
end

function solve_master_lp!(state)
    optimize!(state.model)
    return state.model
end

function add_route_to_master_lp!(state, novaA, novaAst, novosCustos)
    state.n_routes += 1
    r = state.n_routes

    for v in 1:state.n_vehicles
        novaA[v] == 1 || continue

        var = @variable(state.model, lower_bound=0.0, base_name="x_$(r)_$(v)")
        state.x[(r,v)] = var
        set_objective_coefficient(state.model, var, novosCustos[v])

        for s in 2:state.n_stores
            novaAst[s] == 0 && continue
            set_normalized_coefficient(state.atendimento[s], var, novaAst[s])
        end

        set_normalized_coefficient(state.veiculo[v], var, 1.0)
    end

    return r
end

function get_master_lp_duals(state)
    pi = zeros(Float64, state.n_stores)
    alpha = zeros(Float64, state.n_vehicles)

    for s in 2:state.n_stores
        pi[s] = dual(state.atendimento[s])
    end

    for v in 1:state.n_vehicles
        alpha[v] = dual(state.veiculo[v])
    end

    return pi, alpha
end
