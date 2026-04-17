// src/models/burst_model.sv
`ifndef BURST_MODEL_SV
`define BURST_MODEL_SV

`include "traffic_model_base.sv"

class burst_model extends traffic_model_base;

    int      send_count;
    realtime pause_time;
    int      sent_in_burst;

    function new();
        super.new();
        this.model_type    = MODEL_BURST;
        this.send_count    = 10;
        this.pause_time    = 100ns;
        this.sent_in_burst = 0;
    endfunction

    virtual function realtime get_interval(int pkt_size, realtime current_time);
        sent_in_burst++;
        if (sent_in_burst <= send_count) begin
            return 0;
        end else begin
            sent_in_burst = 1;
            return pause_time;
        end
    endfunction

    virtual function void reset();
        sent_in_burst = 0;
    endfunction

    virtual function string to_string();
        return $sformatf("burst_model: send=%0d, pause=%0t", send_count, pause_time);
    endfunction

endclass

`endif // BURST_MODEL_SV
