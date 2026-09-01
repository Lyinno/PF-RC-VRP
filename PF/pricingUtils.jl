function wait_for_available_memory(minFreeRamGB)
    minFreeBytes = minFreeRamGB * 1024^3

    while Sys.free_memory() < minFreeBytes
        sleep(0.1)
    end
end

route_key(rota) = Tuple(sort(unique(rota[2:end-1])))
