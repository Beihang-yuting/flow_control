# Flow Controller Design Spec

## Overview

A generic multi-queue traffic scheduling engine implemented as SystemVerilog classes for VCS simulation. Controls per-queue traffic shaping on the send side and verifies traffic conformance on the receive side. Interface-agnostic — input/output is `byte unsigned data[$]`.

## Requirements

### Functional

- Support N queues (default 8), queue key is user-defined (CoS, flow_id, VLAN, etc.)
- Each queue has an independent, configurable traffic model
- Single output port with configurable total bandwidth cap
- Two-layer rate control: per-queue shaping + total port shaping
- Configurable scheduling/arbitration across queues
- Duration-based send control: `pkt_count = -1` means continuous send until duration expires
- Time unit configurable, default microseconds (us)
- Monitor side: statistical rate checking + post-run report + optional debug trace
- Can operate as:
  - Shaper (directly connected to interface, controls when packets go out)
  - Standalone scheduler (decides timing, external driver does actual send)
  - Monitor (checks received traffic against expected model)

### Non-Functional

- Pure SV class, no RTL dependency
- Compatible with net_packet (`byte unsigned raw_data[$]` as packet format)
- Extensible via inheritance and callback

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                flow_controller (top)                 │
│                                                     │
│  ┌──────────┐  ┌──────────┐      ┌──────────┐     │
│  │ queue[0] │  │ queue[1] │ ...  │ queue[N] │     │
│  │ model:X  │  │ model:Y  │      │ model:Z  │     │
│  └────┬─────┘  └────┬─────┘      └────┬─────┘     │
│       └──────────┬───┘─────────────────┘            │
│            ┌─────▼──────┐                           │
│            │  scheduler  │  (SP / WRR / SP+WRR)     │
│            └─────┬──────┘                           │
│            ┌─────▼──────┐                           │
│            │ port_shaper │  (total port rate limit)  │
│            └─────┬──────┘                           │
│                  ▼                                  │
│           output (byte stream)                      │
│                                                     │
│  ┌──────────────────────────────────────┐           │
│  │        traffic_monitor               │           │
│  │  - windowed rate statistics          │           │
│  │  - post-run report                   │           │
│  │  - real-time debug trace (optional)  │           │
│  └──────────────────────────────────────┘           │
└─────────────────────────────────────────────────────┘
```

## Class Hierarchy

### 1. traffic_model_base (abstract)

Abstract base class for all traffic models. Determines **when** the next packet should be sent.

```systemverilog
virtual class traffic_model_base;
    // Returns the next send time (in time_unit)
    pure virtual function realtime get_next_send_time();

    // Reset internal state
    pure virtual function void reset();

    // Optional: callback hook for user-defined logic
    // Users can also override get_next_send_time() via inheritance
endclass
```

**Built-in subclasses:**

| Class | Behavior | Key Parameters |
|-------|----------|----------------|
| `rate_model` | Constant rate, evenly spaced packets | `rate_mbps`, `pkt_size` |
| `token_bucket_model` | Rate + burst tolerance | `rate_mbps`, `burst_size_bytes`, `pkt_size` |
| `burst_model` | Send N packets, pause M cycles, repeat | `send_count`, `pause_cycles` |
| `random_model` | Average rate with random inter-packet gap | `avg_rate_mbps`, `distribution` (UNIFORM / POISSON / NORMAL), `pkt_size` |
| `step_model` | Time-segmented rate profile | `step_cfg[$]` (array of `{duration, rate_mbps}`) |

### 2. traffic_queue

Represents a single traffic queue with its own model and packet FIFO.

```systemverilog
class traffic_queue;
    int              queue_id;       // user-defined key
    traffic_model_base model;        // assigned traffic model
    byte unsigned    pkt_fifo[$][$]; // queue of packets (each is byte array)
    int              priority;       // for SP scheduling
    int              weight;         // for WRR scheduling

    function void push_packet(byte unsigned data[$]);
    function bit  has_packet();
    function void get_next_packet(output byte unsigned data[$]);
endclass
```

### 3. scheduler

Multi-queue arbitration. Decides which queue's packet goes next when multiple queues are ready.

**Supported modes:**

| Mode | Behavior |
|------|----------|
| `STRICT_PRIORITY` | Higher priority queue always wins |
| `WRR` | Weighted round-robin based on configured weights |
| `SP_WRR_MIXED` | Top N queues use SP, remaining use WRR among themselves |

```systemverilog
class scheduler;
    scheduler_mode_e mode;

    // Returns the queue_id that should send next
    function int select_queue(traffic_queue queues[$]);
