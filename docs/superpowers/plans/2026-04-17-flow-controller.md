# Flow Controller Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a generic multi-queue traffic scheduling engine (SV classes) for VCS simulation, supporting per-queue traffic models, multi-mode scheduling, total port shaping, and receive-side traffic verification.

**Architecture:** Bottom-up build: defines → base model → concrete models → queue → scheduler → port shaper → top-level controller → monitor. Each layer is independently testable. Tests use the same `program` + `check` task pattern as net_packet.

**Tech Stack:** SystemVerilog (pure class, no RTL), VCS simulator, Makefile build system

**Reference project:** `/home/ubuntu/ryan/shm_work/net_packet` — follow its coding conventions: `ifndef` guards, `virtual class` for abstract bases, `program` blocks for tests, `check` task for assertions.

---

## File Structure

```
flow_control/
├── src/
│   ├── common/
│   │   └── flow_defines.sv          # all enums, typedefs, structs
│   ├── models/
│   │   ├── traffic_model_base.sv    # abstract base class
│   │   ├── rate_model.sv            # constant rate
│   │   ├── token_bucket_model.sv    # rate + burst
│   │   ├── burst_model.sv           # send N, pause M
│   │   ├── random_model.sv          # statistical distributions
│   │   └── step_model.sv            # time-segmented rate profile
│   ├── core/
│   │   ├── traffic_queue.sv         # single queue with FIFO
│   │   ├── scheduler.sv             # SP / WRR / mixed arbitration
│   │   ├── port_shaper.sv           # total port token bucket
│   │   └── flow_controller.sv       # top-level orchestrator
│   └── monitor/
│       └── traffic_monitor.sv       # receive-side verification
├── test/
│   ├── test_traffic_models.sv       # tests for all 5 models
│   ├── test_queue.sv                # queue FIFO tests
│   ├── test_scheduler.sv            # arbitration tests
│   ├── test_port_shaper.sv          # port rate limiting tests
│   ├── test_flow_controller.sv      # integration tests
│   └── test_monitor.sv              # monitor verification tests
├── Makefile
└── filelist.f
```

---

## Task 1: Project Scaffold — Makefile, filelist.f, flow_defines.sv

**Files:**
- Create: `Makefile`
- Create: `filelist.f`
- Create: `src/common/flow_defines.sv`

- [ ] **Step 1: Create Makefile**

```makefile
# Makefile
SIM ?= vcs
TOP_DIR := $(shell pwd)
SRC_DIR := $(TOP_DIR)/src
TEST_DIR := $(TOP_DIR)/test
FILELIST := $(TOP_DIR)/filelist.f

VCS_FLAGS := -full64 -sverilog -timescale=1ns/1ps -f $(FILELIST) +incdir+$(SRC_DIR)

.PHONY: compile run clean

run_%: test/test_%.sv
	@echo "=== Running test: $* ==="
	vcs $(VCS_FLAGS) $< -o simv_$* && ./simv_$*

test_traffic_models: test/test_traffic_models.sv
	$(MAKE) run_traffic_models

test_queue: test/test_queue.sv
	$(MAKE) run_queue

test_scheduler: test/test_scheduler.sv
	$(MAKE) run_scheduler

test_port_shaper: test/test_port_shaper.sv
	$(MAKE) run_port_shaper

test_flow_controller: test/test_flow_controller.sv
	$(MAKE) run_flow_controller

test_monitor: test/test_monitor.sv
	$(MAKE) run_monitor

test_all: test_traffic_models test_queue test_scheduler test_port_shaper test_flow_controller test_monitor

clean:
	rm -rf simv_* csrc *.log *.vpd *.fsdb DVEfiles
```

- [ ] **Step 2: Create filelist.f**

```
// filelist.f
+incdir+src
+incdir+src/common
+incdir+src/models
+incdir+src/core
+incdir+src/monitor

src/common/flow_defines.sv
src/models/traffic_model_base.sv
src/models/rate_model.sv
src/models/token_bucket_model.sv
src/models/burst_model.sv
src/models/random_model.sv
src/models/step_model.sv
src/core/traffic_queue.sv
src/core/scheduler.sv
src/core/port_shaper.sv
src/core/flow_controller.sv
src/monitor/traffic_monitor.sv
```

- [ ] **Step 3: Create flow_defines.sv**

```systemverilog
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
```

- [ ] **Step 4: Commit**

```bash
git add Makefile filelist.f src/common/flow_defines.sv
git commit -m "feat: project scaffold with Makefile, filelist, and flow_defines"
```

---

## Task 2: traffic_model_base — Abstract Base Class

**Files:**
- Create: `src/models/traffic_model_base.sv`

- [ ] **Step 1: Create traffic_model_base.sv**

```systemverilog
// src/models/traffic_model_base.sv
`ifndef TRAFFIC_MODEL_BASE_SV
`define TRAFFIC_MODEL_BASE_SV

`include "flow_defines.sv"

virtual class traffic_model_base;

    traffic_model_type_e model_type;
    realtime             time_unit;    // configurable, default 1us

    function new();
        this.time_unit = 1us;
    endfunction

    // Returns the inter-packet gap (time to wait before sending next packet)
    // pkt_size: size of the packet about to be sent, in bytes
    // current_time: current simulation time
    pure virtual function realtime get_interval(int pkt_size, realtime current_time);

    // Reset internal state (e.g., token count, step index)
    pure virtual function void reset();

    // Human-readable description
    pure virtual function string to_string();

endclass

`endif // TRAFFIC_MODEL_BASE_SV
```

- [ ] **Step 2: Commit**

```bash
git add src/models/traffic_model_base.sv
git commit -m "feat: add traffic_model_base abstract class"
```

---

## Task 3: rate_model — Constant Rate

**Files:**
- Create: `src/models/rate_model.sv`
- Create: `test/test_traffic_models.sv`

- [ ] **Step 1: Write the failing test for rate_model**

```systemverilog
// test/test_traffic_models.sv
`include "models/rate_model.sv"

