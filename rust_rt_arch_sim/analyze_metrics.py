#!/usr/bin/env python3
"""
Analyze simulation metrics from the .npy output files.
Computes:
- Avg instructions per AABB test
- Avg instructions per triangle test
- Memory utilization
- NOC congestion/utilization comparisons (high vs low priority)
"""

import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from pathlib import Path
import json

def load_metrics(sim_logs_dir="./src/sim_logs"):
    """Load all metric files from sim_logs directory."""
    metrics = {}
    log_path = Path(sim_logs_dir)

    npy_files = [
        'aabb_instruction_count.npy',
        'triangle_instruction_count.npy',
        'aabb_cycle_count.npy',
        'triangle_cycle_count.npy',
        'memory_operations_close.npy',
        'memory_operations_far.npy',
        'bytes_read_close.npy',
        'bytes_read_far.npy',
        'bytes_wrote_close.npy',
        'bytes_wrote_far.npy',
        'up_noc_util.npy',
        'down_noc_util.npy',
        'left_noc_util.npy',
        'right_noc_util.npy',
        'up_noc_congestion.npy',
        'down_noc_congestion.npy',
        'left_noc_congestion.npy',
        'right_noc_congestion.npy',
        'high_priority_noc_util.npy',
        'low_priority_noc_util.npy',
        'high_priority_noc_congestion.npy',
        'low_priority_noc_congestion.npy',
    ]

    for filename in npy_files:
        filepath = log_path / filename
        if filepath.exists():
            try:
                metrics[filename[:-4]] = np.load(filepath, allow_pickle=True)
            except Exception as e:
                print(f"Warning: failed to load {filename}: {e}")
        else:
            print(f"Warning: {filename} not found in {filepath}")

    return metrics

def compute_instruction_metrics(metrics):
    """Compute avg instructions per test."""
    results = {}
    
    # AABB metrics
    aabb_instructions = metrics['aabb_instruction_count'].sum()
    aabb_cycles = metrics['aabb_cycle_count'].sum()
    if aabb_instructions > 0:
        results['avg_instructions_per_aabb'] = aabb_cycles / aabb_instructions
    else:
        results['avg_instructions_per_aabb'] = 0
    results['total_aabb_instructions'] = aabb_instructions
    results['total_aabb_cycles'] = aabb_cycles
    
    # Triangle metrics
    triangle_instructions = metrics['triangle_instruction_count'].sum()
    triangle_cycles = metrics['triangle_cycle_count'].sum()
    if triangle_instructions > 0:
        results['avg_instructions_per_triangle'] = triangle_cycles / triangle_instructions
    else:
        results['avg_instructions_per_triangle'] = 0
    results['total_triangle_instructions'] = triangle_instructions
    results['total_triangle_cycles'] = triangle_cycles
    
    return results

def compute_memory_metrics(metrics):
    """Compute memory utilization."""
    results = {}
    
    mem_ops_close = metrics['memory_operations_close'].sum()
    mem_ops_far = metrics['memory_operations_far'].sum()
    total_mem_ops = mem_ops_close + mem_ops_far
    
    results['total_memory_operations_close'] = mem_ops_close
    results['total_memory_operations_far'] = mem_ops_far
    results['total_memory_operations'] = total_mem_ops
    
    bytes_read_close = metrics['bytes_read_close'].sum()
    bytes_read_far = metrics['bytes_read_far'].sum()
    bytes_wrote_close = metrics['bytes_wrote_close'].sum()
    bytes_wrote_far = metrics['bytes_wrote_far'].sum()
    
    total_bytes = bytes_read_close + bytes_read_far + bytes_wrote_close + bytes_wrote_far
    
    results['total_bytes_transferred'] = total_bytes
    results['bytes_read_close'] = bytes_read_close
    results['bytes_read_far'] = bytes_read_far
    results['bytes_wrote_close'] = bytes_wrote_close
    results['bytes_wrote_far'] = bytes_wrote_far
    
    if total_bytes > 0:
        results['local_vs_far_ratio'] = bytes_read_close / bytes_read_far if bytes_read_far > 0 else float('inf')
    
    return results

