# Cheshire HyperBus Integration and Performance Analysis

This project investigates the integration of **HyperBus / HyperRAM memory** into **Cheshire**, a modular, open-source **RISC-V System-on-Chip (SoC)**, with the goal of evaluating architectural trade-offs and performance implications in modern embedded systems.

The work focuses on memory subsystem design, interconnect behavior, and performance optimization, and was developed with the scope of a **Semester Thesis** project during my Master's degree at **ETH Zurich**.

---

## Project Overview

Modern embedded and edge systems increasingly require:
- high memory bandwidth,
- low pin count,
- low power consumption.

**HyperBus** addresses these needs, but its integration into a general-purpose SoC raises non-trivial design and performance challenges.

In this project, I:
- integrated HyperBus support into the Cheshire SoC,
- analyzed how it interacts with the existing AXI-based memory system,
- designed and evaluated alternative buffering strategies,
- measured and compared real performance using hardware counters and benchmarks.

---

## What Was Done

### 1. HyperBus Integration
- Integrated a **HyperBus/HyperRAM controller** into the Cheshire SoC memory subsystem.
- Connected the controller to the system via AXI-compatible interfaces.
- Ensured functional correctness across read/write paths and burst transfers.

### 2. Memory Architecture Exploration
- Studied and compared different memory access paths:
  - direct AXI access,
  - AXI LLC (Last-Level Cache),
  - custom buffering mechanisms.
- Analyzed latency, throughput, and contention effects.

### 3. Custom Buffer Design
- Designed and implemented a **custom coalescing buffer** to optimize HyperBus transactions.
- Reduced transaction overhead by merging smaller accesses into wider HyperBus bursts.
- Compared this approach against the existing AXI LLC in terms of efficiency and scalability.

### 4. Performance Measurement
- Implemented **performance counters** and low-level instrumentation.
- Measured:
  - cache pollution,
  - sustained bandwidth,
  - impact of burst length and access patterns.
- Benchmarks were executed directly on the RISC-V cores.

---

## Results

Key results obtained from the analysis:

- **Correct and stable integration** of HyperBus into the Cheshire SoC.
- **Improved effective bandwidth** for sequential memory accesses when using the custom coalescing buffer.
- **Reduced latency overhead** compared to naïve AXI-to-HyperBus transactions.
- Identified **trade-offs between AXI LLC and custom buffering**, highlighting when each approach is preferable.
- Demonstrated how memory access patterns strongly influence HyperBus performance.

Overall, the results show that **architecture-aware buffering strategies are crucial** to fully exploit HyperBus performance in SoC designs.

---

## Tools & Technologies

- **Cheshire RISC-V SoC**
- **SystemVerilog**
- **AXI / HyperBus protocols**
- RISC-V bare-metal software
- Performance counters and hardware profiling
- Simulation and RTL verification

---

## Relevance for Academia and Industry

This project demonstrates skills in:
- advanced SoC architecture,
- memory subsystem design,
- hardware/software co-design,
- performance evaluation and benchmarking,
- protocol-level understanding (AXI, HyperBus).

---

