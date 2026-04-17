// test/test_queue.sv
`include "core/traffic_queue.sv"

program test_queue;

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
        $display("=== test_queue ===");

        begin
            traffic_queue q = new(0);
            byte unsigned pkt1[$] = '{8'hAA, 8'hBB, 8'hCC};
            byte unsigned pkt2[$] = '{8'h11, 8'h22};
            byte unsigned out[$];

            check("queue: initially empty", !q.has_packet());
            check("queue: depth is 0", q.get_depth() == 0);

            q.push_packet(pkt1);
            check("queue: has packet after push", q.has_packet());
            check("queue: depth is 1", q.get_depth() == 1);

            q.push_packet(pkt2);
            check("queue: depth is 2", q.get_depth() == 2);

            q.get_next_packet(out);
            check("queue: first out is pkt1", out.size() == 3 && out[0] == 8'hAA);

            q.get_next_packet(out);
            check("queue: second out is pkt2", out.size() == 2 && out[0] == 8'h11);

            check("queue: empty after drain", !q.has_packet());
        end

        begin
            traffic_queue q = new(5);
            rate_model rm = new();
            rm.rate_mbps = 2000.0;
            q.set_model(rm);
            check("queue: model assigned", q.model != null);
            check("queue: queue_id is 5", q.queue_id == 5);
        end

        begin
            traffic_queue q = new(0);
            byte unsigned pkt[$] = '{8'h01, 8'h02, 8'h03, 8'h04};
            q.push_packet(pkt);
            check("queue: peek size is 4", q.peek_next_size() == 4);
        end

        begin
            traffic_queue q = new(0);
            byte unsigned pkt[$] = '{8'hFF};
            q.push_packet(pkt);
            q.push_packet(pkt);
            q.flush();
            check("queue: empty after flush", !q.has_packet());
        end

        $display("\n=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TEST FAILED");
    end

endprogram