endclass
```

### 4. port_shaper

Total output port rate limiter using token bucket algorithm.

```systemverilog
class port_shaper;
    real     port_rate_mbps;    // total port bandwidth
    int      burst_size_bytes;  // burst tolerance
    realtime last_send_time;

    // Returns 1 if sending pkt_size bytes is allowed now
    function bit can_send(int pkt_size);

    // Consume tokens after sending
    function void consume(int pkt_size);
endclass
```

### 5. flow_controller (top-level)

The main user-facing class that ties everything together.

```systemverilog
class flow_controller;
    // Configuration
    function void set_port_rate(real rate_mbps);
    function void set_port_burst(int burst_bytes);
    function void set_duration(realtime duration);     // default send duration
    function void set_time_unit(realtime unit);        // default 1us

    // Queue management
    function void add_queue(int queue_id, traffic_model_type_e model_type);
    function void set_queue_rate(int queue_id, real rate_mbps);
    function void set_queue_burst(int queue_id, int burst_bytes);
    function void set_queue_priority(int queue_id, int priority);
    function void set_queue_weight(int queue_id, int weight);
    function void set_burst_param(int queue_id, int send_count, int pause_cycles);
    function void set_random_param(int queue_id, real avg_rate, distribution_e dist);
    function void set_step_param(int queue_id, step_cfg_t steps[$]);

    // Custom model support
    function void set_queue_model(int queue_id, traffic_model_base custom_model);
    function void set_queue_callback(int queue_id, traffic_callback_t cb);

    // Scheduler
    function void set_scheduler_mode(scheduler_mode_e mode);

    // Packet input
    function void push_packet(int queue_id, byte unsigned data[$]);

    // Execution
    task start(int pkt_count = -1);   // -1 = send until duration expires
    task stop();

    // Monitor (receive side)
    function void monitor_packet(int queue_id, byte unsigned data[$], realtime recv_time);

    // Report
    function void report();
    function void set_debug_level(int level);  // 0=off, 1=summary, 2=verbose

    // Internal
    protected scheduler      sched;
    protected port_shaper    shaper;
    protected traffic_queue  queues[int];   // associative array keyed by queue_id
    protected traffic_monitor monitor;
    protected realtime       duration;
    protected realtime       time_unit;
endclass
```

### 6. traffic_monitor

Receive-side traffic verification.

```systemverilog
class traffic_monitor;
    // Configuration
    realtime          window_size;      // statistics window (default 10us)
    real              tolerance_pct;    // allowed deviation (default 5.0)
    int               debug_level;     // 0=off, 1=summary, 2=per-packet

    // Per-queue statistics
    typedef struct {
        real    configured_rate_mbps;
        real    actual_rate_mbps;
        real    deviation_pct;
        longint total_bytes;
        longint total_packets;
        longint burst_max_bytes;       // max bytes in single window
        int     window_violations;     // windows exceeding tolerance
    } queue_stats_t;

    // Record a received packet
    function void record(int queue_id, int pkt_size, realtime recv_time);

    // Generate report (called at end of simulation)
    function void report();

    // Per-window check (called internally at window boundaries)
    protected function void check_window(int queue_id);
endclass
```

## Traffic Model Details

### Rate Model

Constant inter-packet gap:

```
gap = pkt_size_bytes * 8 / rate_mbps * time_unit_factor
```

### Token Bucket Model

- Tokens accumulate at `rate_mbps`
- Bucket capacity = `burst_size_bytes`
- Packet sent only when enough tokens available
- Allows bursts up to bucket capacity

### Burst Model

```
[send_count packets at line rate] -> [pause for pause_cycles] -> repeat
```

### Random Model

Inter-packet gap sampled from configured distribution:

- **UNIFORM**: gap ~ U(min_gap, max_gap), derived from avg_rate
- **POISSON**: gap ~ Exp(lambda), where lambda = avg_rate / pkt_size
- **NORMAL**: gap ~ N(mean_gap, sigma), clamped to positive values

### Step Model

User provides array of `{duration, rate_mbps}` segments:

```systemverilog
steps = '{
    '{duration: 10us, rate_mbps: 1000},  // 1Gbps for 10us
    '{duration: 20us, rate_mbps: 500},   // 500Mbps for 20us
    '{duration: 10us, rate_mbps: 2000}   // 2Gbps for 10us
};
```

Time unit is configurable, segments play out sequentially, can optionally loop.

## Scheduling Details

### Strict Priority (SP)

Queue with highest `priority` value always served first. Lower priority queues may starve.

### Weighted Round-Robin (WRR)

Each queue served proportionally to its `weight`. Implementation uses deficit-weighted round-robin (DWRR) for byte-accurate fairness.

### SP + WRR Mixed

- Queues with `priority > 0` use strict priority among themselves
- Queues with `priority == 0` share remaining bandwidth via WRR
- SP queues are served first; WRR queues get whatever is left

## Port Shaper

Token bucket on the total output:

- All queues' output passes through port_shaper before final output
- If port is full, scheduler blocks even if individual queue has budget
- Prevents total output exceeding physical port capacity

## Duration & Packet Count Control

- `pkt_count = -1`: send continuously until `duration` expires
- `pkt_count = N` (N > 0): send exactly N packets total (across all queues, proportional to their rates), or until duration expires, whichever comes first
- `duration` is the hard upper bound; simulation time will not exceed it
- Default time unit: 1us; configurable via `set_time_unit()`

## Monitor Behavior

### Statistical Window Check

- Divide simulation time into windows of `window_size` (default 10us)
- At each window boundary, calculate actual rate per queue
- Compare against configured rate with `tolerance_pct` margin
- Record violations but do not stop simulation (non-blocking)

### Post-Run Report

At simulation end, `report()` outputs:

```
=== Flow Controller Report ===
Duration: 100us | Port Rate: 10000 Mbps

