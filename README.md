# Flow Control

**SystemVerilog Traffic Scheduling & Shaping Engine**

A modular, simulation-ready framework for generating, scheduling, shaping, and monitoring network traffic at the packet level. Designed for use with Synopsys VCS.

---

## Features

- **5 Traffic Models** — Constant rate, token bucket (burst), burst pattern, random (uniform/poisson/normal), step rate profile
- **3 Scheduling Algorithms** — Strict Priority (SP), Weighted Round Robin (WRR), Mixed SP+WRR
- **Port-Level Rate Limiting** — Token bucket shaper for total port bandwidth control
- **Real-Time Statistics** — Per-queue monitoring with windowed rate checking and deviation tracking
- **Extensible** — Custom traffic models via class inheritance
- **89 Test Cases** — Comprehensive test suite, all passing on VCS Q-2020.03-SP2-7

---

## Architecture

```
Input Packets ──> Queue[N] + Model ──> Scheduler ──> Port Shaper ──> Output
                       │                                                │
                 Traffic Monitor <──────── record() ──────────── Statistics
```

| Component | Description |
|-----------|-------------|
| **Traffic Queue** | Per-queue FIFO with associated traffic model, priority, and weight |
| **Traffic Models** | Control inter-packet gap (IPG) — determines sending rate per queue |
| **Scheduler** | Selects which queue sends next (SP / WRR / Mixed) |
| **Port Shaper** | Token bucket rate limiter for aggregate port bandwidth |
| **Traffic Monitor** | Collects per-queue statistics with windowed rate checking |
| **Flow Controller** | Top-level orchestrator integrating all components |

---

## Project Structure

```
flow_control/
├── Makefile                        # Build system (VCS)
├── filelist.f                      # Compilation file list
├── Flow_Control_User_Manual.docx   # Detailed user manual
├── src/
│   ├── common/
│   │   └── flow_defines.sv         # Enums, structs, type definitions
│   ├── models/
│   │   ├── traffic_model_base.sv   # Abstract base class
│   │   ├── rate_model.sv           # Constant rate: gap = (size*8) / rate
│   │   ├── token_bucket_model.sv   # Token bucket: burst then rate-limit
│   │   ├── burst_model.sv          # N packets back-to-back, then pause
│   │   ├── random_model.sv         # Stochastic IPG (3 distributions)
│   │   └── step_model.sv           # Time-segmented rate profile
│   ├── core/
│   │   ├── traffic_queue.sv        # FIFO queue with model assignment
│   │   ├── scheduler.sv            # SP / WRR / Mixed scheduling
│   │   ├── port_shaper.sv          # Port-level token bucket
│   │   └── flow_controller.sv      # Top-level orchestrator
│   └── monitor/
│       └── traffic_monitor.sv      # Per-queue stats & windowed rate check
└── test/
    ├── test_traffic_models.sv      # 19 tests — all 5 model types
    ├── test_queue.sv               # 12 tests — FIFO operations
    ├── test_scheduler.sv           # 17 tests — SP, WRR, Mixed
    ├── test_port_shaper.sv         #  4 tests — token bucket
    ├── test_flow_controller.sv     # 29 tests — integration
    └── test_monitor.sv             #  8 tests — statistics
```

---

## Quick Start

### Prerequisites

- Synopsys VCS simulator with valid license
- Linux environment

### Environment Setup

```bash
export VCS_HOME=/opt/synopsys/vcs/Q-2020.03-SP2-7
export PATH=$VCS_HOME/bin:$PATH
export LM_LICENSE_FILE=30000@<license_server>
```

### Run All Tests

```bash
make test_all
```

### Minimal Example

