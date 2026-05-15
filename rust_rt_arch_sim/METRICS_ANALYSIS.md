# Simulation Metrics Analysis Guide

## Overview

This guide explains how to analyze the simulation output metrics after running the RustSim raytracer simulator.

## Quick Start

### 1. Run the Simulation
```bash
cd rust_rt_arch_sim
cargo build --release
cargo run --release
```

The simulation will generate `.npy` files in the `sim_logs/` directory.

### 2. Quick Statistics (< 1 second)
```bash
python quick_stats.py
```

Provides immediate overview of key metrics:
- AABB test instructions and cycles
- Triangle test instructions and cycles
- Memory operation split (local vs remote)
- NOC priority comparison (high vs low)

### 3. Full Analysis (5-10 seconds)
```bash
python analyze_metrics.py
```

Generates comprehensive report including:
- Detailed instruction/cycle metrics
- Memory utilization analysis
- NOC performance breakdown by direction
- Spatial analysis (hotspots)
- Visualizations (PNG charts)
- JSON report for further processing

## Output Files

After running `analyze_metrics.py`, you'll find:
- `sim_logs/metrics_analysis.png` - 4-panel visualization
- `sim_logs/noc_memory_analysis.png` - Detailed NOC/memory charts
- `sim_logs/metrics_report.json` - All metrics in JSON format

## Key Metrics Explained

### Instruction & Cycle Metrics

**AABB Tests**
- Count of AABB branch instructions executed
- Cycles spent in AABB test regions
- Average cycles per test = total_cycles / total_instructions

**Triangle Tests**
- Count of triangle intersection test instructions
- Cycles spent in triangle test regions
- Average cycles per test = total_cycles / total_instructions

### Memory Utilization

**Operations**
- `memory_operations_close`: Local DRAM accesses (same stack)
- `memory_operations_far`: Remote DRAM accesses (different stack)

**Bytes Transferred**
- Breakdown of read/write operations by locality
- Local/far ratio indicates data locality efficiency

### NOC Performance

**Priority Classes**
- **High Priority** (mailbox < 32): Critical control/synchronization flits
  - Lower congestion expected
  - Should have better throughput
  
- **Low Priority** (mailbox >= 32): Regular data flits
  - May experience higher congestion
  - Resource-starved by high priority

**Directional Breakdown**
- UP, DOWN, LEFT, RIGHT: Mesh network directions
- Shows if bottlenecks are location-dependent

**Congestion Rate**
- Percentage of flit attempts that hit a full lane
- Higher rate = NOC bottleneck
- Target: < 10% for healthy network

## Interpreting Results

### Performance Indicators

✅ **Good Signs**
- Low average cycles per AABB/triangle test (< 10)
- High local memory operation percentage (> 70%)
- Low NOC congestion rate (< 10%)
- High priority flits have better congestion rates than low priority
- Memory-intensive cores clustered together (good spatial locality)

⚠️ **Warning Signs**
- High cycles per test (> 20) → Stalls, dependencies, or poor pipelining
- High remote memory percentage (> 30%) → Poor data placement
- High NOC congestion (> 20%) → Communication bottleneck
- Uneven distribution across cores → Load imbalance
- High priority congestion rate → Critical path being blocked

### Analysis Workflow

1. **Start with quick_stats.py** to get immediate overview
2. **Identify bottlenecks** from the ratios
3. **Run analyze_metrics.py** for detailed breakdown
4. **Check visualizations** for spatial patterns
5. **Review JSON report** for programmatic analysis

## Advanced Usage

### Processing JSON Report

```python
import json

with open('sim_logs/metrics_report.json') as f:
    report = json.load(f)

# Access specific metrics
aabb_instr = report['instruction_metrics']['total_aabb_instructions']
memory_ops = report['memory_metrics']['total_memory_operations']
noc_util = report['noc_metrics']['high_priority_noc_util']
```

### Custom Metrics

To add your own analysis, edit `analyze_metrics.py`:

```python
def my_custom_analysis(metrics):
    # Load any .npy file from sim_logs/
    custom_data = metrics['your_metric_name']
    # Perform analysis
    result = custom_data.sum()
    return result
```

## Troubleshooting

**"No metrics found in sim_logs/"**
- Ensure simulation completed successfully
- Check that sim_logs/ directory exists
- Run `ls sim_logs/*.npy` to verify files were created

**Import errors (numpy, matplotlib)**
```bash
pip install numpy matplotlib seaborn
```

**Plots not showing**
- Plots are saved as PNG files, not displayed to screen
- Check `sim_logs/` for .png files

## Files Generated

### Core Metrics (.npy files)
- `aabb_instruction_count.npy` - Per-core AABB instruction counts
- `triangle_instruction_count.npy` - Per-core triangle test counts
- `aabb_cycle_count.npy` - Cycles spent in AABB regions
- `triangle_cycle_count.npy` - Cycles spent in triangle regions
- `memory_operations_close.npy` - Per-core local memory ops
- `memory_operations_far.npy` - Per-core remote memory ops
- `high_priority_noc_util.npy` - High priority NOC utilization timeline
- `high_priority_noc_congestion.npy` - High priority congestion timeline
- `low_priority_noc_util.npy` - Low priority NOC utilization timeline
- `low_priority_noc_congestion.npy` - Low priority congestion timeline

### Derived Output Files
- `metrics_analysis.png` - Main visualization dashboard
- `noc_memory_analysis.png` - Detailed NOC/memory charts
- `metrics_report.json` - Complete metrics in JSON

## References

- NOC Priority Threshold: `mailbox_id < 32` = High priority
- Core Coordinate System: `(x, y)` where x=0..31, y=0..31 in each stack
- Congestion Rate = congestion_events / (util_events + congestion_events)