def compute_noc_metrics(metrics):
    """Compute NOC utilization and congestion."""
    results = {}
    
    # High priority (mailbox < 32)
    high_priority_util = metrics['high_priority_noc_util'].sum()
    high_priority_cong = metrics['high_priority_noc_congestion'].sum()
    
    results['high_priority_noc_util'] = high_priority_util
    results['high_priority_noc_congestion'] = high_priority_cong
    if high_priority_util > 0:
        results['high_priority_congestion_rate'] = high_priority_cong / (high_priority_util + high_priority_cong)
    
    # Low priority (mailbox >= 32)
    low_priority_util = metrics['low_priority_noc_util'].sum()
    low_priority_cong = metrics['low_priority_noc_congestion'].sum()
    
    results['low_priority_noc_util'] = low_priority_util
    results['low_priority_noc_congestion'] = low_priority_cong
    if low_priority_util > 0:
        results['low_priority_congestion_rate'] = low_priority_cong / (low_priority_util + low_priority_cong)
    
    # Directional metrics
    for direction in ['up', 'down', 'left', 'right']:
        util_key = f'{direction}_noc_util'
        cong_key = f'{direction}_noc_congestion'
        if util_key in metrics and cong_key in metrics:
            util_sum = metrics[util_key].sum()
            cong_sum = metrics[cong_key].sum()
            results[f'{direction}_noc_util'] = util_sum
            results[f'{direction}_noc_congestion'] = cong_sum
            if util_sum > 0:
                results[f'{direction}_congestion_rate'] = cong_sum / (util_sum + cong_sum)
    
    return results

def compute_spatial_metrics(metrics):
    """Compute per-core spatial metrics."""
    results = {}
    
    # AABB hotspots (cores with highest AABB activity)
    aabb_counts = metrics['aabb_instruction_count']
    top_aabb_cores = np.argsort(aabb_counts.flatten())[-10:]
    results['top_aabb_cores'] = [(idx, aabb_counts.flatten()[idx]) for idx in top_aabb_cores[::-1]]
    
    # Triangle hotspots
    triangle_counts = metrics['triangle_instruction_count']
    top_triangle_cores = np.argsort(triangle_counts.flatten())[-10:]
    results['top_triangle_cores'] = [(idx, triangle_counts.flatten()[idx]) for idx in top_triangle_cores[::-1]]
    
    # Memory-intensive cores
    mem_ops = metrics['memory_operations_close'] + metrics['memory_operations_far']
    top_mem_cores = np.argsort(mem_ops.flatten())[-10:]
    results['top_memory_cores'] = [(idx, mem_ops.flatten()[idx]) for idx in top_mem_cores[::-1]]
    
    return results