```systemverilog
program quick_start;
    `include "core/flow_controller.sv"

    initial begin
        flow_controller fc = new();
        byte unsigned pkt[$];
        int qid;
        byte unsigned out_data[$];
        realtime send_time;

        // Configure
        fc.set_port_rate(10000.0);       // 10 Gbps port
        fc.set_duration(100us);          // 100 us simulation

        // Add queue at 1 Gbps
        fc.add_queue(0, MODEL_RATE);
        fc.set_queue_rate(0, 1000.0);

        // Generate and push packets
        pkt = {};
        for (int i = 0; i < 1000; i++) pkt.push_back(i % 256);
        for (int i = 0; i < 100; i++)
            fc.push_packet(0, pkt);

        // Schedule
        fc.start_schedule();
        while (fc.get_next_scheduled(qid, out_data, send_time))
            ;

        // Report
        fc.report();
    end
endprogram
```

Compile and run:

```bash
vcs -full64 -sverilog -timescale=1ns/1ps \
    -f filelist.f +incdir+src quick_start.sv -o simv
./simv
```

---

## Traffic Models

### rate_model — Constant Rate

Evenly-spaced packets at a fixed rate.

```systemverilog
fc.add_queue(0, MODEL_RATE);
fc.set_queue_rate(0, 1000.0);    // 1 Gbps
```

### token_bucket_model — Rate + Burst

Tokens refill at configured rate, capped at burst size. Packets within burst are sent immediately.

```systemverilog
fc.add_queue(0, MODEL_TOKEN_BUCKET);
fc.set_queue_rate(0, 500.0);         // 500 Mbps sustained
fc.set_queue_burst(0, 16000);        // 16 KB burst
// First 16 packets of 1000B sent instantly, then rate-limited
```

### burst_model — Burst Pattern

Send N packets back-to-back, pause, repeat.

```systemverilog
fc.add_queue(0, MODEL_BURST);
fc.set_burst_param(0, 5, 10us);      // 5 pkts per burst, 10 us pause
// Pattern: [pkt pkt pkt pkt pkt] --10us-- [pkt pkt pkt pkt pkt] ...
```

### random_model — Stochastic IPG

Three distribution types for randomized inter-packet gaps.

```systemverilog
fc.add_queue(0, MODEL_RANDOM);
fc.set_random_param(0, 2000.0, DIST_UNIFORM);   // Uniform
fc.set_random_param(0, 1000.0, DIST_POISSON);   // Exponential
fc.set_random_param(0, 500.0,  DIST_NORMAL);    // Gaussian
```

### step_model — Time-Segmented Rate Profile

Rate changes over time according to a step schedule. Optional looping.

```systemverilog
fc.add_queue(0, MODEL_STEP);
begin
    step_cfg_t steps[$];
    step_cfg_t s;
    s.duration = 10us; s.rate_mbps = 1000.0; steps.push_back(s);  // 0-10us: 1G
    s.duration = 20us; s.rate_mbps = 5000.0; steps.push_back(s);  // 10-30us: 5G
    s.duration = 10us; s.rate_mbps = 500.0;  steps.push_back(s);  // 30-40us: 500M
    fc.set_step_param(0, steps);
end
```

### Custom Model

Extend `traffic_model_base` for custom behavior.

```systemverilog
class my_model extends traffic_model_base;
    virtual function realtime get_interval(int pkt_size, realtime current_time);
        return (pkt_size * 8.0) / (1000.0 * 1_000_000.0) * 1s;  // 1 Gbps
    endfunction
    virtual function void reset(); endfunction
    virtual function string to_string(); return "my_model"; endfunction
endclass

fc.add_queue(0, MODEL_CUSTOM);
begin
    my_model m = new();
    fc.set_queue_model(0, m);
