// test/test_port_shaper.sv
`include "core/port_shaper.sv"

program test_port_shaper;

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
        $display("=== test_port_shaper ===");

        begin
            port_shaper ps = new();
            bit ok;

            ps.port_rate_mbps   = 10000.0;
            ps.burst_size_bytes = 16000;
            ps.reset();

            ok = ps.can_send(1500, 0);
            check("shaper: first pkt can send", ok);
            ps.consume(1500, 0);

            for (int i = 0; i < 9; i++) begin
                ok = ps.can_send(1500, 0);
                if (ok) ps.consume(1500, 0);
            end

            ok = ps.can_send(1500, 0);
            check("shaper: blocked after burst exhausted", !ok);

            ok = ps.can_send(1500, 1us);
            check("shaper: can send after refill at 1us", ok);
        end

        begin
            port_shaper ps = new();
            realtime wt;

            ps.port_rate_mbps   = 1000.0;
            ps.burst_size_bytes = 0;
            ps.reset();

            wt = ps.get_wait_time(1500, 0);
            check("shaper: wait time ~12us at 1Gbps for 1500B",
                  wt > 11us && wt < 13us);
        end

        $display("\n=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TEST FAILED");
    end

endprogram
