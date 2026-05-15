#!/usr/bin/env python3
"""
Quick statistics from simulation metrics - minimal output for rapid analysis.
"""

import numpy as np
from pathlib import Path
import sys

def quick_stats(sim_logs_dir="sim_logs"):
    """Print quick statistics."""
    log_path = Path(sim_logs_dir)
    
    # Load key metrics
    metrics = {}
    for filename in [
        'aabb_instruction_count.npy', 'triangle_instruction_count.npy',
        'aabb_cycle_count.npy', 'triangle_cycle_count.npy',
        'memory_operations_close.npy', 'memory_operations_far.npy',
        'high_priority_noc_util.npy', 'high_priority_noc_congestion.npy',
        'low_priority_noc_util.npy', 'low_priority_noc_congestion.npy'
    ]:
        filepath = log_path / filename
        if filepath.exists():
            metrics[filename.replace('.npy', '')] = np.load(filepath)
    
    if not metrics:
        print("ERROR: No metrics found!")
        return
    
    # Quick stats
    print("\n" + "="*70)
    print("QUICK SIMULATION METRICS")
    print("="*70)
    
    # AABB
    aabb_instr = metrics['aabb_instruction_count'].sum()
    aabb_cyc = metrics['aabb_cycle_count'].sum()
    print(f"\nAABB Tests:")
    print(f"  {aabb_instr:>15,.0f} instructions")
    print(f"  {aabb_cyc:>15,.0f} cycles")
    print(f"  {aabb_cyc/aabb_instr if aabb_instr > 0 else 0:>15.2f} cycles/instr")
    
    # Triangle
    tri_instr = metrics['triangle_instruction_count'].sum()
    tri_cyc = metrics['triangle_cycle_count'].sum()
    print(f"\nTriangle Tests:")
    print(f"  {tri_instr:>15,.0f} instructions")
    print(f"  {tri_cyc:>15,.0f} cycles")
    print(f"  {tri_cyc/tri_instr if tri_instr > 0 else 0:>15.2f} cycles/instr")
    
    # Memory
    mem_close = metrics['memory_operations_close'].sum()
    mem_far = metrics['memory_operations_far'].sum()
    print(f"\nMemory Operations:")
    print(f"  {mem_close:>15,.0f} close (local)")
    print(f"  {mem_far:>15,.0f} far (remote)")
    print(f"  {mem_close/(mem_close+mem_far)*100 if (mem_close+mem_far) > 0 else 0:>14.1f}% local")
    
    # NOC
    h_util = metrics['high_priority_noc_util'].sum()
    h_cong = metrics['high_priority_noc_congestion'].sum()
    l_util = metrics['low_priority_noc_util'].sum()
    l_cong = metrics['low_priority_noc_congestion'].sum()
    
    print(f"\nNOC High Priority (mailbox < 32):")
    print(f"  {h_util:>15,.0f} util events")
    print(f"  {h_cong:>15,.0f} congestion events")
    if (h_util + h_cong) > 0:
        print(f"  {h_cong/(h_util+h_cong)*100:>14.1f}% congestion rate")
    
    print(f"\nNOC Low Priority (mailbox >= 32):")
    print(f"  {l_util:>15,.0f} util events")
    print(f"  {l_cong:>15,.0f} congestion events")
    if (l_util + l_cong) > 0:
        print(f"  {l_cong/(l_util+l_cong)*100:>14.1f}% congestion rate")
    
    print("\n" + "="*70 + "\n")

if __name__ == '__main__':
    quick_stats()
