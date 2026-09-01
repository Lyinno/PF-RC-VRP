function calculate_gap(LB, UB)
    UB === nothing && return nothing
    abs(UB) <= 1e-9 && return abs(UB - LB) <= 1e-9 ? 0.0 : Inf
    return 100 * (UB - LB) / abs(UB)
end