program test_traffic_models;

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

    // Helper: check realtime within tolerance
    function automatic bit time_close(realtime actual, realtime expected, real tol_pct);
        real diff;
        if (expected == 0) return (actual == 0);
        diff = (actual - expected) / expected * 100.0;
        if (diff < 0) diff = -diff;
        return (diff < tol_pct);
    endfunction

    initial begin
        $display("=== test_traffic_models ===");

        // ---- rate_model tests ----
        begin
            rate_model rm = new();
            realtime gap;

            // 1Gbps, 1000-byte packets
            // gap = (pkt_size_bytes * 8) / (rate_mbps * 1e6) seconds
            // gap = (1000 * 8) / (1000 * 1e6) = 8e-6 s = 8us
            rm.rate_mbps = 1000.0;
            rm.reset();

            gap = rm.get_interval(1000, 0);
            check("rate_model: 1Gbps 1000B gap ~8us", time_close(gap, 8us, 1.0));

            // 10Gbps, 64-byte packets
            // gap = 64*8 / 10000e6 = 512 / 1e10 = 51.2ns
            rm.rate_mbps = 10000.0;
            rm.reset();
            gap = rm.get_interval(64, 0);
            check("rate_model: 10Gbps 64B gap ~51.2ns", time_close(gap, 51.2ns, 1.0));

            // Different packet sizes produce different gaps
            gap = rm.get_interval(1500, 0);
            check("rate_model: 10Gbps 1500B gap ~1.2us", time_close(gap, 1.2us, 1.0));
        end

        $display("\n=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TEST FAILED");
    end

endprogram
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test_traffic_models`
Expected: FAIL — `rate_model` class not defined.

- [ ] **Step 3: Implement rate_model**

```systemverilog
// src/models/rate_model.sv
`ifndef RATE_MODEL_SV
`define RATE_MODEL_SV

`include "traffic_model_base.sv"

class rate_model extends traffic_model_base;

    real rate_mbps;  // target rate in Mbps

    function new();
        super.new();
        this.model_type = MODEL_RATE;
        this.rate_mbps  = 1000.0;  // default 1Gbps
    endfunction

    // gap = (pkt_size_bytes * 8) / (rate_mbps * 1e6) seconds
    virtual function realtime get_interval(int pkt_size, realtime current_time);
        real bits;
        real rate_bps;
        bits     = pkt_size * 8.0;
        rate_bps = rate_mbps * 1_000_000.0;
        if (rate_bps <= 0) return 0;
        return (bits / rate_bps) * 1s;
    endfunction

    virtual function void reset();
        // Stateless model, nothing to reset
    endfunction

    virtual function string to_string();
        return $sformatf("rate_model: rate=%.1f Mbps", rate_mbps);
    endfunction

endclass

`endif // RATE_MODEL_SV
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test_traffic_models`
Expected: All 3 checks PASS.

- [ ] **Step 5: Commit**

```bash
git add src/models/rate_model.sv test/test_traffic_models.sv
git commit -m "feat: add rate_model with constant inter-packet gap"
```

---

## Task 4: token_bucket_model

**Files:**
- Create: `src/models/token_bucket_model.sv`
- Modify: `test/test_traffic_models.sv`

- [ ] **Step 1: Add failing tests for token_bucket_model to test_traffic_models.sv**

Add `\`include "models/token_bucket_model.sv"` after the rate_model include. Append before the `Results` display line:

```systemverilog
        // ---- token_bucket_model tests ----
        begin
            token_bucket_model tbm = new();
            realtime gap;

            // 1Gbps rate, 8000-byte burst (allows one 1000B packet burst)
            tbm.rate_mbps        = 1000.0;
            tbm.burst_size_bytes = 8000;
            tbm.reset();

            // First packet: bucket is full (8000 bytes), should send immediately (gap=0)
            gap = tbm.get_interval(1000, 0);
            check("tbm: first pkt gap is 0 (burst)", gap == 0);

            // After sending 8 x 1000B packets back-to-back (draining bucket),
            // the 9th should need to wait for tokens
            for (int i = 1; i < 8; i++) begin
                gap = tbm.get_interval(1000, 0);
            end
            // 9th packet: bucket should be near empty, gap > 0
            gap = tbm.get_interval(1000, 0);
            check("tbm: gap > 0 after burst exhausted", gap > 0);

            // After reset, bucket refills
            tbm.reset();
            gap = tbm.get_interval(1000, 0);
            check("tbm: gap is 0 after reset", gap == 0);
        end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test_traffic_models`
Expected: FAIL — `token_bucket_model` not defined.

- [ ] **Step 3: Implement token_bucket_model**

```systemverilog
// src/models/token_bucket_model.sv
`ifndef TOKEN_BUCKET_MODEL_SV
`define TOKEN_BUCKET_MODEL_SV

`include "traffic_model_base.sv"

class token_bucket_model extends traffic_model_base;

    real     rate_mbps;         // token fill rate
    int      burst_size_bytes;  // bucket capacity in bytes
    real     tokens;            // current token count in bytes
    realtime last_update_time;  // last time tokens were updated

    function new();
        super.new();
        this.model_type       = MODEL_TOKEN_BUCKET;
        this.rate_mbps        = 1000.0;
        this.burst_size_bytes = 4096;
        this.tokens           = 0;
        this.last_update_time = 0;
    endfunction

    // Refill tokens based on elapsed time
    protected function void refill(realtime current_time);
        real elapsed_sec;
        real new_tokens;
        if (current_time > last_update_time) begin
            elapsed_sec = (current_time - last_update_time) / 1s;
            new_tokens  = elapsed_sec * rate_mbps * 1_000_000.0 / 8.0; // bytes
            tokens      = tokens + new_tokens;
            if (tokens > burst_size_bytes)
                tokens = burst_size_bytes;
            last_update_time = current_time;
        end
    endfunction

    // Returns 0 if enough tokens (send immediately), else returns wait time
    virtual function realtime get_interval(int pkt_size, realtime current_time);
        real deficit;
        real rate_bytes_per_sec;
        refill(current_time);
        if (tokens >= pkt_size) begin
            tokens -= pkt_size;
            return 0;
        end
        // Calculate how long to wait for enough tokens
        deficit           = pkt_size - tokens;
        rate_bytes_per_sec = rate_mbps * 1_000_000.0 / 8.0;
        if (rate_bytes_per_sec <= 0) return 0;
        tokens = 0; // will be consumed after wait
        return (deficit / rate_bytes_per_sec) * 1s;
    endfunction

    virtual function void reset();
        tokens           = burst_size_bytes; // bucket starts full
        last_update_time = 0;
    endfunction

    virtual function string to_string();
        return $sformatf("token_bucket_model: rate=%.1f Mbps, burst=%0d B", rate_mbps, burst_size_bytes);
    endfunction

endclass

`endif // TOKEN_BUCKET_MODEL_SV
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test_traffic_models`
Expected: All 6 checks PASS.

- [ ] **Step 5: Commit**

