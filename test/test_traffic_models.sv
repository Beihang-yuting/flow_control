// test/test_traffic_models.sv
`include "models/rate_model.sv"
`include "models/token_bucket_model.sv"
`include "models/burst_model.sv"
`include "models/random_model.sv"
`include "models/step_model.sv"

program test_traffic_models;

    int pass_count = 0;
    int fail_count = 0;

    task automatic check(string name, bit condition);
        if (condition) begin
            $display("[PASS] %s", name);
            pass_count++;
        end else begin
            $display("[FAIL] %s", name);
            fail_count++;
        end
    endtask

    function automatic bit time_close(realtime actual, realtime expected, real tol_pct);
        real diff;
        if (expected == 0) return (actual == 0);
        diff = (actual - expected) / expected * 100.0;
        if (diff < 0) diff = -diff;
        return (diff < tol_pct);
    endfunction

    initial begin
        $display("=== test_traffic_models ===");

        // ---- rate_model tests ----
        begin
            rate_model rm = new();
            realtime gap;

            rm.rate_mbps = 1000.0;
            rm.reset();
            gap = rm.get_interval(1000, 0);
            check("rate_model: 1Gbps 1000B gap ~8us", time_close(gap, 8us, 1.0));

            rm.rate_mbps = 10000.0;
            rm.reset();
            gap = rm.get_interval(64, 0);
            check("rate_model: 10Gbps 64B gap ~51.2ns", time_close(gap, 51.2ns, 1.0));

            gap = rm.get_interval(1500, 0);
            check("rate_model: 10Gbps 1500B gap ~1.2us", time_close(gap, 1.2us, 1.0));
        end

        // ---- token_bucket_model tests ----
        begin
            token_bucket_model tbm = new();
            realtime gap;

            tbm.rate_mbps        = 1000.0;
            tbm.burst_size_bytes = 8000;
            tbm.reset();

            gap = tbm.get_interval(1000, 0);
            check("tbm: first pkt gap is 0 (burst)", gap == 0);

            for (int i = 1; i < 8; i++) begin
                gap = tbm.get_interval(1000, 0);
            end
            gap = tbm.get_interval(1000, 0);
            check("tbm: gap > 0 after burst exhausted", gap > 0);

            tbm.reset();
            gap = tbm.get_interval(1000, 0);
            check("tbm: gap is 0 after reset", gap == 0);
        end

        // ---- burst_model tests ----
        begin
            burst_model bm = new();
            realtime gap;

            bm.send_count   = 3;
            bm.pause_time   = 100ns;
            bm.reset();

            gap = bm.get_interval(100, 0);
            check("burst: pkt 1 gap=0", gap == 0);
            gap = bm.get_interval(100, 0);
            check("burst: pkt 2 gap=0", gap == 0);
            gap = bm.get_interval(100, 0);
            check("burst: pkt 3 gap=0", gap == 0);

            gap = bm.get_interval(100, 0);
            check("burst: pkt 4 gap=100ns (pause)", time_close(gap, 100ns, 1.0));

            gap = bm.get_interval(100, 0);
            check("burst: pkt 5 gap=0 (new burst)", gap == 0);
        end

        // ---- random_model tests ----
        begin
            random_model rm_rand = new();
            realtime gap;
            realtime total_gap;
            int num_samples;

            rm_rand.avg_rate_mbps = 1000.0;
            rm_rand.dist          = DIST_UNIFORM;
            rm_rand.reset();

            gap = rm_rand.get_interval(1000, 0);
            check("random_uniform: gap > 0", gap > 0);

            total_gap = 0;
            num_samples = 100;
            rm_rand.reset();
            for (int i = 0; i < num_samples; i++) begin
                total_gap += rm_rand.get_interval(1000, 0);
            end
            begin
                real avg_gap_ns;
                avg_gap_ns = total_gap / num_samples / 1ns;
                check("random_uniform: avg gap within 30% of 8us",
                      avg_gap_ns > 5600.0 && avg_gap_ns < 10400.0);
            end

            rm_rand.dist = DIST_POISSON;
            rm_rand.reset();
            gap = rm_rand.get_interval(1000, 0);
            check("random_poisson: gap > 0", gap > 0);

            rm_rand.dist = DIST_NORMAL;
            rm_rand.reset();
            gap = rm_rand.get_interval(1000, 0);
            check("random_normal: gap > 0", gap > 0);
        end

        // ---- step_model tests ----
        begin
            step_model sm = new();
            realtime gap;
            step_cfg_t steps[$];

            steps.push_back('{duration: 10us, rate_mbps: 1000.0});
            steps.push_back('{duration: 10us, rate_mbps: 500.0});
            sm.steps = steps;
            sm.reset();

            gap = sm.get_interval(1000, 0);
            check("step: t=0 gap ~8us (1Gbps)", time_close(gap, 8us, 1.0));

            gap = sm.get_interval(1000, 11us);
            check("step: t=11us gap ~16us (500Mbps)", time_close(gap, 16us, 1.0));

            gap = sm.get_interval(1000, 25us);
            check("step: t=25us past end gap=0", gap == 0);

            sm.loop_enable = 1;
            sm.reset();
            gap = sm.get_interval(1000, 21us);
            check("step: t=21us loop back to 1Gbps gap ~8us", time_close(gap, 8us, 1.0));
        end

        $display("\n=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TEST FAILED");
    end

endprogram