end
```

---

## Scheduling Algorithms

### Strict Priority (SP)

Always serves the highest-priority queue first. Lower-priority queues only served when higher-priority queues are empty.

```systemverilog
fc.add_queue(0, MODEL_RATE);
fc.set_queue_priority(0, 3);     // Highest
fc.add_queue(1, MODEL_RATE);
fc.set_queue_priority(1, 1);     // Lowest
fc.set_scheduler_mode(SCHED_STRICT_PRIORITY);
```

### Weighted Round Robin (WRR)

Bandwidth distributed proportionally to queue weights using Deficit Round Robin (quantum = 1500 bytes).

```systemverilog
fc.add_queue(0, MODEL_RATE);
fc.set_queue_weight(0, 3);       // 75% bandwidth
fc.add_queue(1, MODEL_RATE);
fc.set_queue_weight(1, 1);       // 25% bandwidth
fc.set_scheduler_mode(SCHED_WRR);
```

### Mixed SP+WRR

Queues with `prio > 0` use SP (always preempt). Queues with `prio = 0` share remaining bandwidth via WRR.

```systemverilog
fc.add_queue(0, MODEL_RATE);
fc.set_queue_priority(0, 5);     // SP: always first
fc.add_queue(1, MODEL_RATE);
fc.set_queue_priority(1, 0);
fc.set_queue_weight(1, 3);       // WRR among prio=0 queues
fc.add_queue(2, MODEL_RATE);
fc.set_queue_priority(2, 0);
fc.set_queue_weight(2, 1);
fc.set_scheduler_mode(SCHED_SP_WRR_MIXED);
```

---

## Statistics & Monitoring

```systemverilog
// Print formatted report
fc.report();
// === Flow Controller Report ===
// Queue | Config Rate | Actual Rate | Dev    | Packets | Bytes      | Violations
// 0     | 1000.0 Mbps | 1090.9 Mbps |  9.1%  |      12 |      12000 | 0
// === END ===

// Programmatic access
queue_stats_t stats = fc.get_queue_stats(0);
$display("Rate: %.1f Mbps, Deviation: %.1f%%", stats.actual_rate_mbps, stats.deviation_pct);
```

**`queue_stats_t` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `configured_rate_mbps` | real | Expected rate |
| `actual_rate_mbps` | real | Measured rate |
| `deviation_pct` | real | Rate deviation percentage |
| `total_bytes` | longint | Total bytes sent |
| `total_packets` | longint | Total packets sent |
| `burst_max_bytes` | longint | Max bytes in any monitoring window |
| `window_violations` | int | Windows exceeding tolerance |

---

## API Reference

### flow_controller Configuration

| Method | Parameters | Description |
|--------|-----------|-------------|
| `set_port_rate()` | `real rate_mbps` | Set port bandwidth |
| `set_port_burst()` | `int burst_bytes` | Set port burst capacity |
| `set_duration()` | `realtime dur` | Set simulation duration |
| `set_debug_level()` | `int level` | Debug verbosity (0=off, 2=trace) |
| `set_scheduler_mode()` | `scheduler_mode_e mode` | Set scheduling algorithm |

### Queue Management

| Method | Parameters | Description |
|--------|-----------|-------------|
| `add_queue()` | `int queue_id, traffic_model_type_e type` | Create queue with model |
| `set_queue_rate()` | `int queue_id, real rate_mbps` | Set queue rate |
| `set_queue_burst()` | `int queue_id, int burst_bytes` | Set token bucket burst |
| `set_queue_priority()` | `int queue_id, int prio` | Set priority (for SP) |
| `set_queue_weight()` | `int queue_id, int weight` | Set weight (for WRR) |
| `set_burst_param()` | `int qid, int count, realtime pause` | Configure burst model |
| `set_random_param()` | `int qid, real rate, distribution_e dist` | Configure random model |
| `set_step_param()` | `int qid, step_cfg_t steps[$]` | Configure step model |
| `set_queue_model()` | `int qid, traffic_model_base model` | Set custom model |
| `push_packet()` | `int qid, byte unsigned data[$]` | Enqueue packet |

### Execution

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `start_schedule()` | `int pkt_count = -1` | void | Start (-1 = duration mode) |
| `get_next_scheduled()` | `out int qid, out byte[] data, out realtime time` | bit | Get next packet (0 = done) |
| `is_running()` | — | bit | Check if active |
| `report()` | — | void | Print statistics |
| `get_queue_stats()` | `int queue_id` | `queue_stats_t` | Get queue stats |

---

## Complete Example

```systemverilog
program complete_testbench;
    `include "core/flow_controller.sv"

    initial begin
        flow_controller fc = new();
        byte unsigned pkt[$];
        int qid;
        byte unsigned out_data[$];
        realtime send_time;
        int q0_count, q1_count, total;
        queue_stats_t s0, s1;

        // Configure
        fc.set_port_rate(10000.0);
        fc.set_duration(200us);

        // Queue 0: 3 Gbps, weight 3
        fc.add_queue(0, MODEL_RATE);
        fc.set_queue_rate(0, 3000.0);
        fc.set_queue_weight(0, 3);

        // Queue 1: 2 Gbps, weight 1
        fc.add_queue(1, MODEL_RATE);
        fc.set_queue_rate(1, 2000.0);
        fc.set_queue_weight(1, 1);

        fc.set_scheduler_mode(SCHED_WRR);

        // Generate packets
        pkt = {};
        for (int i = 0; i < 1500; i++) pkt.push_back(i % 256);
        for (int i = 0; i < 1000; i++) begin
            fc.push_packet(0, pkt);
            fc.push_packet(1, pkt);
        end

        // Run
        q0_count = 0; q1_count = 0; total = 0;
        fc.start_schedule();
        while (fc.get_next_scheduled(qid, out_data, send_time)) begin
            if (qid == 0) q0_count++; else q1_count++;
            total++;
        end

        // Results
        fc.report();
        s0 = fc.get_queue_stats(0);
        s1 = fc.get_queue_stats(1);

        $display("Queue 0: %0d pkts (%.1f%%), rate=%.1f Mbps",
                 q0_count, 100.0*q0_count/total, s0.actual_rate_mbps);
        $display("Queue 1: %0d pkts (%.1f%%), rate=%.1f Mbps",
                 q1_count, 100.0*q1_count/total, s1.actual_rate_mbps);
    end
endprogram
```

