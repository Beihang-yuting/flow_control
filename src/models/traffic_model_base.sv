// src/models/traffic_model_base.sv
`ifndef TRAFFIC_MODEL_BASE_SV
`define TRAFFIC_MODEL_BASE_SV

`include "flow_defines.sv"

virtual class traffic_model_base;

    traffic_model_type_e model_type;
    realtime             time_unit;    // configurable, default 1us

    function new();
        this.time_unit = 1us;
    endfunction

    // Returns the inter-packet gap (time to wait before sending next packet)
    // pkt_size: size of the packet about to be sent, in bytes
    // current_time: current simulation time
    pure virtual function realtime get_interval(int pkt_size, realtime current_time);

    // Reset internal state (e.g., token count, step index)
    pure virtual function void reset();

    // Human-readable description
    pure virtual function string to_string();

endclass

`endif // TRAFFIC_MODEL_BASE_SV
