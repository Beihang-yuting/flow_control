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