```bash
git add src/models/token_bucket_model.sv test/test_traffic_models.sv
git commit -m "feat: add token_bucket_model with burst tolerance"
```

---

## Task 5: burst_model

**Files:**
- Create: `src/models/burst_model.sv`
- Modify: `test/test_traffic_models.sv`

- [ ] **Step 1: Add failing tests for burst_model**

Add `\`include "models/burst_model.sv"` to test file. Append before Results line:

```systemverilog
        // ---- burst_model tests ----
        begin
            burst_model bm = new();
            realtime gap;

            // Send 3 packets, then pause 100ns, repeat
            bm.send_count   = 3;
            bm.pause_time   = 100ns;
            bm.reset();

            // First 3 packets: gap = 0 (line rate burst)
            gap = bm.get_interval(100, 0);
            check("burst: pkt 1 gap=0", gap == 0);
            gap = bm.get_interval(100, 0);
            check("burst: pkt 2 gap=0", gap == 0);
            gap = bm.get_interval(100, 0);
            check("burst: pkt 3 gap=0", gap == 0);

            // 4th packet: should pause
            gap = bm.get_interval(100, 0);
            check("burst: pkt 4 gap=100ns (pause)", time_close(gap, 100ns, 1.0));

            // After pause, next 3 should be gap=0 again
            gap = bm.get_interval(100, 0);
            check("burst: pkt 5 gap=0 (new burst)", gap == 0);
        end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test_traffic_models`
Expected: FAIL — `burst_model` not defined.

- [ ] **Step 3: Implement burst_model**

```systemverilog
// src/models/burst_model.sv
`ifndef BURST_MODEL_SV
`define BURST_MODEL_SV

`include "traffic_model_base.sv"

class burst_model extends traffic_model_base;

    int      send_count;   // packets per burst
    realtime pause_time;   // pause duration between bursts
    int      sent_in_burst; // counter within current burst

    function new();
        super.new();
        this.model_type    = MODEL_BURST;
        this.send_count    = 10;
        this.pause_time    = 100ns;
        this.sent_in_burst = 0;
    endfunction

    virtual function realtime get_interval(int pkt_size, realtime current_time);
        sent_in_burst++;
        if (sent_in_burst <= send_count) begin
            return 0; // burst: send immediately
        end else begin
            sent_in_burst = 1; // reset counter (this packet counts as first of new burst)
            return pause_time;
        end
    endfunction

    virtual function void reset();
        sent_in_burst = 0;
    endfunction

    virtual function string to_string();
        return $sformatf("burst_model: send=%0d, pause=%0t", send_count, pause_time);
    endfunction

endclass

`endif // BURST_MODEL_SV
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test_traffic_models`
Expected: All 11 checks PASS.

- [ ] **Step 5: Commit**

```bash
git add src/models/burst_model.sv test/test_traffic_models.sv
git commit -m "feat: add burst_model with send/pause cycle"
```

---

## Task 6: random_model

**Files:**
- Create: `src/models/random_model.sv`
- Modify: `test/test_traffic_models.sv`

- [ ] **Step 1: Add failing tests for random_model**

Add `\`include "models/random_model.sv"` to test file. Append before Results line:

```systemverilog
        // ---- random_model tests ----
        begin
            random_model rm_rand = new();
            realtime gap;
            realtime total_gap;
            int num_samples;

            // Uniform distribution, avg rate 1Gbps, 1000B packets
            // Expected avg gap ~8us
            rm_rand.avg_rate_mbps = 1000.0;
            rm_rand.dist          = DIST_UNIFORM;
            rm_rand.reset();

            // First gap should be positive
            gap = rm_rand.get_interval(1000, 0);
            check("random_uniform: gap > 0", gap > 0);

            // Batch: check average is within 30% of expected (statistical, wide margin)
            total_gap = 0;
            num_samples = 100;
            rm_rand.reset();
            for (int i = 0; i < num_samples; i++) begin
                total_gap += rm_rand.get_interval(1000, 0);
            end
            begin
                real avg_gap_ns;
                avg_gap_ns = total_gap / num_samples / 1ns;
                // Expected: ~8000ns = 8us
                check("random_uniform: avg gap within 30% of 8us",
                      avg_gap_ns > 5600.0 && avg_gap_ns < 10400.0);
            end

            // Poisson distribution: gap should be positive
            rm_rand.dist = DIST_POISSON;
            rm_rand.reset();
            gap = rm_rand.get_interval(1000, 0);
            check("random_poisson: gap > 0", gap > 0);

            // Normal distribution: gap should be positive
            rm_rand.dist = DIST_NORMAL;
            rm_rand.reset();
            gap = rm_rand.get_interval(1000, 0);
            check("random_normal: gap > 0", gap > 0);
        end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test_traffic_models`
Expected: FAIL — `random_model` not defined.

- [ ] **Step 3: Implement random_model**

```systemverilog
// src/models/random_model.sv
`ifndef RANDOM_MODEL_SV
`define RANDOM_MODEL_SV

`include "traffic_model_base.sv"

class random_model extends traffic_model_base;

    real           avg_rate_mbps;
    distribution_e dist;

    function new();
        super.new();
        this.model_type    = MODEL_RANDOM;
        this.avg_rate_mbps = 1000.0;
        this.dist          = DIST_UNIFORM;
    endfunction

    // Generate exponential random variate for Poisson process
    // -ln(U) / lambda, where U ~ Uniform(0,1)
    protected function real exp_random(real lambda);
        real u;
        u = $urandom_range(1, 1000000) / 1000000.0; // avoid 0
        return -$ln(u) / lambda;
    endfunction

    // Generate normal random variate using Box-Muller transform
    protected function real normal_random(real mean_val, real sigma);
        real u1, u2, z;
        u1 = $urandom_range(1, 1000000) / 1000000.0;
        u2 = $urandom_range(1, 1000000) / 1000000.0;
        z  = $sqrt(-2.0 * $ln(u1)) * $cos(2.0 * 3.14159265358979 * u2);
        return mean_val + sigma * z;
    endfunction

    virtual function realtime get_interval(int pkt_size, realtime current_time);
        real mean_gap_sec;
        real gap_sec;
        real rate_bps;

        rate_bps     = avg_rate_mbps * 1_000_000.0;
        if (rate_bps <= 0) return 0;
        mean_gap_sec = (pkt_size * 8.0) / rate_bps;

        case (dist)
            DIST_UNIFORM: begin
                // Uniform between 0.5x and 1.5x mean gap
                real min_gap, max_gap, u;
                min_gap = mean_gap_sec * 0.5;
                max_gap = mean_gap_sec * 1.5;
                u       = $urandom_range(0, 1000000) / 1000000.0;
                gap_sec = min_gap + u * (max_gap - min_gap);
            end
            DIST_POISSON: begin
                // Exponential inter-arrival (Poisson process)
                real lambda;
                lambda  = 1.0 / mean_gap_sec;
                gap_sec = exp_random(lambda);
            end
            DIST_NORMAL: begin
                // Normal with sigma = 0.2 * mean
                real sigma;
                sigma   = mean_gap_sec * 0.2;
                gap_sec = normal_random(mean_gap_sec, sigma);
                if (gap_sec < 0) gap_sec = mean_gap_sec * 0.1; // clamp to positive
            end
            default: gap_sec = mean_gap_sec;
        endcase

        return gap_sec * 1s;
    endfunction

    virtual function void reset();
        // Stateless (random seed managed by simulator)
    endfunction

    virtual function string to_string();
        return $sformatf("random_model: avg_rate=%.1f Mbps, dist=%s", avg_rate_mbps, dist.name());
    endfunction

