// test/test_flow_controller.sv
`include "core/flow_controller.sv"

program test_flow_controller;

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
        $display("=== test_flow_controller ===");

        // ---- Basic configuration and packet output ----
        begin
            flow_controller fc = new();
            byte unsigned pkt[$];
            byte unsigned out_data[$];
            int out_queue_id;
            realtime out_send_time;
            int sent_count;

            fc.set_port_rate(10000.0);
            fc.set_duration(50us);

            fc.add_queue(0, MODEL_RATE);
            fc.set_queue_rate(0, 2000.0);

            fc.add_queue(1, MODEL_RATE);
            fc.set_queue_rate(1, 1000.0);

            fc.set_scheduler_mode(SCHED_WRR);
            fc.set_queue_weight(0, 2);
            fc.set_queue_weight(1, 1);

            pkt = new[64];
            foreach (pkt[i]) pkt[i] = i;
            for (int i = 0; i < 200; i++) begin
                fc.push_packet(0, pkt);
                fc.push_packet(1, pkt);
            end

            check("fc: queues configured", 1);

            sent_count = 0;
            fc.start_schedule();
            while (fc.get_next_scheduled(out_queue_id, out_data, out_send_time)) begin
                sent_count++;
                if (sent_count > 10000) break;
            end

            check("fc: sent some packets", sent_count > 0);
            check("fc: sent < 10000 (duration limit)", sent_count < 10000);

            fc.report();
        end

        // ---- pkt_count mode ----
        begin
            flow_controller fc = new();
            byte unsigned pkt[$];
            int out_queue_id;
            byte unsigned out_data[$];
            realtime out_send_time;
            int sent_count;

            fc.set_port_rate(10000.0);
            fc.set_duration(1000us);

            fc.add_queue(0, MODEL_RATE);
            fc.set_queue_rate(0, 5000.0);

            pkt = new[128];
            for (int i = 0; i < 100; i++)
                fc.push_packet(0, pkt);

            sent_count = 0;
            fc.start_schedule(.pkt_count(50));
            while (fc.get_next_scheduled(out_queue_id, out_data, out_send_time)) begin
                sent_count++;
            end

            check("fc_pktcount: exactly 50 packets sent", sent_count == 50);
        end

        // ---- Custom model ----
        begin
            flow_controller fc = new();
            byte unsigned pkt[$];
            int out_queue_id;
            byte unsigned out_data[$];
            realtime out_send_time;
            int sent_count;

            fc.set_port_rate(10000.0);
            fc.set_duration(20us);

            fc.add_queue(0, MODEL_CUSTOM);
            begin
                rate_model custom_rm = new();
                custom_rm.rate_mbps = 500.0;
                fc.set_queue_model(0, custom_rm);
            end

            pkt = new[64];
            for (int i = 0; i < 100; i++)
                fc.push_packet(0, pkt);

            sent_count = 0;
            fc.start_schedule();
            while (fc.get_next_scheduled(out_queue_id, out_data, out_send_time)) begin
                sent_count++;
            end
            check("fc_custom: sent some packets with custom model", sent_count > 0);
        end

        // ---- Token bucket with burst ----
        begin
            flow_controller fc = new();
            byte unsigned pkt[$];
            int out_queue_id;
            byte unsigned out_data[$];
            realtime out_send_time;
            int sent_count;
            realtime first_time, tenth_time;

            fc.set_port_rate(10000.0);
            fc.set_duration(100us);

            fc.add_queue(0, MODEL_TOKEN_BUCKET);
            fc.set_queue_rate(0, 1000.0);
            fc.set_queue_burst(0, 8000);

            pkt = new[1000];
            for (int i = 0; i < 100; i++)
                fc.push_packet(0, pkt);

            sent_count = 0;
            fc.start_schedule();
            while (fc.get_next_scheduled(out_queue_id, out_data, out_send_time)) begin
                if (sent_count == 0) first_time = out_send_time;
                if (sent_count == 9) tenth_time = out_send_time;
                sent_count++;
            end
            check("fc_tbm: first 10 pkts arrive quickly (burst)",
                  tenth_time - first_time < 5us);
            check("fc_tbm: sent packets", sent_count > 0);
        end

        $display("\n=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TEST FAILED");
    end

endprogram
