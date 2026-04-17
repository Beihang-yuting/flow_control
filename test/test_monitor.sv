// test/test_monitor.sv
`include "monitor/traffic_monitor.sv"

program test_monitor;

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

    initial begin
        $display("=== test_monitor ===");

        begin
            traffic_monitor mon = new();
            queue_stats_t stats;

            mon.window_size    = 10us;
            mon.tolerance_pct  = 5.0;

            mon.register_queue(0, 1000.0);

            for (int i = 0; i < 12; i++) begin
                mon.record(0, 1000, i * 8us);
            end

            mon.finalize(100us);
            stats = mon.get_stats(0);

            check("monitor: total_packets = 12", stats.total_packets == 12);
            check("monitor: total_bytes = 12000", stats.total_bytes == 12000);
            check("monitor: actual rate ~960Mbps",
                  stats.actual_rate_mbps > 900.0 && stats.actual_rate_mbps < 1100.0);
            check("monitor: deviation < 10%",
                  stats.deviation_pct > -10.0 && stats.deviation_pct < 10.0);
        end

        begin
            traffic_monitor mon = new();
            queue_stats_t s0, s1;

            mon.window_size   = 10us;
            mon.tolerance_pct = 5.0;
            mon.register_queue(0, 1000.0);
            mon.register_queue(1, 500.0);

            for (int i = 0; i < 10; i++)
                mon.record(0, 1000, i * 8us);

            for (int i = 0; i < 5; i++)
                mon.record(1, 1000, i * 16us);

            mon.finalize(80us);
            s0 = mon.get_stats(0);
            s1 = mon.get_stats(1);

            check("monitor_multi: q0 pkts=10", s0.total_packets == 10);
            check("monitor_multi: q1 pkts=5", s1.total_packets == 5);
            check("monitor_multi: q0 rate > q1 rate",
                  s0.actual_rate_mbps > s1.actual_rate_mbps);
        end

        begin
            traffic_monitor mon = new();
            mon.debug_level = 2;
            mon.register_queue(0, 1000.0);
            mon.record(0, 1500, 10us);
            mon.record(0, 1500, 20us);
            mon.finalize(30us);
            check("monitor_debug: no crash with debug_level=2", 1);
        end

        $display("\n=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TEST FAILED");
    end

endprogram
