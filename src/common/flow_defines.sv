// src/common/flow_defines.sv
`ifndef FLOW_DEFINES_SV
`define FLOW_DEFINES_SV

// Traffic model types
typedef enum int {
    MODEL_RATE          = 0,
    MODEL_TOKEN_BUCKET  = 1,
    MODEL_BURST         = 2,
    MODEL_RANDOM        = 3,
    MODEL_STEP          = 4,
    MODEL_CUSTOM        = 5
} traffic_model_type_e;

// Random distribution types
typedef enum int {
    DIST_UNIFORM  = 0,
    DIST_POISSON  = 1,
    DIST_NORMAL   = 2
} distribution_e;

// Scheduler modes
typedef enum int {
    SCHED_STRICT_PRIORITY = 0,
    SCHED_WRR             = 1,
    SCHED_SP_WRR_MIXED    = 2
} scheduler_mode_e;

// Step configuration: one segment of the step model
typedef struct {
    realtime duration;
    real     rate_mbps;
} step_cfg_t;

// Per-queue statistics (used by traffic_monitor)
typedef struct {
    real    configured_rate_mbps;
    real    actual_rate_mbps;
    real    deviation_pct;
    longint total_bytes;
    longint total_packets;
    longint burst_max_bytes;
    int     window_violations;
} queue_stats_t;

// Callback type for custom traffic model
// SV does not have native function pointers; we use a virtual class wrapper
virtual class traffic_callback;
    pure virtual function realtime get_interval(int queue_id, int pkt_size, realtime current_time);
endclass

`endif // FLOW_DEFINES_SV
