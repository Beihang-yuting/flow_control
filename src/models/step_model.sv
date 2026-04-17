// src/models/step_model.sv
`ifndef STEP_MODEL_SV
`define STEP_MODEL_SV

`include "traffic_model_base.sv"

class step_model extends traffic_model_base;

    step_cfg_t steps[$];
    bit        loop_enable;

    function new();
        super.new();
        this.model_type  = MODEL_STEP;
        this.loop_enable = 0;
    endfunction

    protected function real get_active_rate(realtime current_time);
        realtime elapsed;
        realtime total_duration;
        realtime step_start;

        total_duration = 0;
        foreach (steps[i]) total_duration += steps[i].duration;

        if (total_duration == 0) return 0;

        elapsed = current_time;

        if (loop_enable && elapsed >= total_duration) begin
            while (elapsed >= total_duration)
                elapsed -= total_duration;
        end

        step_start = 0;
        foreach (steps[i]) begin
            if (elapsed >= step_start && elapsed < step_start + steps[i].duration)
                return steps[i].rate_mbps;
            step_start += steps[i].duration;
        end

        return 0;
    endfunction

    virtual function realtime get_interval(int pkt_size, realtime current_time);
        real rate_mbps_now;
        real bits;
        real rate_bps;

        rate_mbps_now = get_active_rate(current_time);
        if (rate_mbps_now <= 0) return 0;

        bits     = pkt_size * 8.0;
        rate_bps = rate_mbps_now * 1_000_000.0;
        return (bits / rate_bps) * 1s;
    endfunction

    virtual function void reset();
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("step_model: %0d steps, loop=%0b", steps.size(), loop_enable);
        foreach (steps[i])
            s = {s, $sformatf("\n  [%0d] dur=%0t rate=%.1f Mbps", i, steps[i].duration, steps[i].rate_mbps)};
        return s;
    endfunction

endclass

`endif // STEP_MODEL_SV