def generate_report(metrics):
    """Generate comprehensive analysis report."""
    print("\n" + "="*80)
    print("SIMULATION METRICS ANALYSIS REPORT")
    print("="*80 + "\n")
    
    # Instruction metrics
    print("┌─ INSTRUCTION & CYCLE METRICS ─────────────────────────────────────────┐")
    instr_metrics = compute_instruction_metrics(metrics)
    print(f"│ AABB Tests")
    print(f"│   Total instructions:        {instr_metrics['total_aabb_instructions']:>12,.0f}")
    print(f"│   Total cycles:              {instr_metrics['total_aabb_cycles']:>12,.0f}")
    print(f"│   Avg cycles per test:       {instr_metrics['avg_instructions_per_aabb']:>12.2f}")
    print(f"│")
    print(f"│ Triangle Tests")
    print(f"│   Total instructions:        {instr_metrics['total_triangle_instructions']:>12,.0f}")
    print(f"│   Total cycles:              {instr_metrics['total_triangle_cycles']:>12,.0f}")
    print(f"│   Avg cycles per test:       {instr_metrics['avg_instructions_per_triangle']:>12.2f}")
    print("└" + "─"*77 + "┘\n")
    
    # Memory metrics
    print("┌─ MEMORY UTILIZATION ──────────────────────────────────────────────────┐")
    mem_metrics = compute_memory_metrics(metrics)
    print(f"│ Memory Operations")
    print(f"│   Close (local):             {mem_metrics['total_memory_operations_close']:>12,.0f}")
    print(f"│   Far (remote):              {mem_metrics['total_memory_operations_far']:>12,.0f}")
    print(f"│   Total:                     {mem_metrics['total_memory_operations']:>12,.0f}")
    print(f"│")
    print(f"│ Bytes Transferred")
    print(f"│   Read (close):              {mem_metrics['bytes_read_close']:>12,.0f}")
    print(f"│   Read (far):                {mem_metrics['bytes_read_far']:>12,.0f}")
    print(f"│   Write (close):             {mem_metrics['bytes_wrote_close']:>12,.0f}")
    print(f"│   Write (far):               {mem_metrics['bytes_wrote_far']:>12,.0f}")
    print(f"│   Total:                     {mem_metrics['total_bytes_transferred']:>12,.0f}")
    if 'local_vs_far_ratio' in mem_metrics:
        print(f"│   Local/Far ratio:           {mem_metrics['local_vs_far_ratio']:>12.2f}x")
    print("└" + "─"*77 + "┘\n")
    
    # NOC metrics
    # print("┌─ NOC PERFORMANCE ─────────────────────────────────────────────────────┐")
    # noc_metrics = compute_noc_metrics(metrics)
    # print(f"│ High Priority (Mailbox < 32)")
    # print(f"│   Utilization:               {noc_metrics['high_priority_noc_util']:>12,.0f}")
    # print(f"│   Congestion events:         {noc_metrics['high_priority_noc_congestion']:>12,.0f}")
    # if 'high_priority_congestion_rate' in noc_metrics:
    #     print(f"│   Congestion rate:           {noc_metrics['high_priority_congestion_rate']:>12.2%}")
    # print(f"│")
    # print(f"│ Low Priority (Mailbox >= 32)")
    # print(f"│   Utilization:               {noc_metrics['low_priority_noc_util']:>12,.0f}")
    # print(f"│   Congestion events:         {noc_metrics['low_priority_noc_congestion']:>12,.0f}")
    # if 'low_priority_congestion_rate' in noc_metrics:
    #     print(f"│   Congestion rate:           {noc_metrics['low_priority_congestion_rate']:>12.2%}")
    # print(f"│")
    # print(f"│ Directional Breakdown")
    # for direction in ['up', 'down', 'left', 'right']:
    #     util_key = f'{direction}_noc_util'
    #     cong_key = f'{direction}_noc_congestion'
    #     if util_key in noc_metrics:
    #         util = noc_metrics[util_key]
    #         cong = noc_metrics[cong_key]
    #         cong_rate = noc_metrics.get(f'{direction}_congestion_rate', 0)
    #         print(f"│   {direction.upper():5} util: {util:>10,.0f}  cong: {cong:>10,.0f}  rate: {cong_rate:>6.2%}")
    # print("└" + "─"*77 + "┘\n")
    
    # Spatial hotspots
    print("┌─ SPATIAL ANALYSIS ────────────────────────────────────────────────────┐")
    spatial_metrics = compute_spatial_metrics(metrics)
    print(f"│ Top 5 AABB Cores")
    for i, (core_idx, count) in enumerate(spatial_metrics['top_aabb_cores'][-5:][::-1], 1):
        print(f"│   {i}. Core {core_idx:>5}:  {count:>10,.0f} instructions")
    print(f"│")
    print(f"│ Top 5 Triangle Test Cores")
    for i, (core_idx, count) in enumerate(spatial_metrics['top_triangle_cores'][-5:][::-1], 1):
        print(f"│   {i}. Core {core_idx:>5}:  {count:>10,.0f} instructions")
    print(f"│")
    print(f"│ Top 5 Memory-Intensive Cores")
    for i, (core_idx, count) in enumerate(spatial_metrics['top_memory_cores'][-5:][::-1], 1):
        print(f"│   {i}. Core {core_idx:>5}:  {count:>10,.0f} operations")
    print("└" + "─"*77 + "┘\n")
    
    return {
        'instruction_metrics': instr_metrics,
        'memory_metrics': mem_metrics,
        # 'noc_metrics': noc_metrics,
        'spatial_metrics': spatial_metrics
    }