---

## Test Suite

| Test File | Tests | Coverage |
|-----------|-------|---------|
| `test_traffic_models.sv` | 19 | All 5 models: rate accuracy, burst behavior, random distributions, step transitions |
| `test_queue.sv` | 12 | FIFO: push/pop, depth, flush, model assignment, peek |
| `test_scheduler.sv` | 17 | SP priority, WRR fairness (3:1, 1:1, 4:2:1), drain, mixed, preemption, reset |
| `test_port_shaper.sv` | 4 | Token refill, burst exhaustion, wait time calculation |
| `test_flow_controller.sv` | 29 | Integration: data integrity, SP/WRR ordering, rate accuracy, statistics, burst flow, duration, monotonicity |
| `test_monitor.sv` | 8 | Statistics collection, multi-queue tracking, deviation, debug mode |
| **Total** | **89** | **All passing** |

```bash
make test_all           # Run all tests
make test_scheduler     # Run single test suite
make clean              # Clean build artifacts
```

---

## Build Targets

| Target | Description |
|--------|-------------|
| `make test_all` | Run all 6 test suites |
| `make test_traffic_models` | Test traffic models |
| `make test_queue` | Test queue operations |
| `make test_scheduler` | Test scheduling algorithms |
| `make test_port_shaper` | Test port rate limiter |
| `make test_flow_controller` | Test flow controller integration |
| `make test_monitor` | Test statistics monitor |
| `make clean` | Remove build artifacts |

---

## Documentation

- **[Flow_Control_User_Manual.docx](Flow_Control_User_Manual.docx)** — Detailed user manual with 11 complete usage examples
- This README — Quick reference and API guide

---

## License

Internal use. All rights reserved.
