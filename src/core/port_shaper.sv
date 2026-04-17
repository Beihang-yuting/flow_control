// src/core/port_shaper.sv
`ifndef PORT_SHAPER_SV
`define PORT_SHAPER_SV

`include "flow_defines.sv"

class port_shaper;

    real     port_rate_mbps;
    int      burst_size_bytes;
    real     tokens;
    realtime last_update_time;

    function new();
        this.port_rate_mbps   = 10000.0;
        this.burst_size_bytes = 16000;
        this.tokens           = 0;
        this.last_update_time = 0;
    endfunction

    protected function void refill(realtime current_time);
        real elapsed_sec;
        real new_tokens;
        if (current_time > last_update_time) begin
            elapsed_sec = (current_time - last_update_time) / 1s;
            new_tokens  = elapsed_sec * port_rate_mbps * 1_000_000.0 / 8.0;
            tokens     += new_tokens;
            if (tokens > burst_size_bytes && burst_size_bytes > 0)
                tokens = burst_size_bytes;
            last_update_time = current_time;
        end
    endfunction

    function bit can_send(int pkt_size, realtime current_time);
        refill(current_time);
        return (tokens >= pkt_size);
    endfunction

    function void consume(int pkt_size, realtime current_time);
        refill(current_time);
        tokens -= pkt_size;
        if (tokens < 0) tokens = 0;
    endfunction

    function realtime get_wait_time(int pkt_size, realtime current_time);
        real deficit;
        real rate_bytes_per_sec;
        refill(current_time);
        if (tokens >= pkt_size) return 0;
        deficit           = pkt_size - tokens;
        rate_bytes_per_sec = port_rate_mbps * 1_000_000.0 / 8.0;
        if (rate_bytes_per_sec <= 0) return 0;
        return (deficit / rate_bytes_per_sec) * 1s;
    endfunction

    function void reset();
        tokens           = burst_size_bytes;
        last_update_time = 0;
    endfunction

endclass

`endif // PORT_SHAPER_SV