endclass

`endif // RANDOM_MODEL_SV
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test_traffic_models`
Expected: All 15 checks PASS.

- [ ] **Step 5: Commit**

```bash
git add src/models/random_model.sv test/test_traffic_models.sv
git commit -m "feat: add random_model with uniform/poisson/normal distributions"
```

---

## Task 7: step_model

**Files:**
- Create: `src/models/step_model.sv`
- Modify: `test/test_traffic_models.sv`

- [ ] **Step 1: Add failing tests for step_model**

Add `\`include "models/step_model.sv"` to test file. Append before Results line:

```systemverilog
        // ---- step_model tests ----
        begin
            step_model sm = new();
            realtime gap;
            step_cfg_t steps[$];

            // Two steps: 10us at 1Gbps, then 10us at 500Mbps
            steps.push_back('{duration: 10us, rate_mbps: 1000.0});
            steps.push_back('{duration: 10us, rate_mbps: 500.0});
            sm.steps = steps;
            sm.reset();

            // At time 0 (in step 0): 1000B pkt, gap = 8us
            gap = sm.get_interval(1000, 0);
            check("step: t=0 gap ~8us (1Gbps)", time_close(gap, 8us, 1.0));

            // At time 11us (in step 1): 1000B pkt, gap = 16us (500Mbps)
            gap = sm.get_interval(1000, 11us);
            check("step: t=11us gap ~16us (500Mbps)", time_close(gap, 16us, 1.0));

            // At time 25us (past all steps, no looping): should return 0
            gap = sm.get_interval(1000, 25us);
            check("step: t=25us past end gap=0", gap == 0);

            // With looping enabled
            sm.loop_enable = 1;
            sm.reset();
            // Total step duration = 20us. At t=21us -> loops back to step 0
            gap = sm.get_interval(1000, 21us);
            check("step: t=21us loop back to 1Gbps gap ~8us", time_close(gap, 8us, 1.0));
        end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test_traffic_models`
Expected: FAIL — `step_model` not defined.

- [ ] **Step 3: Implement step_model**

```systemverilog
// src/models/step_model.sv
`ifndef STEP_MODEL_SV
`define STEP_MODEL_SV

`include "traffic_model_base.sv"

class step_model extends traffic_model_base;

    step_cfg_t steps[$];
    bit        loop_enable;

    function new();
        super.new();
        this.model_type  = MODEL_STEP;
        this.loop_enable = 0;
    endfunction

    // Find which step is active at current_time, return its rate
    protected function real get_active_rate(realtime current_time);
        realtime elapsed;
        realtime total_duration;
        realtime step_start;

        // Calculate total duration
        total_duration = 0;
        foreach (steps[i]) total_duration += steps[i].duration;

        if (total_duration == 0) return 0;

        elapsed = current_time;

        // Handle looping
        if (loop_enable && elapsed >= total_duration) begin
            while (elapsed >= total_duration)
                elapsed -= total_duration;
        end

        // Find active step
        step_start = 0;
        foreach (steps[i]) begin
            if (elapsed >= step_start && elapsed < step_start + steps[i].duration)
                return steps[i].rate_mbps;
            step_start += steps[i].duration;
        end

        return 0; // past all steps, not looping
    endfunction

    virtual function realtime get_interval(int pkt_size, realtime current_time);
        real rate_mbps_now;
        real bits;
        real rate_bps;

        rate_mbps_now = get_active_rate(current_time);
        if (rate_mbps_now <= 0) return 0;

        bits     = pkt_size * 8.0;
        rate_bps = rate_mbps_now * 1_000_000.0;
        return (bits / rate_bps) * 1s;
    endfunction

    virtual function void reset();
        // Stateless relative to time
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("step_model: %0d steps, loop=%0b", steps.size(), loop_enable);
        foreach (steps[i])
            s = {s, $sformatf("\n  [%0d] dur=%0t rate=%.1f Mbps", i, steps[i].duration, steps[i].rate_mbps)};
        return s;
    endfunction

endclass

`endif // STEP_MODEL_SV
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test_traffic_models`
Expected: All 19 checks PASS.

- [ ] **Step 5: Commit**

```bash
git add src/models/step_model.sv test/test_traffic_models.sv
git commit -m "feat: add step_model with time-segmented rate profile and looping"
```

---

## Task 8: traffic_queue

**Files:**
- Create: `src/core/traffic_queue.sv`
- Create: `test/test_queue.sv`

- [ ] **Step 1: Write failing test**

```systemverilog
// test/test_queue.sv
`include "core/traffic_queue.sv"