def generate_visualizations(metrics):
    """Generate visualization plots."""
    fig, axes = plt.subplots(2, 2, figsize=(16, 12))
    
    # 1. AABB vs Triangle instruction distribution
    ax = axes[0, 0]
    aabb_counts = metrics['aabb_instruction_count']
    triangle_counts = metrics['triangle_instruction_count']
    im1 = ax.imshow(aabb_counts, cmap='YlOrRd', aspect='auto')
    ax.set_title('AABB Instruction Count (Heatmap)', fontsize=12, fontweight='bold')
    ax.set_xlabel('X')
    ax.set_ylabel('Y')
    plt.colorbar(im1, ax=ax)
    
    # 2. Triangle heatmap
    ax = axes[0, 1]
    im2 = ax.imshow(triangle_counts, cmap='Blues', aspect='auto')
    ax.set_title('Triangle Instruction Count (Heatmap)', fontsize=12, fontweight='bold')
    ax.set_xlabel('X')
    ax.set_ylabel('Y')
    plt.colorbar(im2, ax=ax)
    
    # 3. Memory operations distribution
    ax = axes[1, 0]
    mem_close = metrics['memory_operations_close']
    mem_far = metrics['memory_operations_far']
    im3 = ax.imshow(mem_close + mem_far, cmap='Greens', aspect='auto')
    ax.set_title('Total Memory Operations (Heatmap)', fontsize=12, fontweight='bold')
    ax.set_xlabel('X')
    ax.set_ylabel('Y')
    plt.colorbar(im3, ax=ax)
    
    # 4. NOC priority comparison
    # ax = axes[1, 1]
    # categories = ['Utilization', 'Congestion']
    # # high_priority = [
    # #     metrics['high_priority_noc_util'].sum(),
    # #     metrics['high_priority_noc_congestion'].sum()
    # # ]
    # # low_priority = [
    # #     metrics['low_priority_noc_util'].sum(),
    # #     metrics['low_priority_noc_congestion'].sum()
    # # ]
    # x = np.arange(len(categories))
    # width = 0.35
    # ax.bar(x - width/2, high_priority, width, label='High Priority (< 32)', color='#2ecc71')
    # ax.bar(x + width/2, low_priority, width, label='Low Priority (>= 32)', color='#e74c3c')
    # ax.set_ylabel('Count')
    # ax.set_title('NOC Performance: High vs Low Priority', fontsize=12, fontweight='bold')
    # ax.set_xticks(x)
    # ax.set_xticklabels(categories)
    # ax.legend()
    # ax.set_yscale('log')
    
    plt.tight_layout()
    plt.savefig('./src/sim_logs/metrics_analysis.png', dpi=150, bbox_inches='tight')
    print("✓ Visualization saved to: ./src/sim_logs/metrics_analysis.png")
    
    # Additional detailed plots
    fig2, axes2 = plt.subplots(1, 2, figsize=(14, 5))
    
    # Directional NOC breakdown
    ax = axes2[0]
    directions = ['up', 'down', 'left', 'right']
    util_vals = []
    cong_vals = []
    for d in directions:
        util_key = f'{d}_noc_util'
        cong_key = f'{d}_noc_congestion'
        if util_key in metrics:
            util_vals.append(metrics[util_key].sum())
            cong_vals.append(metrics[cong_key].sum())
    
    x = np.arange(len(directions))
    width = 0.35
    ax.bar(x - width/2, util_vals, width, label='Utilization', color='#3498db')
    ax.bar(x + width/2, cong_vals, width, label='Congestion', color='#e74c3c')
    ax.set_ylabel('Count')
    ax.set_title('NOC Directional Breakdown', fontsize=12, fontweight='bold')
    ax.set_xticks(x)
    ax.set_xticklabels([d.upper() for d in directions])
    ax.legend()
    ax.set_yscale('log')
    
    # Memory operation comparison
    ax = axes2[1]
    categories = ['Close Ops', 'Far Ops', 'Close Bytes', 'Far Bytes']
    values = [
        metrics['memory_operations_close'].sum(),
        metrics['memory_operations_far'].sum(),
        metrics['bytes_read_close'].sum() + metrics['bytes_wrote_close'].sum(),
        metrics['bytes_read_far'].sum() + metrics['bytes_wrote_far'].sum()
    ]
    colors = ['#2ecc71', '#e74c3c', '#2ecc71', '#e74c3c']
    ax.bar(categories, values, color=colors)
    ax.set_ylabel('Count')
    ax.set_title('Memory Operation & Bytes Comparison', fontsize=12, fontweight='bold')
    ax.set_yscale('log')
    plt.setp(ax.xaxis.get_majorticklabels(), rotation=45, ha='right')
    
    plt.tight_layout()
    plt.savefig('./src/sim_logs/noc_memory_analysis.png', dpi=150, bbox_inches='tight')
    print("✓ Visualization saved to: sim_logs/noc_memory_analysis.png")

def save_json_report(all_metrics):
    """Save metrics as JSON for further processing."""
    def convert_to_serializable(obj):
        if isinstance(obj, np.integer):
            return int(obj)
        elif isinstance(obj, np.floating):
            return float(obj)
        elif isinstance(obj, list):
            return [convert_to_serializable(item) for item in obj]
        elif isinstance(obj, dict):
            return {k: convert_to_serializable(v) for k, v in obj.items()}
        return obj
    
    json_report = convert_to_serializable(all_metrics)
    with open('./src/sim_logs/metrics_report.json', 'w') as f:
        json.dump(json_report, f, indent=2)
    print("✓ JSON report saved to: sim_logs/metrics_report.json")

def main():
    print("Loading metrics from sim_logs/...")
    metrics = load_metrics()
    
    if not metrics:
        print("ERROR: No metrics found in sim_logs/")
        return
    
    print(f"Loaded {len(metrics)} metric files\n")
    
    # Generate report
    all_metrics = generate_report(metrics)
    
    # Generate visualizations
    print("\nGenerating visualizations...")
    generate_visualizations(metrics)
    
    # Save JSON report
    # print("Saving JSON report...")
    # save_json_report(all_metrics)
    
    print("\n✓ Analysis complete!")

if __name__ == '__main__':
    main()
