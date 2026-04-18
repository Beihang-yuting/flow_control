// src/core/scheduler.sv
`ifndef SCHEDULER_SV
`define SCHEDULER_SV

`include "traffic_queue.sv"

class scheduler;

    scheduler_mode_e mode;

    protected int deficit_counter[int];
    protected int wrr_queue_ids[$];
    protected int wrr_index;

    function new();
        this.mode      = SCHED_STRICT_PRIORITY;
        this.wrr_index = 0;
    endfunction

    function int select_queue(traffic_queue queues[int]);
        case (mode)
            SCHED_STRICT_PRIORITY: return select_sp(queues);
            SCHED_WRR:             return select_wrr(queues);
            SCHED_SP_WRR_MIXED:    return select_mixed(queues);
            default:               return -1;
        endcase
    endfunction

    protected function int select_sp(traffic_queue queues[int]);
        int best_id = -1;
        int best_pri = -1;
        foreach (queues[id]) begin
            if (queues[id].has_packet() && queues[id].prio > best_pri) begin
                best_pri = queues[id].prio;
                best_id  = id;
            end
        end
        return best_id;
    endfunction

    protected function int select_wrr(traffic_queue queues[int]);
        int quantum = 1500;
        int attempts;

        if (wrr_queue_ids.size() == 0) begin
            foreach (queues[id]) wrr_queue_ids.push_back(id);
        end

        attempts = 0;
        while (attempts < wrr_queue_ids.size() * 3) begin
            int qid;
            if (wrr_index >= wrr_queue_ids.size())
                wrr_index = 0;
            qid = wrr_queue_ids[wrr_index];

            if (queues.exists(qid) && queues[qid].has_packet()) begin
                if (!deficit_counter.exists(qid))
                    deficit_counter[qid] = 0;

                if (deficit_counter[qid] < queues[qid].peek_next_size())
                    deficit_counter[qid] += quantum * queues[qid].weight;

                if (deficit_counter[qid] >= queues[qid].peek_next_size()) begin
                    deficit_counter[qid] -= queues[qid].peek_next_size();
                    if (deficit_counter[qid] <= 0)
                        wrr_index++;
                    return qid;
                end
            end
            wrr_index++;
            attempts++;
        end

        return -1;
    endfunction

    protected function int select_mixed(traffic_queue queues[int]);
        begin
            int best_id = -1;
            int best_pri = 0;
            foreach (queues[id]) begin
                if (queues[id].has_packet() && queues[id].prio > best_pri) begin
                    best_pri = queues[id].prio;
                    best_id  = id;
                end
            end
            if (best_id >= 0) return best_id;
        end

        begin
            traffic_queue wrr_queues[int];
            foreach (queues[id]) begin
                if (queues[id].prio == 0)
                    wrr_queues[id] = queues[id];
            end
            if (wrr_queues.size() > 0)
                return select_wrr(wrr_queues);
        end

        return -1;
    endfunction

    function void reset();
        deficit_counter.delete();
        wrr_queue_ids.delete();
        wrr_index = 0;
    endfunction

endclass

`endif // SCHEDULER_SV
