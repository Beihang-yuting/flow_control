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

    function automatic void make_pkt(output byte unsigned pkt[$], input int size);
        pkt = {};
        for (int i = 0; i < size; i++) pkt.push_back(8'hAA);
    endfunction

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
            byte unsigned dummy[$];

            make_pkt(dummy, 64);

            q0.prio = 1;
            q1.prio = 3;
            q2.prio = 2;

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

        // ---- SP: all same priority picks first available ----
        begin
            scheduler sched = new();
            traffic_queue q0 = new(0);
            traffic_queue q1 = new(1);
            traffic_queue queues[int];
            byte unsigned dummy[$];
            int selected;

            make_pkt(dummy, 64);
            q0.prio = 5;
            q1.prio = 5;
            q0.push_packet(dummy);
            q1.push_packet(dummy);
            queues[0] = q0;
            queues[1] = q1;

            sched.mode = SCHED_STRICT_PRIORITY;
            selected = sched.select_queue(queues);
            check("sp: same priority returns a valid queue", selected == 0 || selected == 1);
        end

        // ---- WRR weight 3:1 ----
        begin
            scheduler sched = new();
            traffic_queue q0 = new(0);
            traffic_queue q1 = new(1);
            traffic_queue queues[int];
            int selected;
            byte unsigned pkt[$];
            int count0, count1;
            int total_iter;

            make_pkt(pkt, 1500);

            q0.weight = 3;
            q1.weight = 1;

            for (int i = 0; i < 200; i++) begin
                q0.push_packet(pkt);
                q1.push_packet(pkt);
            end

            queues[0] = q0;
            queues[1] = q1;

            sched.mode = SCHED_WRR;
            count0 = 0;
            count1 = 0;
            total_iter = 80;

            for (int i = 0; i < total_iter; i++) begin
                byte unsigned tmp[$];
                selected = sched.select_queue(queues);
                if (selected == 0) begin count0++; q0.get_next_packet(tmp); end
                else if (selected == 1) begin count1++; q1.get_next_packet(tmp); end
            end

            $display("  wrr 3:1 result: q0=%0d q1=%0d (expect ~60/20)", count0, count1);
            check("wrr: q0 gets ~75%", count0 >= 50 && count0 <= 70);
            check("wrr: q1 gets ~25%", count1 >= 10 && count1 <= 30);
        end

        // ---- WRR weight 1:1 (equal) ----
        begin
            scheduler sched = new();
            traffic_queue q0 = new(0);
            traffic_queue q1 = new(1);
            traffic_queue queues[int];
            int selected;
            byte unsigned pkt[$];
            int count0, count1;

            make_pkt(pkt, 1500);
            q0.weight = 1;
            q1.weight = 1;

            for (int i = 0; i < 100; i++) begin
                q0.push_packet(pkt);
                q1.push_packet(pkt);
            end

            queues[0] = q0;
            queues[1] = q1;
            sched.mode = SCHED_WRR;
            count0 = 0;
            count1 = 0;

            for (int i = 0; i < 40; i++) begin
                byte unsigned tmp[$];
                selected = sched.select_queue(queues);
                if (selected == 0) begin count0++; q0.get_next_packet(tmp); end
                else begin count1++; q1.get_next_packet(tmp); end
            end

            $display("  wrr 1:1 result: q0=%0d q1=%0d (expect ~20/20)", count0, count1);
            check("wrr_equal: q0 gets ~50%", count0 >= 15 && count0 <= 25);
            check("wrr_equal: q1 gets ~50%", count1 >= 15 && count1 <= 25);
        end

        // ---- WRR with 3 queues, weight 4:2:1 ----
        begin
            scheduler sched = new();
            traffic_queue q0 = new(0);
            traffic_queue q1 = new(1);
            traffic_queue q2 = new(2);
            traffic_queue queues[int];
            int selected;
            byte unsigned pkt[$];
            int count0, count1, count2;
            int total_iter;

            make_pkt(pkt, 1500);
            q0.weight = 4;
            q1.weight = 2;
            q2.weight = 1;

            for (int i = 0; i < 200; i++) begin
                q0.push_packet(pkt);
                q1.push_packet(pkt);
                q2.push_packet(pkt);
            end

            queues[0] = q0;
            queues[1] = q1;
            queues[2] = q2;
            sched.mode = SCHED_WRR;
            count0 = 0; count1 = 0; count2 = 0;
            total_iter = 70;

            for (int i = 0; i < total_iter; i++) begin
                byte unsigned tmp[$];
                selected = sched.select_queue(queues);
                if (selected == 0) begin count0++; q0.get_next_packet(tmp); end
                else if (selected == 1) begin count1++; q1.get_next_packet(tmp); end
                else if (selected == 2) begin count2++; q2.get_next_packet(tmp); end
            end

            $display("  wrr 4:2:1 result: q0=%0d q1=%0d q2=%0d (expect ~40/20/10)", count0, count1, count2);
            check("wrr_3q: q0 gets most", count0 > count1 && count0 > count2);
            check("wrr_3q: q1 gets more than q2", count1 > count2);
        end

        // ---- WRR: one queue drains, other continues ----
        begin
            scheduler sched = new();
            traffic_queue q0 = new(0);
            traffic_queue q1 = new(1);
            traffic_queue queues[int];
            int selected;
            byte unsigned pkt[$];
            int count0, count1;

            make_pkt(pkt, 1500);
            q0.weight = 1;
            q1.weight = 1;

            for (int i = 0; i < 5; i++) q0.push_packet(pkt);
            for (int i = 0; i < 50; i++) q1.push_packet(pkt);

            queues[0] = q0;
            queues[1] = q1;
            sched.mode = SCHED_WRR;
            count0 = 0; count1 = 0;

            for (int i = 0; i < 30; i++) begin
                byte unsigned tmp[$];
                selected = sched.select_queue(queues);
                if (selected < 0) break;
                if (selected == 0) begin count0++; q0.get_next_packet(tmp); end
                else begin count1++; q1.get_next_packet(tmp); end
            end

            check("wrr_drain: q0 sends all 5", count0 == 5);
            check("wrr_drain: q1 takes remainder", count1 > 5);
        end

        // ---- SP+WRR Mixed ----
        begin
            scheduler sched = new();
            traffic_queue q0 = new(0);
            traffic_queue q1 = new(1);
            traffic_queue q2 = new(2);
            traffic_queue queues[int];
            int selected;
            byte unsigned dummy[$];

            make_pkt(dummy, 64);

            q0.prio = 2;
            q1.prio = 0; q1.weight = 1;
            q2.prio = 0; q2.weight = 1;

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

        // ---- Mixed: SP queues always preempt WRR ----
        begin
            scheduler sched = new();
            traffic_queue q0 = new(0);
            traffic_queue q1 = new(1);
            traffic_queue q2 = new(2);
            traffic_queue queues[int];
            int selected;
            byte unsigned pkt[$];
            int sp_count, wrr_count;

            make_pkt(pkt, 64);
            q0.prio = 3;
            q1.prio = 1;
            q2.prio = 0; q2.weight = 1;

            for (int i = 0; i < 10; i++) begin
                q0.push_packet(pkt);
                q1.push_packet(pkt);
                q2.push_packet(pkt);
            end

            queues[0] = q0;
            queues[1] = q1;
            queues[2] = q2;
            sched.mode = SCHED_SP_WRR_MIXED;
            sp_count = 0; wrr_count = 0;

            for (int i = 0; i < 25; i++) begin
                byte unsigned tmp[$];
                selected = sched.select_queue(queues);
                if (selected < 0) break;
                if (selected == 0 || selected == 1) sp_count++;
                else wrr_count++;
                queues[selected].get_next_packet(tmp);
            end

            check("mixed_preempt: SP queues served first", sp_count == 20);
            check("mixed_preempt: WRR after SP drained", wrr_count == 5);
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

        // ---- Reset clears state ----
        begin
            scheduler sched = new();
            traffic_queue q0 = new(0);
            traffic_queue queues[int];
            byte unsigned pkt[$];
            int sel;

            make_pkt(pkt, 64);
            q0.weight = 1;
            q0.push_packet(pkt);
            queues[0] = q0;
            sched.mode = SCHED_WRR;
            sel = sched.select_queue(queues);

            sched.reset();
            q0.push_packet(pkt);
            sel = sched.select_queue(queues);
            check("reset: works after reset", sel == 0);
        end

        $display("\n=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TEST FAILED");
    end

endprogram
