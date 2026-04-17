// src/models/rate_model.sv
`ifndef RATE_MODEL_SV
`define RATE_MODEL_SV

`include "traffic_model_base.sv"

class rate_model extends traffic_model_base;

    real rate_mbps;

    function new();
        super.new();
        this.model_type = MODEL_RATE;
        this.rate_mbps  = 1000.0;
    endfunction

    // gap = (pkt_size_bytes * 8) / (rate_mbps * 1e6) seconds
    virtual function realtime get_interval(int pkt_size, realtime current_time);
        real bits;
        real rate_bps;
        bits     = pkt_size * 8.0;
        rate_bps = rate_mbps * 1_000_000.0;
        if (rate_bps <= 0) return 0;
        return (bits / rate_bps) * 1s;
    endfunction

    virtual function void reset();
    endfunction

    virtual function string to_string();
        return $sformatf("rate_model: rate=%.1f Mbps", rate_mbps);
    endfunction

endclass

`endif // RATE_MODEL_SV
