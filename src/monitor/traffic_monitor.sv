// src/monitor/traffic_monitor.sv
`ifndef TRAFFIC_MONITOR_SV
`define TRAFFIC_MONITOR_SV

`include "flow_defines.sv"

class traffic_monitor;

    realtime window_size;
    real     tolerance_pct;
    int      debug_level;

    protected real     configured_rate[int];
    protected longint  total_bytes[int];
    protected longint  total_packets[int];
    protected longint  burst_max_bytes[int];

    protected longint  window_bytes[int];
    protected int      window_violations[int];
    protected realtime window_start_time;

    protected realtime first_record_time;
    protected realtime last_record_time;
    protected bit      has_records;

    function new();
        this.window_size       = 10us;
        this.tolerance_pct     = 5.0;
        this.debug_level       = 0;
        this.has_records       = 0;
        this.window_start_time = 0;
    endfunction

    function void register_queue(int queue_id, real expected_rate_mbps);
        configured_rate[queue_id]   = expected_rate_mbps;
        total_bytes[queue_id]       = 0;
        total_packets[queue_id]     = 0;
        burst_max_bytes[queue_id]   = 0;
        window_bytes[queue_id]      = 0;
        window_violations[queue_id] = 0;
    endfunction

    function void record(int queue_id, int pkt_size, realtime recv_time);
        if (!configured_rate.exists(queue_id)) begin
            $display("[WARN] traffic_monitor: unregistered queue_id=%0d", queue_id);
            return;
        end

        if (!has_records) begin
            first_record_time  = recv_time;
            window_start_time  = recv_time;
            has_records        = 1;
        end

        while (recv_time >= window_start_time + window_size) begin
            check_all_windows();
            window_start_time += window_size;
        end

        total_bytes[queue_id]   += pkt_size;
        total_packets[queue_id] += 1;
        window_bytes[queue_id]  += pkt_size;

        if (window_bytes[queue_id] > burst_max_bytes[queue_id])
            burst_max_bytes[queue_id] = window_bytes[queue_id];

        last_record_time = recv_time;

        if (debug_level >= 2) begin
            $display("[%0t] RX queue=%0d pkt_size=%0d", recv_time, queue_id, pkt_size);
        end
    endfunction

    protected function void check_all_windows();
        foreach (configured_rate[qid]) begin
            check_window(qid);
            window_bytes[qid] = 0;
        end
    endfunction

    protected function void check_window(int queue_id);
        real window_rate_mbps;
        real deviation;
        real window_dur_sec;

        window_dur_sec = window_size / 1s;
        if (window_dur_sec <= 0) return;

        window_rate_mbps = (window_bytes[queue_id] * 8.0) / (window_dur_sec * 1_000_000.0);

        if (configured_rate[queue_id] > 0) begin
            deviation = (window_rate_mbps - configured_rate[queue_id]) / configured_rate[queue_id] * 100.0;
            if (deviation > tolerance_pct || deviation < -tolerance_pct)
                window_violations[queue_id]++;
        end

        if (debug_level >= 1) begin
            $display("[MONITOR] window queue=%0d rate=%.1f Mbps (expected %.1f, dev=%.1f%%)",
                     queue_id, window_rate_mbps, configured_rate[queue_id],
                     (configured_rate[queue_id] > 0) ?
                       ((window_rate_mbps - configured_rate[queue_id]) / configured_rate[queue_id] * 100.0) : 0.0);
        end
    endfunction

    function void finalize(realtime end_time);
        last_record_time = end_time;
        check_all_windows();
    endfunction

    function queue_stats_t get_stats(int queue_id);
        queue_stats_t s;
        real duration_sec;

        duration_sec = (last_record_time - first_record_time) / 1s;

        s.configured_rate_mbps = configured_rate.exists(queue_id) ? configured_rate[queue_id] : 0;
        s.total_bytes          = total_bytes.exists(queue_id) ? total_bytes[queue_id] : 0;
        s.total_packets        = total_packets.exists(queue_id) ? total_packets[queue_id] : 0;
        s.burst_max_bytes      = burst_max_bytes.exists(queue_id) ? burst_max_bytes[queue_id] : 0;
        s.window_violations    = window_violations.exists(queue_id) ? window_violations[queue_id] : 0;

        if (duration_sec > 0)
            s.actual_rate_mbps = (s.total_bytes * 8.0) / (duration_sec * 1_000_000.0);
        else
            s.actual_rate_mbps = 0;

        if (s.configured_rate_mbps > 0)
            s.deviation_pct = (s.actual_rate_mbps - s.configured_rate_mbps) / s.configured_rate_mbps * 100.0;
        else
            s.deviation_pct = 0;

        return s;
    endfunction

    function void report();
        queue_stats_t s;
        longint grand_total_bytes   = 0;
        longint grand_total_packets = 0;

        $display("\n=== Flow Controller Report ===");
        $display("Duration: %0t | Window: %0t | Tolerance: %.1f%%",
                 last_record_time - first_record_time, window_size, tolerance_pct);
        $display("Queue | Config Rate | Actual Rate | Deviation | Packets | Bytes      | Violations");
        $display("------|-------------|-------------|-----------|---------|------------|-----------");

        foreach (configured_rate[qid]) begin
            s = get_stats(qid);
            grand_total_bytes   += s.total_bytes;
            grand_total_packets += s.total_packets;

            $display("%-6d| %7.1f Mbps| %7.1f Mbps| %6.1f%%   | %7d | %10d | %d",
                     qid,
                     s.configured_rate_mbps, s.actual_rate_mbps, s.deviation_pct,
                     s.total_packets, s.total_bytes, s.window_violations);
        end

        $display("\nTotal: %0d packets, %0d bytes", grand_total_packets, grand_total_bytes);
        $display("=== END ===\n");
    endfunction

endclass

`endif // TRAFFIC_MONITOR_SV
