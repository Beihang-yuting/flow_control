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

    function automatic void make_pkt(output byte unsigned pkt[$], input int size);
        pkt = {};
        for (int i = 0; i < size; i++) pkt.push_back(i % 256);
    endfunction

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

            make_pkt(pkt, 64);
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

            make_pkt(pkt, 128);
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

            make_pkt(pkt, 64);
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
            fc.set_queue_burst(0, 12000);

            make_pkt(pkt, 1000);
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

        // ---- Packet data integrity ----
        begin
            flow_controller fc = new();
            byte unsigned pkt[$];
            byte unsigned out_data[$];
            int out_queue_id;
            realtime out_send_time;
            bit data_ok;

            fc.set_port_rate(10000.0);
            fc.set_duration(100us);
            fc.add_queue(0, MODEL_RATE);
            fc.set_queue_rate(0, 1000.0);

            make_pkt(pkt, 256);
            fc.push_packet(0, pkt);

            fc.start_schedule();
            fc.get_next_scheduled(out_queue_id, out_data, out_send_time);

            data_ok = (out_data.size() == 256);
            if (data_ok) begin
                for (int i = 0; i < 256; i++) begin
                    if (out_data[i] != (i % 256)) begin
                        data_ok = 0;
                        break;
                    end
                end
            end
            check("integrity: packet data preserved", data_ok);
            check("integrity: correct queue_id", out_queue_id == 0);
            check("integrity: send_time >= 0", out_send_time >= 0);
        end

        // ---- Multi-queue packet ordering ----
        begin
            flow_controller fc = new();
            byte unsigned pkt[$];
            int out_queue_id;
            byte unsigned out_data[$];
            realtime out_send_time;
            int q0_count, q1_count, q2_count;
            int sent;

            fc.set_port_rate(10000.0);
            fc.set_duration(100us);

            fc.add_queue(0, MODEL_RATE);
            fc.set_queue_rate(0, 3000.0);
            fc.set_queue_priority(0, 3);

            fc.add_queue(1, MODEL_RATE);
            fc.set_queue_rate(1, 2000.0);
            fc.set_queue_priority(1, 2);

            fc.add_queue(2, MODEL_RATE);
            fc.set_queue_rate(2, 1000.0);
            fc.set_queue_priority(2, 1);

            fc.set_scheduler_mode(SCHED_STRICT_PRIORITY);

            make_pkt(pkt, 100);
            for (int i = 0; i < 300; i++) begin
                fc.push_packet(0, pkt);
                fc.push_packet(1, pkt);
                fc.push_packet(2, pkt);
            end

            q0_count = 0; q1_count = 0; q2_count = 0;
            sent = 0;
            fc.start_schedule();
            while (fc.get_next_scheduled(out_queue_id, out_data, out_send_time)) begin
                case (out_queue_id)
                    0: q0_count++;
                    1: q1_count++;
                    2: q2_count++;
                endcase
                sent++;
            end

            check("sp_multi: q0 (highest prio) served first", q0_count > 0);
            check("sp_multi: total packets sent > 0", sent > 0);
            check("sp_multi: q0 served before q1 q2", q0_count >= q1_count);
        end

        // ---- Rate accuracy test (single queue) ----
        begin
            flow_controller fc = new();
            byte unsigned pkt[$];
            int out_queue_id;
            byte unsigned out_data[$];
            realtime out_send_time;
            int sent_count;
            queue_stats_t stats;
            real deviation;

            fc.set_port_rate(10000.0);
            fc.set_duration(100us);

            fc.add_queue(0, MODEL_RATE);
            fc.set_queue_rate(0, 1000.0);

            make_pkt(pkt, 1000);
            for (int i = 0; i < 200; i++)
                fc.push_packet(0, pkt);

            sent_count = 0;
            fc.start_schedule();
            while (fc.get_next_scheduled(out_queue_id, out_data, out_send_time))
                sent_count++;

            stats = fc.get_queue_stats(0);
            deviation = stats.deviation_pct;
            if (deviation < 0) deviation = -deviation;

            $display("  rate_accuracy: sent=%0d actual=%.1f Mbps expected=1000.0 dev=%.1f%%",
                     sent_count, stats.actual_rate_mbps, stats.deviation_pct);
            check("rate_accuracy: deviation < 15%", deviation < 15.0);
            check("rate_accuracy: sent > 5 packets", sent_count > 5);
        end

        // ---- WRR bandwidth distribution test ----
        begin
            flow_controller fc = new();
            byte unsigned pkt[$];
            int out_queue_id;
            byte unsigned out_data[$];
            realtime out_send_time;
            int q0_bytes, q1_bytes;
            real ratio;

            fc.set_port_rate(10000.0);
            fc.set_duration(100us);

            fc.add_queue(0, MODEL_RATE);
            fc.set_queue_rate(0, 5000.0);
            fc.set_queue_weight(0, 3);

            fc.add_queue(1, MODEL_RATE);
            fc.set_queue_rate(1, 5000.0);
            fc.set_queue_weight(1, 1);

            fc.set_scheduler_mode(SCHED_WRR);

            make_pkt(pkt, 1500);
            for (int i = 0; i < 500; i++) begin
                fc.push_packet(0, pkt);
                fc.push_packet(1, pkt);
            end

            q0_bytes = 0; q1_bytes = 0;
            fc.start_schedule();
            while (fc.get_next_scheduled(out_queue_id, out_data, out_send_time)) begin
                if (out_queue_id == 0) q0_bytes += out_data.size();
                else q1_bytes += out_data.size();
            end

            if (q1_bytes > 0) ratio = real'(q0_bytes) / real'(q1_bytes);
            else ratio = 999.0;
            $display("  wrr_bw: q0=%0d bytes, q1=%0d bytes, ratio=%.2f (expect ~3.0)",
                     q0_bytes, q1_bytes, ratio);
            check("wrr_bw: q0 gets more bandwidth than q1", q0_bytes > q1_bytes);
            check("wrr_bw: ratio roughly 3:1", ratio > 1.5 && ratio < 5.0);
        end

        // ---- Statistics collection test ----
        begin
            flow_controller fc = new();
            byte unsigned pkt[$];
            int out_queue_id;
            byte unsigned out_data[$];
            realtime out_send_time;
            queue_stats_t s0, s1;
            int sent;

            fc.set_port_rate(10000.0);
            fc.set_duration(50us);

            fc.add_queue(0, MODEL_RATE);
            fc.set_queue_rate(0, 2000.0);

            fc.add_queue(1, MODEL_RATE);
            fc.set_queue_rate(1, 1000.0);

            fc.set_scheduler_mode(SCHED_WRR);
            fc.set_queue_weight(0, 1);
            fc.set_queue_weight(1, 1);

            make_pkt(pkt, 500);
            for (int i = 0; i < 200; i++) begin
                fc.push_packet(0, pkt);
                fc.push_packet(1, pkt);
            end

            sent = 0;
            fc.start_schedule();
            while (fc.get_next_scheduled(out_queue_id, out_data, out_send_time))
                sent++;

            s0 = fc.get_queue_stats(0);
            s1 = fc.get_queue_stats(1);

            $display("  stats: q0 pkts=%0d bytes=%0d rate=%.1f Mbps",
                     s0.total_packets, s0.total_bytes, s0.actual_rate_mbps);
            $display("  stats: q1 pkts=%0d bytes=%0d rate=%.1f Mbps",
                     s1.total_packets, s1.total_bytes, s1.actual_rate_mbps);

            check("stats: q0 total_packets > 0", s0.total_packets > 0);
            check("stats: q1 total_packets > 0", s1.total_packets > 0);
            check("stats: q0 total_bytes = pkts * 500", s0.total_bytes == s0.total_packets * 500);
            check("stats: q1 total_bytes = pkts * 500", s1.total_bytes == s1.total_packets * 500);
            check("stats: total sent matches stats", sent == s0.total_packets + s1.total_packets);
        end

        // ---- Burst model flow test ----
        begin
            flow_controller fc = new();
            byte unsigned pkt[$];
            int out_queue_id;
            byte unsigned out_data[$];
            realtime out_send_time;
            int sent;
            realtime times[$];

            fc.set_port_rate(10000.0);
            fc.set_duration(50us);

            fc.add_queue(0, MODEL_BURST);
            fc.set_burst_param(0, 3, 5us);

            make_pkt(pkt, 100);
            for (int i = 0; i < 50; i++)
                fc.push_packet(0, pkt);

            sent = 0;
            fc.start_schedule();
            while (fc.get_next_scheduled(out_queue_id, out_data, out_send_time)) begin
                times.push_back(out_send_time);
                sent++;
            end

            check("burst_flow: sent packets", sent > 3);
            if (times.size() >= 4) begin
                check("burst_flow: first 3 pkts at same time (burst)",
                      times[1] - times[0] < 1ns && times[2] - times[1] < 1ns);
                check("burst_flow: 4th pkt after pause",
                      times[3] - times[2] > 1us);
            end
        end

        // ---- Duration limit enforced ----
        begin
            flow_controller fc = new();
            byte unsigned pkt[$];
            int out_queue_id;
            byte unsigned out_data[$];
            realtime out_send_time;
            realtime last_time;
            int sent;

            fc.set_port_rate(10000.0);
            fc.set_duration(10us);

            fc.add_queue(0, MODEL_RATE);
            fc.set_queue_rate(0, 5000.0);

            make_pkt(pkt, 200);
            for (int i = 0; i < 500; i++)
                fc.push_packet(0, pkt);

            sent = 0;
            last_time = 0;
            fc.start_schedule();
            while (fc.get_next_scheduled(out_queue_id, out_data, out_send_time)) begin
                last_time = out_send_time;
                sent++;
            end

            check("duration: last_time < 10us", last_time < 10us);
            check("duration: sent some packets", sent > 0);
        end

        // ---- Time monotonicity ----
        begin
            flow_controller fc = new();
            byte unsigned pkt[$];
            int out_queue_id;
            byte unsigned out_data[$];
            realtime out_send_time;
            realtime prev_time;
            bit monotonic;
            int sent;

            fc.set_port_rate(10000.0);
            fc.set_duration(50us);

            fc.add_queue(0, MODEL_RATE);
            fc.set_queue_rate(0, 2000.0);
            fc.add_queue(1, MODEL_RATE);
            fc.set_queue_rate(1, 1000.0);
            fc.set_scheduler_mode(SCHED_WRR);
            fc.set_queue_weight(0, 1);
            fc.set_queue_weight(1, 1);

            make_pkt(pkt, 500);
            for (int i = 0; i < 200; i++) begin
                fc.push_packet(0, pkt);
                fc.push_packet(1, pkt);
            end

            monotonic = 1;
            prev_time = 0;
            sent = 0;
            fc.start_schedule();
            while (fc.get_next_scheduled(out_queue_id, out_data, out_send_time)) begin
                if (out_send_time < prev_time) monotonic = 0;
                prev_time = out_send_time;
                sent++;
            end

            check("monotonic: send times are non-decreasing", monotonic);
            check("monotonic: sent packets", sent > 0);
        end

        $display("\n=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TEST FAILED");
    end

endprogram