program test_queue;

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
        $display("=== test_queue ===");

        begin
            traffic_queue q = new(0);
            byte unsigned pkt1[$] = '{8'hAA, 8'hBB, 8'hCC};
            byte unsigned pkt2[$] = '{8'h11, 8'h22};
            byte unsigned out[$];

            check("queue: initially empty", !q.has_packet());
            check("queue: depth is 0", q.get_depth() == 0);

            q.push_packet(pkt1);
            check("queue: has packet after push", q.has_packet());
            check("queue: depth is 1", q.get_depth() == 1);

            q.push_packet(pkt2);
            check("queue: depth is 2", q.get_depth() == 2);

            q.get_next_packet(out);
            check("queue: first out is pkt1", out.size() == 3 && out[0] == 8'hAA);

            q.get_next_packet(out);
            check("queue: second out is pkt2", out.size() == 2 && out[0] == 8'h11);

            check("queue: empty after drain", !q.has_packet());
        end

        // Test with model assignment
        begin
            traffic_queue q = new(5);
            rate_model rm = new();
            rm.rate_mbps = 2000.0;
            q.set_model(rm);
            check("queue: model assigned", q.model != null);
            check("queue: queue_id is 5", q.queue_id == 5);
        end

        // Test peek_next_size
        begin
            traffic_queue q = new(0);
            byte unsigned pkt[$] = '{8'h01, 8'h02, 8'h03, 8'h04};
            q.push_packet(pkt);
            check("queue: peek size is 4", q.peek_next_size() == 4);
        end

        // Test flush
        begin
            traffic_queue q = new(0);
            byte unsigned pkt[$] = '{8'hFF};
            q.push_packet(pkt);
            q.push_packet(pkt);
            q.flush();
            check("queue: empty after flush", !q.has_packet());
        end

        $display("\n=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TEST FAILED");
    end

endprogram
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test_queue`
Expected: FAIL — `traffic_queue` not defined.

- [ ] **Step 3: Implement traffic_queue**

```systemverilog
// src/core/traffic_queue.sv
`ifndef TRAFFIC_QUEUE_SV
`define TRAFFIC_QUEUE_SV

`include "traffic_model_base.sv"
`include "rate_model.sv"
`include "token_bucket_model.sv"
`include "burst_model.sv"
`include "random_model.sv"
`include "step_model.sv"

class traffic_queue;

    int                  queue_id;
    traffic_model_base   model;
    int                  priority;    // for SP scheduling (higher = higher priority)
    int                  weight;      // for WRR scheduling

    protected byte unsigned pkt_fifo[$][$]; // queue of byte arrays

    function new(int id);
        this.queue_id = id;
        this.model    = null;
        this.priority = 0;
        this.weight   = 1;
    endfunction

    function void set_model(traffic_model_base m);
        this.model = m;
    endfunction

    function void push_packet(byte unsigned data[$]);
        pkt_fifo.push_back(data);
    endfunction

    function bit has_packet();
        return pkt_fifo.size() > 0;
    endfunction

    function int get_depth();
        return pkt_fifo.size();
    endfunction

    function void get_next_packet(output byte unsigned data[$]);
        if (pkt_fifo.size() > 0) begin
            data = pkt_fifo[0];
            pkt_fifo.delete(0);
        end else begin
            data = '{};
        end
    endfunction

    // Peek at next packet size without dequeuing
    function int peek_next_size();
        if (pkt_fifo.size() > 0)
            return pkt_fifo[0].size();
        return 0;
    endfunction

    function void flush();
        pkt_fifo.delete();
    endfunction

endclass

`endif // TRAFFIC_QUEUE_SV
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test_queue`
Expected: All 12 checks PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/traffic_queue.sv test/test_queue.sv
git commit -m "feat: add traffic_queue with FIFO and model assignment"
```

---

## Task 9: scheduler

**Files:**
- Create: `src/core/scheduler.sv`
- Create: `test/test_scheduler.sv`

- [ ] **Step 1: Write failing test**

```systemverilog
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
            q1.priority = 3; // highest
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

            // Remove q1's packet, should select q2 next
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

            // Push many packets
            for (int i = 0; i < 100; i++) begin
                q0.push_packet(dummy);
                q1.push_packet(dummy);
            end

            queues[0] = q0;
            queues[1] = q1;

            sched.mode = SCHED_WRR;
            count0 = 0;
            count1 = 0;

            // Select 40 times; expect ~30 from q0, ~10 from q1
            for (int i = 0; i < 40; i++) begin
                selected = sched.select_queue(queues);
                if (selected == 0) count0++;
                else count1++;
                // Consume the selected packet
                if (selected == 0) begin byte unsigned tmp[$]; q0.get_next_packet(tmp); end
                else begin byte unsigned tmp[$]; q1.get_next_packet(tmp); end
            end

            check("wrr: q0 gets ~75%", count0 >= 25 && count0 <= 35);
            check("wrr: q1 gets ~25%", count1 >= 5 && count1 <= 15);
        end

        // ---- SP+WRR Mixed ----
        begin
            scheduler sched = new();
            traffic_queue q0 = new(0); // SP priority=2
            traffic_queue q1 = new(1); // WRR (priority=0)
            traffic_queue q2 = new(2); // WRR (priority=0)
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

            // SP queue should be selected first
            selected = sched.select_queue(queues);
            check("mixed: SP queue q0 first", selected == 0);

            // After q0 is empty, WRR among q1 and q2
            q0.get_next_packet(dummy);
            selected = sched.select_queue(queues);
            check("mixed: WRR selects q1 or q2", selected == 1 || selected == 2);
        end

        // ---- No packets: returns -1 ----
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test_scheduler`
Expected: FAIL — `scheduler` not defined.

- [ ] **Step 3: Implement scheduler**

```systemverilog
// src/core/scheduler.sv
`ifndef SCHEDULER_SV
`define SCHEDULER_SV

`include "traffic_queue.sv"

class scheduler;

    scheduler_mode_e mode;

    // DWRR state: deficit counters per queue
    protected int deficit_counter[int]; // keyed by queue_id
    protected int wrr_queue_ids[$];     // ordered list for round-robin
    protected int wrr_index;            // current position in round-robin

    function new();
        this.mode      = SCHED_STRICT_PRIORITY;
        this.wrr_index = 0;
    endfunction

    // Returns queue_id of the queue that should send next
    // Returns -1 if no queue has packets
    function int select_queue(traffic_queue queues[int]);
        case (mode)
            SCHED_STRICT_PRIORITY: return select_sp(queues);
            SCHED_WRR:             return select_wrr(queues);
            SCHED_SP_WRR_MIXED:    return select_mixed(queues);
            default:               return -1;
        endcase
    endfunction

    // Strict Priority: pick highest priority queue with packets
    protected function int select_sp(traffic_queue queues[int]);
        int best_id = -1;
        int best_pri = -1;
        foreach (queues[id]) begin
            if (queues[id].has_packet() && queues[id].priority > best_pri) begin
                best_pri = queues[id].priority;
                best_id  = id;
            end
        end
        return best_id;
    endfunction

    // Weighted Round-Robin using Deficit Weighted Round-Robin (DWRR)
    protected function int select_wrr(traffic_queue queues[int]);
        int quantum = 1500; // bytes, one MTU-sized quantum
        int attempts;

        // Build queue list if needed
        if (wrr_queue_ids.size() == 0) begin
            foreach (queues[id]) wrr_queue_ids.push_back(id);
        end

        attempts = 0;
        while (attempts < wrr_queue_ids.size() * 2) begin
            int qid;
            if (wrr_index >= wrr_queue_ids.size())
                wrr_index = 0;
            qid = wrr_queue_ids[wrr_index];

            if (queues.exists(qid) && queues[qid].has_packet()) begin
                // Add weighted quantum to deficit
                if (!deficit_counter.exists(qid))
                    deficit_counter[qid] = 0;
                deficit_counter[qid] += quantum * queues[qid].weight;

                if (deficit_counter[qid] >= queues[qid].peek_next_size()) begin
                    deficit_counter[qid] -= queues[qid].peek_next_size();
                    wrr_index++;
                    return qid;
                end
            end
            wrr_index++;
            attempts++;
        end

        return -1;
    endfunction

    // SP+WRR Mixed: SP queues (priority > 0) first, then WRR for rest
    protected function int select_mixed(traffic_queue queues[int]);
        // First: check SP queues
        begin
            int best_id = -1;
            int best_pri = 0; // only priority > 0 counts as SP
            foreach (queues[id]) begin
                if (queues[id].has_packet() && queues[id].priority > best_pri) begin
                    best_pri = queues[id].priority;
                    best_id  = id;
                end
            end
            if (best_id >= 0) return best_id;
        end

        // Then: WRR among priority == 0 queues
        begin
            traffic_queue wrr_queues[int];
            foreach (queues[id]) begin
                if (queues[id].priority == 0)
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test_scheduler`
Expected: All 7 checks PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/scheduler.sv test/test_scheduler.sv
git commit -m "feat: add scheduler with SP, WRR, and mixed modes"
```

---

## Task 10: port_shaper

**Files:**
- Create: `src/core/port_shaper.sv`
- Create: `test/test_port_shaper.sv`

- [ ] **Step 1: Write failing test**

```systemverilog
// test/test_port_shaper.sv
`include "core/port_shaper.sv"

program test_port_shaper;

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
        $display("=== test_port_shaper ===");

        begin
            port_shaper ps = new();
            bit ok;

            // 10Gbps port, 16000 byte burst
            ps.port_rate_mbps   = 10000.0;
            ps.burst_size_bytes = 16000;
            ps.reset();

            // Bucket starts full. First packet should pass immediately.
            ok = ps.can_send(1500, 0);
            check("shaper: first pkt can send", ok);
            ps.consume(1500, 0);

            // Send more packets until burst is exhausted
            for (int i = 0; i < 9; i++) begin
                ok = ps.can_send(1500, 0);
                if (ok) ps.consume(1500, 0);
            end

            // After ~10 x 1500B = 15000B consumed at time 0, bucket has ~1000B
            // 11th 1500B packet should be blocked
            ok = ps.can_send(1500, 0);
            check("shaper: blocked after burst exhausted", !ok);

            // After some time, tokens refill. At 10Gbps:
            // refill rate = 10e9/8 = 1.25e9 bytes/sec
            // At time = 1us, refill = 1250 bytes, total ~2250, should be enough
            ok = ps.can_send(1500, 1us);
            check("shaper: can send after refill at 1us", ok);
        end

        // Test: get_wait_time
        begin
            port_shaper ps = new();
            realtime wt;

            ps.port_rate_mbps   = 1000.0; // 1Gbps
            ps.burst_size_bytes = 0;       // no burst tolerance
            ps.reset();

            // No burst: bucket starts at 0
            // Need 1500 bytes. rate = 125e6 bytes/sec
            // wait = 1500/125e6 = 12us
            wt = ps.get_wait_time(1500, 0);
            check("shaper: wait time ~12us at 1Gbps for 1500B",
                  wt > 11us && wt < 13us);
        end

        $display("\n=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TEST FAILED");
    end

endprogram
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test_port_shaper`
Expected: FAIL — `port_shaper` not defined.

- [ ] **Step 3: Implement port_shaper**

```systemverilog
// src/core/port_shaper.sv
`ifndef PORT_SHAPER_SV
`define PORT_SHAPER_SV

`include "flow_defines.sv"

class port_shaper;

    real     port_rate_mbps;
    int      burst_size_bytes;
    real     tokens;            // current tokens in bytes
    realtime last_update_time;

    function new();
        this.port_rate_mbps   = 10000.0;  // default 10Gbps
        this.burst_size_bytes = 16000;
        this.tokens           = 0;
        this.last_update_time = 0;
    endfunction

    protected function void refill(realtime current_time);
        real elapsed_sec;
        real new_tokens;
        if (current_time > last_update_time) begin
            elapsed_sec = (current_time - last_update_time) / 1s;
            new_tokens  = elapsed_sec * port_rate_mbps * 1_000_000.0 / 8.0;
            tokens     += new_tokens;
            if (tokens > burst_size_bytes && burst_size_bytes > 0)
                tokens = burst_size_bytes;
            last_update_time = current_time;
        end
    endfunction

    function bit can_send(int pkt_size, realtime current_time);
        refill(current_time);
        return (tokens >= pkt_size);
    endfunction

    function void consume(int pkt_size, realtime current_time);
        refill(current_time);
        tokens -= pkt_size;
        if (tokens < 0) tokens = 0;
    endfunction

    // Calculate how long to wait before pkt_size bytes are available
    function realtime get_wait_time(int pkt_size, realtime current_time);
        real deficit;
        real rate_bytes_per_sec;
        refill(current_time);
        if (tokens >= pkt_size) return 0;
        deficit           = pkt_size - tokens;
        rate_bytes_per_sec = port_rate_mbps * 1_000_000.0 / 8.0;
        if (rate_bytes_per_sec <= 0) return 0;
        return (deficit / rate_bytes_per_sec) * 1s;
    endfunction

    function void reset();
        tokens           = burst_size_bytes; // start full
        last_update_time = 0;
    endfunction

endclass

`endif // PORT_SHAPER_SV
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test_port_shaper`
Expected: All 4 checks PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/port_shaper.sv test/test_port_shaper.sv
git commit -m "feat: add port_shaper with token bucket rate limiting"
```

---

## Task 11: traffic_monitor

**Files:**
- Create: `src/monitor/traffic_monitor.sv`
- Create: `test/test_monitor.sv`

- [ ] **Step 1: Write failing test**

```systemverilog
// test/test_monitor.sv
`include "monitor/traffic_monitor.sv"

program test_monitor;

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
        $display("=== test_monitor ===");

        // Basic recording and stats
        begin
            traffic_monitor mon = new();
            queue_stats_t stats;

            mon.window_size    = 10us;
            mon.tolerance_pct  = 5.0;

            // Register queue 0 with expected rate 1Gbps
            mon.register_queue(0, 1000.0);

            // Simulate 1Gbps traffic: 1000B packets every 8us for 100us
            // That's 12 packets in ~96us
            for (int i = 0; i < 12; i++) begin
                mon.record(0, 1000, i * 8us);
            end

            mon.finalize(100us);
            stats = mon.get_stats(0);

            check("monitor: total_packets = 12", stats.total_packets == 12);
            check("monitor: total_bytes = 12000", stats.total_bytes == 12000);
            // actual rate = 12000 * 8 / 100us = 960 Mbps
            check("monitor: actual rate ~960Mbps",
                  stats.actual_rate_mbps > 900.0 && stats.actual_rate_mbps < 1100.0);
            check("monitor: deviation < 10%",
                  stats.deviation_pct > -10.0 && stats.deviation_pct < 10.0);
        end

        // Multiple queues
        begin
            traffic_monitor mon = new();
            queue_stats_t s0, s1;

            mon.window_size   = 10us;
            mon.tolerance_pct = 5.0;
            mon.register_queue(0, 1000.0);
            mon.register_queue(1, 500.0);

            // Queue 0: 1Gbps (1000B every 8us)
            for (int i = 0; i < 10; i++)
                mon.record(0, 1000, i * 8us);

            // Queue 1: 500Mbps (1000B every 16us)
            for (int i = 0; i < 5; i++)
                mon.record(1, 1000, i * 16us);

            mon.finalize(80us);
            s0 = mon.get_stats(0);
            s1 = mon.get_stats(1);

            check("monitor_multi: q0 pkts=10", s0.total_packets == 10);
            check("monitor_multi: q1 pkts=5", s1.total_packets == 5);
            check("monitor_multi: q0 rate > q1 rate",
                  s0.actual_rate_mbps > s1.actual_rate_mbps);
        end

        // Debug trace (level 2) — just verify no crash
        begin
            traffic_monitor mon = new();
            mon.debug_level = 2;
            mon.register_queue(0, 1000.0);
            mon.record(0, 1500, 10us);
            mon.record(0, 1500, 20us);
            mon.finalize(30us);
            check("monitor_debug: no crash with debug_level=2", 1);
        end

        $display("\n=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TEST FAILED");
    end

endprogram
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test_monitor`
Expected: FAIL — `traffic_monitor` not defined.

- [ ] **Step 3: Implement traffic_monitor**

```systemverilog
// src/monitor/traffic_monitor.sv
`ifndef TRAFFIC_MONITOR_SV
`define TRAFFIC_MONITOR_SV

`include "flow_defines.sv"

class traffic_monitor;

    realtime window_size;
    real     tolerance_pct;
    int      debug_level;     // 0=off, 1=summary, 2=per-packet

    // Per-queue tracking
    protected real     configured_rate[int];   // queue_id -> rate_mbps
    protected longint  total_bytes[int];
    protected longint  total_packets[int];
    protected longint  burst_max_bytes[int];

    // Per-window tracking
    protected longint  window_bytes[int];      // current window bytes per queue
    protected int      window_violations[int];
    protected realtime window_start_time;

    // Overall timing
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

        // Check if we crossed a window boundary
        while (recv_time >= window_start_time + window_size) begin
            check_all_windows();
            window_start_time += window_size;
        end

        total_bytes[queue_id]   += pkt_size;
        total_packets[queue_id] += 1;
        window_bytes[queue_id]  += pkt_size;

        // Track burst max
        if (window_bytes[queue_id] > burst_max_bytes[queue_id])
            burst_max_bytes[queue_id] = window_bytes[queue_id];

        last_record_time = recv_time;

        if (debug_level >= 2) begin
            $display("[%0t] RX queue=%0d pkt_size=%0d", recv_time, queue_id, pkt_size);
        end
    endfunction

    // Check all queues at window boundary
    protected function void check_all_windows();
        foreach (configured_rate[qid]) begin
            check_window(qid);
            window_bytes[qid] = 0; // reset for next window
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

    // Call at end of simulation to compute final stats
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

            $display("%-6d| %7.1f Mbps| %7.1f Mbps| %+6.1f%%   | %7d | %10d | %d",
                     qid,
                     s.configured_rate_mbps, s.actual_rate_mbps, s.deviation_pct,
                     s.total_packets, s.total_bytes, s.window_violations);
        end

        $display("\nTotal: %0d packets, %0d bytes", grand_total_packets, grand_total_bytes);
        $display("=== END ===\n");
    endfunction

endclass

`endif // TRAFFIC_MONITOR_SV
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test_monitor`
Expected: All 8 checks PASS.

- [ ] **Step 5: Commit**

```bash
git add src/monitor/traffic_monitor.sv test/test_monitor.sv
git commit -m "feat: add traffic_monitor with windowed stats and report"
```

---

## Task 12: flow_controller — Top-Level Orchestrator

**Files:**
- Create: `src/core/flow_controller.sv`
- Create: `test/test_flow_controller.sv`

- [ ] **Step 1: Write failing test**

```systemverilog
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

            fc.set_port_rate(10000.0);  // 10Gbps
            fc.set_duration(50us);

            // Add 2 queues with rate model
            fc.add_queue(0, MODEL_RATE);
            fc.set_queue_rate(0, 2000.0);  // 2Gbps

            fc.add_queue(1, MODEL_RATE);
            fc.set_queue_rate(1, 1000.0);  // 1Gbps

            fc.set_scheduler_mode(SCHED_WRR);
            fc.set_queue_weight(0, 2);
            fc.set_queue_weight(1, 1);

            // Push packets (use small packets for fast sim)
            pkt = new[64];
            foreach (pkt[i]) pkt[i] = i;
            for (int i = 0; i < 200; i++) begin
                fc.push_packet(0, pkt);
                fc.push_packet(1, pkt);
            end

            check("fc: queues configured", 1);

            // Use get_next_scheduled mode
            sent_count = 0;
            fc.start_schedule();
            while (fc.get_next_scheduled(out_queue_id, out_data, out_send_time)) begin
                sent_count++;
                if (sent_count > 10000) break; // safety limit
            end

            check("fc: sent some packets", sent_count > 0);
            check("fc: sent < 10000 (duration limit)", sent_count < 10000);

            // Report
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
            fc.set_duration(1000us); // very long duration

            fc.add_queue(0, MODEL_RATE);
            fc.set_queue_rate(0, 5000.0);

            pkt = new[128];
            for (int i = 0; i < 100; i++)
                fc.push_packet(0, pkt);

            // pkt_count = 50: should stop after 50 packets
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

            // Register with monitor manually for custom model
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

        // ---- Token bucket model with burst ----
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
            // First 8 packets should be burst (near zero gap)
            check("fc_tbm: first 10 pkts arrive quickly (burst)",
                  tenth_time - first_time < 5us);
            check("fc_tbm: sent packets", sent_count > 0);
        end

        $display("\n=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count > 0) $fatal(1, "TEST FAILED");
    end

endprogram
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test_flow_controller`
Expected: FAIL — `flow_controller` not defined.

- [ ] **Step 3: Implement flow_controller**

```systemverilog
// src/core/flow_controller.sv
`ifndef FLOW_CONTROLLER_SV
`define FLOW_CONTROLLER_SV

`include "scheduler.sv"
`include "port_shaper.sv"
`include "traffic_monitor.sv"

class flow_controller;

    // Internal components
    protected scheduler       sched;
    protected port_shaper     shaper;
    protected traffic_monitor monitor;
    protected traffic_queue   queues[int];

    // Configuration
    protected realtime duration;
    protected realtime time_unit_val;
    protected int      debug_level;

    // Runtime state
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

    // ---- Configuration API ----

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

    // ---- Queue Management ----

    function void add_queue(int queue_id, traffic_model_type_e model_type);
        traffic_queue q = new(queue_id);
        traffic_model_base m;

        case (model_type)
            MODEL_RATE:         begin rate_model rm = new();          m = rm; end
            MODEL_TOKEN_BUCKET: begin token_bucket_model tb = new();  m = tb; end
            MODEL_BURST:        begin burst_model bm = new();         m = bm; end
            MODEL_RANDOM:       begin random_model rdm = new();       m = rdm; end
            MODEL_STEP:         begin step_model sm = new();          m = sm; end
            MODEL_CUSTOM:       m = null; // user sets via set_queue_model
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

    function void set_queue_priority(int queue_id, int priority);
        if (queues.exists(queue_id))
            queues[queue_id].priority = priority;
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

    function void set_random_param(int queue_id, real avg_rate, distribution_e dist);
        random_model rdm;
        if (!queues.exists(queue_id)) return;
        if ($cast(rdm, queues[queue_id].model)) begin
            rdm.avg_rate_mbps = avg_rate;
            rdm.dist          = dist;
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

    // ---- Packet Input ----

    function void push_packet(int queue_id, byte unsigned data[$]);
        if (queues.exists(queue_id))
            queues[queue_id].push_packet(data);
    endfunction

    // ---- Execution: Standalone Scheduler Mode ----

    function void start_schedule(int pkt_count = -1);
        current_time    = 0;
        total_sent      = 0;
        pkt_limit       = pkt_count;
        is_running_flag = 1;

        // Reset all models
        foreach (queues[id]) begin
            if (queues[id].model != null)
                queues[id].model.reset();
        end
        shaper.reset();
        sched.reset();
    endfunction

    // Returns 1 if a packet was scheduled, 0 if done
    function bit get_next_scheduled(output int queue_id, output byte unsigned data[$], output realtime send_time);
        int selected_id;
        realtime model_interval;
        realtime port_wait;
        int pkt_size;

        if (!is_running_flag) return 0;

        // Check termination: duration
        if (current_time >= duration) begin
            is_running_flag = 0;
            return 0;
        end

        // Check termination: packet count
        if (pkt_limit > 0 && total_sent >= pkt_limit) begin
            is_running_flag = 0;
            return 0;
        end

        // Select queue
        selected_id = sched.select_queue(queues);
        if (selected_id < 0) begin
            is_running_flag = 0;
            return 0; // no queue has packets
        end

        pkt_size = queues[selected_id].peek_next_size();

        // Get model interval
        if (queues[selected_id].model != null)
            model_interval = queues[selected_id].model.get_interval(pkt_size, current_time);
        else
            model_interval = 0;

        // Advance time by model interval
        current_time += model_interval;

        // Check port shaper
        port_wait = shaper.get_wait_time(pkt_size, current_time);
        current_time += port_wait;

        // Check duration again after time advance
        if (current_time >= duration) begin
            is_running_flag = 0;
            return 0;
        end

        // Dequeue and output
        shaper.consume(pkt_size, current_time);
        queues[selected_id].get_next_packet(data);

        queue_id  = selected_id;
        send_time = current_time;
        total_sent++;

        // Record in monitor
        monitor.record(selected_id, pkt_size, current_time);

        if (debug_level >= 2) begin
            $display("[%0t] TX queue=%0d pkt_size=%0d", current_time, selected_id, pkt_size);
        end

        return 1;
    endfunction

    function bit is_running();
        return is_running_flag;
    endfunction

    // ---- Monitor: Receive Side ----

    function void monitor_packet(int queue_id, byte unsigned data[$], realtime recv_time);
        monitor.record(queue_id, data.size(), recv_time);
    endfunction

    // ---- Report ----

    function void report();
        monitor.finalize(current_time);
        monitor.report();
    endfunction

    function queue_stats_t get_queue_stats(int queue_id);
        return monitor.get_stats(queue_id);
    endfunction

endclass

`endif // FLOW_CONTROLLER_SV
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test_flow_controller`
Expected: All 7 checks PASS.

- [ ] **Step 5: Commit**

```bash
git add src/core/flow_controller.sv test/test_flow_controller.sv
git commit -m "feat: add flow_controller top-level orchestrator with scheduler mode"
```

---

## Task 13: Git Init and Final Verification

**Files:**
- All files created above

- [ ] **Step 1: Initialize git repo**

```bash
cd /home/ubuntu/ryan/shm_work/flow_control
git init
git add .
git commit -m "feat: flow_control multi-queue traffic scheduling engine

Implements a generic multi-queue traffic scheduling engine for VCS simulation:
- 5 built-in traffic models (rate, token_bucket, burst, random, step)
- 3 scheduling modes (SP, WRR, SP+WRR mixed)
- Port-level token bucket shaping
- Receive-side traffic monitor with windowed stats and report
- Extensible via inheritance and callback"
```

- [ ] **Step 2: Run all tests**

```bash
make test_all
```

Expected: All test programs compile and pass.

- [ ] **Step 3: Fix any compilation or test failures**

Address issues incrementally until `make test_all` passes clean.

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve compilation and test issues from integration"
```
