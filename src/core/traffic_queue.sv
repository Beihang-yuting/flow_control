// src/core/traffic_queue.sv
`ifndef TRAFFIC_QUEUE_SV
`define TRAFFIC_QUEUE_SV

`include "traffic_model_base.sv"
`include "rate_model.sv"
`include "token_bucket_model.sv"
`include "burst_model.sv"
`include "random_model.sv"
`include "step_model.sv"

class traffic_queue;

    int                  queue_id;
    traffic_model_base   model;
    int                  prio;
    int                  weight;

    protected byte unsigned pkt_fifo[$][$];

    function new(int id);
        this.queue_id = id;
        this.model    = null;
        this.prio     = 0;
        this.weight   = 1;
    endfunction

    function void set_model(traffic_model_base m);
        this.model = m;
    endfunction

    function void push_packet(byte unsigned data[$]);
        pkt_fifo.push_back(data);
    endfunction

    function bit has_packet();
        return pkt_fifo.size() > 0;
    endfunction

    function int get_depth();
        return pkt_fifo.size();
    endfunction

    function void get_next_packet(output byte unsigned data[$]);
        if (pkt_fifo.size() > 0) begin
            data = pkt_fifo[0];
            pkt_fifo.delete(0);
        end else begin
            data = '{};
        end
    endfunction

    function int peek_next_size();
        if (pkt_fifo.size() > 0)
            return pkt_fifo[0].size();
        return 0;
    endfunction

    function void flush();
        pkt_fifo.delete();
    endfunction

endclass

`endif // TRAFFIC_QUEUE_SV
