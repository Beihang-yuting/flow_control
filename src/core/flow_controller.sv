// src/core/flow_controller.sv
`ifndef FLOW_CONTROLLER_SV
`define FLOW_CONTROLLER_SV

`include "scheduler.sv"
`include "port_shaper.sv"
`include "traffic_monitor.sv"

class flow_controller;

    protected scheduler       sched;
    protected port_shaper     shaper;
    protected traffic_monitor monitor;
    protected traffic_queue   queues[int];

    protected realtime duration;
    protected realtime time_unit_val;
    protected int      debug_level;

    protected realtime current_time;
    protected int      total_sent;
    protected int      pkt_limit;
    protected bit      is_running_flag;

    function new();
        sched           = new();
        shaper          = new();
        monitor         = new();
        duration        = 100us;
        time_unit_val   = 1us;
        debug_level     = 0;
        current_time    = 0;
        total_sent      = 0;
        pkt_limit       = -1;
        is_running_flag = 0;
    endfunction

    function void set_port_rate(real rate_mbps);
        shaper.port_rate_mbps = rate_mbps;
    endfunction

    function void set_port_burst(int burst_bytes);
        shaper.burst_size_bytes = burst_bytes;
    endfunction

    function void set_duration(realtime dur);
        duration = dur;
    endfunction

    function void set_time_unit(realtime unit);
        time_unit_val = unit;
    endfunction

    function void set_debug_level(int level);
        debug_level         = level;
        monitor.debug_level = level;
    endfunction

    function void add_queue(int queue_id, traffic_model_type_e model_type);
        traffic_queue q = new(queue_id);
        traffic_model_base m;

        case (model_type)
            MODEL_RATE:         begin rate_model rm = new();          m = rm; end
            MODEL_TOKEN_BUCKET: begin token_bucket_model tb = new();  m = tb; end
            MODEL_BURST:        begin burst_model bm = new();         m = bm; end
            MODEL_RANDOM:       begin random_model rdm = new();       m = rdm; end
            MODEL_STEP:         begin step_model sm = new();          m = sm; end
            MODEL_CUSTOM:       m = null;
        endcase

        q.set_model(m);
        queues[queue_id] = q;
    endfunction

    function void set_queue_rate(int queue_id, real rate_mbps);
        if (!queues.exists(queue_id)) return;
        if (queues[queue_id].model == null) return;

        begin
            rate_model rm;
            token_bucket_model tbm;
            random_model rdm;
            if ($cast(rm, queues[queue_id].model))
                rm.rate_mbps = rate_mbps;
            else if ($cast(tbm, queues[queue_id].model))
                tbm.rate_mbps = rate_mbps;
            else if ($cast(rdm, queues[queue_id].model))
                rdm.avg_rate_mbps = rate_mbps;
        end

        monitor.register_queue(queue_id, rate_mbps);
    endfunction

    function void set_queue_burst(int queue_id, int burst_bytes);
        token_bucket_model tbm;
        if (!queues.exists(queue_id)) return;
        if ($cast(tbm, queues[queue_id].model))
            tbm.burst_size_bytes = burst_bytes;
    endfunction

    function void set_queue_priority(int queue_id, int prio);
        if (queues.exists(queue_id))
            queues[queue_id].prio = prio;
    endfunction

    function void set_queue_weight(int queue_id, int weight);
        if (queues.exists(queue_id))
            queues[queue_id].weight = weight;
    endfunction

    function void set_burst_param(int queue_id, int send_count, realtime pause_time);
        burst_model bm;
        if (!queues.exists(queue_id)) return;
        if ($cast(bm, queues[queue_id].model)) begin
            bm.send_count = send_count;
            bm.pause_time = pause_time;
        end
    endfunction

    function void set_random_param(int queue_id, real avg_rate, distribution_e dist_type);
        random_model rdm;
        if (!queues.exists(queue_id)) return;
        if ($cast(rdm, queues[queue_id].model)) begin
            rdm.avg_rate_mbps = avg_rate;
            rdm.dist_type     = dist_type;
        end
    endfunction

    function void set_step_param(int queue_id, step_cfg_t steps[$]);
        step_model sm;
        if (!queues.exists(queue_id)) return;
        if ($cast(sm, queues[queue_id].model))
            sm.steps = steps;
    endfunction

    function void set_queue_model(int queue_id, traffic_model_base custom_model);
        if (queues.exists(queue_id))
            queues[queue_id].set_model(custom_model);
    endfunction

    function void set_scheduler_mode(scheduler_mode_e mode);
        sched.mode = mode;
    endfunction

    function void push_packet(int queue_id, byte unsigned data[$]);
        if (queues.exists(queue_id))
            queues[queue_id].push_packet(data);
    endfunction

    function void start_schedule(int pkt_count = -1);
        current_time    = 0;
        total_sent      = 0;
        pkt_limit       = pkt_count;
        is_running_flag = 1;

        foreach (queues[id]) begin
            if (queues[id].model != null)
                queues[id].model.reset();
        end
        shaper.reset();
        sched.reset();
    endfunction

    function bit get_next_scheduled(output int queue_id, output byte unsigned data[$], output realtime send_time);
        int selected_id;
        realtime model_interval;
        realtime port_wait;
        int pkt_size;

        if (!is_running_flag) return 0;

        if (current_time >= duration) begin
            is_running_flag = 0;
            return 0;
        end

        if (pkt_limit > 0 && total_sent >= pkt_limit) begin
            is_running_flag = 0;
            return 0;
        end

        selected_id = sched.select_queue(queues);
        if (selected_id < 0) begin
            is_running_flag = 0;
            return 0;
        end

        pkt_size = queues[selected_id].peek_next_size();

        if (queues[selected_id].model != null)
            model_interval = queues[selected_id].model.get_interval(pkt_size, current_time);
        else
            model_interval = 0;

        current_time += model_interval;

        port_wait = shaper.get_wait_time(pkt_size, current_time);
        current_time += port_wait;

        if (current_time >= duration) begin
            is_running_flag = 0;
            return 0;
        end

        shaper.consume(pkt_size, current_time);
        queues[selected_id].get_next_packet(data);

        queue_id  = selected_id;
        send_time = current_time;
        total_sent++;

        monitor.record(selected_id, pkt_size, current_time);

        if (debug_level >= 2) begin
            $display("[%0t] TX queue=%0d pkt_size=%0d", current_time, selected_id, pkt_size);
        end

        return 1;
    endfunction

    function bit is_running();
        return is_running_flag;
    endfunction

    function void monitor_packet(int queue_id, byte unsigned data[$], realtime recv_time);
        monitor.record(queue_id, data.size(), recv_time);
    endfunction

    function void report();
        monitor.finalize(current_time);
        monitor.report();
    endfunction

    function queue_stats_t get_queue_stats(int queue_id);
        return monitor.get_stats(queue_id);
    endfunction

endclass

`endif // FLOW_CONTROLLER_SV
