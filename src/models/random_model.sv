// src/models/random_model.sv
`ifndef RANDOM_MODEL_SV
`define RANDOM_MODEL_SV

`include "traffic_model_base.sv"

class random_model extends traffic_model_base;

    real           avg_rate_mbps;
    distribution_e dist_type;

    function new();
        super.new();
        this.model_type    = MODEL_RANDOM;
        this.avg_rate_mbps = 1000.0;
        this.dist_type     = DIST_UNIFORM;
    endfunction

    protected function real exp_random(real lambda);
        real u;
        u = $urandom_range(1, 1000000) / 1000000.0;
        return -$ln(u) / lambda;
    endfunction

    protected function real normal_random(real mean_val, real sigma);
        real u1, u2, z;
        u1 = $urandom_range(1, 1000000) / 1000000.0;
        u2 = $urandom_range(1, 1000000) / 1000000.0;
        z  = $sqrt(-2.0 * $ln(u1)) * $cos(2.0 * 3.14159265358979 * u2);
        return mean_val + sigma * z;
    endfunction

    virtual function realtime get_interval(int pkt_size, realtime current_time);
        real mean_gap_sec;
        real gap_sec;
        real rate_bps;

        rate_bps     = avg_rate_mbps * 1_000_000.0;
        if (rate_bps <= 0) return 0;
        mean_gap_sec = (pkt_size * 8.0) / rate_bps;

        case (dist_type)
            DIST_UNIFORM: begin
                real min_gap, max_gap, u;
                min_gap = mean_gap_sec * 0.5;
                max_gap = mean_gap_sec * 1.5;
                u       = $urandom_range(0, 1000000) / 1000000.0;
                gap_sec = min_gap + u * (max_gap - min_gap);
            end
            DIST_POISSON: begin
                real lambda;
                lambda  = 1.0 / mean_gap_sec;
                gap_sec = exp_random(lambda);
            end
            DIST_NORMAL: begin
                real sigma;
                sigma   = mean_gap_sec * 0.2;
                gap_sec = normal_random(mean_gap_sec, sigma);
                if (gap_sec < 0) gap_sec = mean_gap_sec * 0.1;
            end
            default: gap_sec = mean_gap_sec;
        endcase

        return gap_sec * 1s;
    endfunction

    virtual function void reset();
    endfunction

    virtual function string to_string();
        return $sformatf("random_model: avg_rate=%.1f Mbps, dist=%s", avg_rate_mbps, dist_type.name());
    endfunction

endclass

`endif // RANDOM_MODEL_SV
