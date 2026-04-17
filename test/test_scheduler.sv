// test/test_scheduler.sv
`include "core/scheduler.sv"

program test_scheduler;

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
        $display("=== test_scheduler ===");

        // ---- Strict Priority ----
        begin
            scheduler sched = new();
            traffic_queue q0 = new(0);
            traffic_queue q1 = new(1);
            traffic_queue q2 = new(2);
            traffic_queue queues[int];
            int selected;
            byte unsigned dummy[$] = '{8'hFF};

            q0.priority = 1;
            q1.priority = 3;
            q2.priority = 2;

            q0.push_packet(dummy);
            q1.push_packet(dummy);
            q2.push_packet(dummy);

            queues[0] = q0;
            queues[1] = q1;
            queues[2] = q2;

            sched.mode = SCHED_STRICT_PRIORITY;
            selected = sched.select_queue(queues);
            check("sp: selects highest priority (q1)", selected == 1);

            q1.get_next_packet(dummy);
            selected = sched.select_queue(queues);
            check("sp: selects q2 after q1 empty", selected == 2);
        end

        // ---- WRR ----
        begin
            scheduler sched = new();
            traffic_queue q0 = new(0);
            traffic_queue q1 = new(1);
            traffic_queue queues[int];
            int selected;
            byte unsigned dummy[$] = '{8'hFF};
            int count0, count1;

            q0.weight = 3;
            q1.weight = 1;

            for (int i = 0; i < 100; i++) begin
                q0.push_packet(dummy);
                q1.push_packet(dummy);
            end

            queues[0] = q0;
            queues[1] = q1;

            sched.mode = SCHED_WRR;
            count0 = 0;
            count1 = 0;

            for (int i = 0; i < 40; i++) begin
                selected = sched.select_queue(queues);
                if (selected == 0) count0++;
                else count1++;
                if (selected == 0) begin byte unsigned tmp[$]; q0.get_next_packet(tmp); end
                else begin byte unsigned tmp[$]; q1.get_next_packet(tmp); end
            end

            check("wrr: q0 gets ~75%", count0 >= 25 && count0 <= 35);
            check("wrr: q1 gets ~25%", count1 >= 5 && count1 <= 15);
        end

        // ---- SP+WRR Mixed ----
        begin
            scheduler sched = new();
            traffic_queue q0 = new(0);
            traffic_queue q1 = new(1);
            traffic_queue q2 = new(2);
            traffic_queue queues[int];
            int selected;
            byte unsigned dummy[$] = '{8'hFF};

            q0.priority = 2;
            q1.priority = 0; q1.weight = 1;
            q2.priority = 0; q2.weight = 1;

            q0.push_packet(dummy);
            q1.push_packet(dummy);
            q2.push_packet(dummy);

            queues[0] = q0;
            queues[1] = q1;
            queues[2] = q2;

            sched.mode = SCHED_SP_WRR_MIXED;

            selected = sched.select_queue(queues);
            check("mixed: SP queue q0 first", selected == 0);

            q0.get_next_packet(dummy);
            selected = sched.select_queue(queues);
            check("mixed: WRR selects q1 or q2", selected == 1 || selected == 2);
        end

        // ---- No packets ----
        begin
            scheduler sched = new();
            traffic_queue queues[int];
            traffic_queue q0 = new(0);
            queues[0] = q0;
            sched.mode = SCHED_STRICT_PRIORITY;
            check("empty: returns -1", sched.select_queue(queues) == -1);
        end

        $display("\n=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TEST FAILED");
    end

endprogram
