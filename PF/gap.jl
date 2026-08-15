function calculate_gap(LB, UB)
    if UB === nothing
        return nothing
    end

    if abs(UB) <= 1e-9
        return abs(UB - LB) <= 1e-9 ? 0.0 : Inf
    end

    return 100 * (UB - LB) / abs(UB)
end