// src/models/token_bucket_model.sv
`ifndef TOKEN_BUCKET_MODEL_SV
`define TOKEN_BUCKET_MODEL_SV

`include "traffic_model_base.sv"

class token_bucket_model extends traffic_model_base;

    real     rate_mbps;
    int      burst_size_bytes;
    real     tokens;
    realtime last_update_time;

    function new();
        super.new();
        this.model_type       = MODEL_TOKEN_BUCKET;
        this.rate_mbps        = 1000.0;
        this.burst_size_bytes = 4096;
        this.tokens           = 0;
        this.last_update_time = 0;
    endfunction

    protected function void refill(realtime current_time);
        real elapsed_sec;
        real new_tokens;
        if (current_time > last_update_time) begin
            elapsed_sec = (current_time - last_update_time) / 1s;
            new_tokens  = elapsed_sec * rate_mbps * 1_000_000.0 / 8.0;
            tokens      = tokens + new_tokens;
            if (tokens > burst_size_bytes)
                tokens = burst_size_bytes;
            last_update_time = current_time;
        end
    endfunction

    virtual function realtime get_interval(int pkt_size, realtime current_time);
        real deficit;
        real rate_bytes_per_sec;
        refill(current_time);
        if (tokens >= pkt_size) begin
            tokens -= pkt_size;
            return 0;
        end
        deficit           = pkt_size - tokens;
        rate_bytes_per_sec = rate_mbps * 1_000_000.0 / 8.0;
        if (rate_bytes_per_sec <= 0) return 0;
        tokens = 0;
        return (deficit / rate_bytes_per_sec) * 1s;
    endfunction

    virtual function void reset();
        tokens           = burst_size_bytes;
        last_update_time = 0;
    endfunction

    virtual function string to_string();
        return $sformatf("token_bucket_model: rate=%.1f Mbps, burst=%0d B", rate_mbps, burst_size_bytes);
    endfunction

endclass

`endif // TOKEN_BUCKET_MODEL_SV