Queue | Model       | Config Rate | Actual Rate | Deviation | Packets | Bytes    | Violations
------|-------------|-------------|-------------|-----------|---------|----------|-----------
0     | rate        | 2000 Mbps   | 1998 Mbps   | -0.1%     | 16650   | 24.97MB  | 0
1     | token_bucket| 1000 Mbps   | 1005 Mbps   | +0.5%     | 8375    | 12.56MB  | 1
2     | burst       | 3000 Mbps   | 2980 Mbps   | -0.7%     | 24833   | 37.25MB  | 2

Total: 49858 packets, 74.78MB, port utilization: 59.8%
=== END ===
```

### Debug Trace (level 2)

When `debug_level >= 2`, log each packet send/receive:

```
[100.500us] TX queue=0 pkt_size=1500 gap=12.0ns rate=1000Mbps
[100.512us] TX queue=1 pkt_size=512  gap=4.1ns  rate=998Mbps
```

## Extensibility

### Custom Traffic Model (Inheritance)

```systemverilog
class sine_wave_model extends traffic_model_base;
    real base_rate_mbps;
    real amplitude_mbps;
    real period;

    virtual function realtime get_next_send_time();
        real current_rate = base_rate_mbps + amplitude_mbps * $sin(2*PI*$realtime/period);
        return /* calculate gap from current_rate */;
    endfunction
endclass

fc.set_queue_model(3, sine_wave_model::new(1000, 500, 50us));
```

### Custom Traffic Model (Callback)

```systemverilog
function realtime my_custom_gap(int queue_id, int pkt_size, realtime current_time);
    // user logic
    return gap;
endfunction

fc.set_queue_callback(3, my_custom_gap);
```

## Operating Modes

### Mode 1: Shaper (direct output)

```systemverilog
fc.start();
// flow_controller internally calls output callback or drives interface
// user registers: fc.set_output_callback(my_driver_send);
```

### Mode 2: Standalone Scheduler

```systemverilog
// flow_controller only decides timing; user polls for next action
while (fc.is_running()) begin
    fc.get_next_scheduled(queue_id, data, send_time);
    @(send_time);
    my_driver.send(data);
end
```

### Mode 3: Monitor Only

```systemverilog
// User feeds received packets into monitor
forever begin
    @(posedge clk);
    if (rx_valid) begin
        fc.monitor_packet(rx_cos, rx_data, $realtime);
    end
end
// At end:
fc.report();
```

## File Structure

```
flow_control/
├── src/
│   ├── common/
│   │   └── flow_defines.sv          # enums, typedefs, structs
│   ├── models/
│   │   ├── traffic_model_base.sv    # abstract base
│   │   ├── rate_model.sv
│   │   ├── token_bucket_model.sv
│   │   ├── burst_model.sv
│   │   ├── random_model.sv
│   │   └── step_model.sv
│   ├── core/
│   │   ├── traffic_queue.sv
│   │   ├── scheduler.sv
│   │   ├── port_shaper.sv
│   │   └── flow_controller.sv       # top-level
│   └── monitor/
│       └── traffic_monitor.sv
├── test/
│   ├── test_rate_model.sv
│   ├── test_scheduler.sv
│   ├── test_flow_controller.sv
│   └── test_monitor.sv
├── docs/
│   └── superpowers/specs/
│       └── 2026-04-17-flow-controller-design.md
├── Makefile
└── filelist.f
```

## Dependencies

- **net_packet** (optional): Can use `packet.raw_data` as input, but flow_control has no hard dependency on it. Any `byte unsigned data[$]` works.
- **UVM** (optional): Can be wrapped in UVM components later, but core classes are plain SV.
