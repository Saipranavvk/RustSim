#include <cstdint>

void leaf_node_idx_vertex_allocator()
{

    set_address_bits(self.node_array_high);
    // lw r[node_array_high], [self.node_array_higha addr]
    // setmembits r[node_array_high]

    // r[node_array_high] free after this

    uint32_t dram_src = self.node_array_low + self.leaf_alloc.node_byte_offset;
    // lw r[node_array_low], [addr_of_self.node_array_low]
    // lw r[node_byte_offset], [addr_of_self.leaf_alloc.node_byte_offset]
    // add r[dram_src], r[node_array_low], r[node_byte_offset]

    // r[node_array_low] free after this
    // r[node_byte_offset] free after this

    uint32_t sram_dst = self.sram_nodes;
    // lw r[sram_dst], [self.sram_nodes addr]

    uint32_t words = self.leaf_alloc.node_byte_count >> 2;
    // lw r[words], [self.leaf_alloc.node_byte_count addr] 
    // srl r[words], r[words], 2

    uint32_t i = 0;
    // and r[i], r[i], 0

node_copy_loop:
    if (i >= words) goto node_copy_done;
    // blte r[words], r[i], node_copy_done    ; branch if words <= i, i.e. i >= words

    *(sram_dst) = load_dram_word(dram_src);
    // lw_d r[tmp], r[dram_src]
    // sw r[tmp], r[sram_dst]

    dram_src += 4;
    // add r[dram_src], r[dram_src], 4

    sram_dst += 4;
    // add r[sram_dst], r[sram_dst], 4

    i += 1;
    // add r[i], r[i], 1

    goto node_copy_loop;
    // jmp node_copy_loop

node_copy_done:

    dram_src = self.index_array_low + self.leaf_alloc.index_byte_offset;
    // lw r[index_array_low], [self.index_array_low addr]
    // lw r[index_byte_offset], [addr_of_self.leaf_alloc.index_byte_offset adr]
    // add r[dram_src], r[index_array_low], r[index_byte_offset]

    words = self.leaf_alloc.index_byte_count >> 2;
    // lw r[words], [self.leaf_alloc.index_byte_count addr]
    // srl r[words], r[words], 2

    i = 0;
    // and r[i], r[i], 0

index_copy_loop:
    if (i >= words) goto index_copy_done;
    // blte r[words], r[i], index_copy_done

    *(sram_dst) = load_dram_word(dram_src);
    // lw_d r[tmp], r[dram_src]
    // sw r[tmp], r[sram_dst]

    dram_src += 4;
    // add r[dram_src], r[dram_src], 4

    sram_dst += 4;
    // add r[sram_dst], r[sram_dst], 4

    i += 1;
    // add r[i], r[i], 1

    goto index_copy_loop;
    // jmp index_copy_loop

index_copy_done:

    dram_src = self.vertex_array_low + self.leaf_alloc.vertex_byte_offset;
    // lw r[vertex_array_low], [self.vertex_array_low addr]
    // lw r[vertex_byte_offset], [self.leaf_alloc.vertex_byte_offset addr]
    // add r[dram_src], r[vertex_array_low], r[vertex_byte_offset]

    words = self.leaf_alloc.vertex_byte_count >> 2;
    // lw r[words], [self.leaf_alloc.vertex_byte_count addr]
    // srl r[words], r[words], 2

    i = 0;
    // and r[i], r[i], 0

vertex_copy_loop:
    if (i >= words) goto vertex_copy_done;
    // blte r[words], r[i], vertex_copy_done

    *(sram_dst) = load_dram_word(dram_src);
    // lw_d r[tmp], r[dram_src]
    // sw r[tmp], r[sram_dst]

    dram_src += 4;
    // add r[dram_src], r[dram_src], 4

    sram_dst += 4;
    // add r[sram_dst], r[sram_dst], 4

    i += 1;
    // add r[i], r[i], 1

    goto vertex_copy_loop;
    // jmp vertex_copy_loop

vertex_copy_done:
    // TODO ask Alex tf I do here
}



#define LOCK_DECREMENT 0x7FFFFFFF // some large value idk
#define IDLE_WINDOW 1000000
#define IDLE_THRESHOLD 100 

bool is_idle_leaf() {

    uint32_t current_cycle = get_cycle_count();
    // getclk r[current_cycle]

    uint32_t last_observed_cycle = self.core_handled->last_observed_cycle;
    // lw r[last_observed_cycle], [self.core_handled.last_observed_cycle addr]

    uint32_t time_diff = current_cycle - last_observed_cycle;
    // sub r[time_diff], r[current_cycle], r[last_observed_cycle]

    if (time_diff < IDLE_WINDOW) {    return 0;    }
    // blte r[time_diff], IDLE_WINDOW, return_false


    if(self.core_handled->previously_idle) {    return 0;    }
    // lbu r[previously_idle], [self.core_handled.previously_idle addr]
    // bne r[previously_idle], 0, return_false

    uint32_t rays_processed = self.core_handled->rays_processed;
    // lw r[rays_processed], [self.core_handled.rays_processed addr]

    self.core_handled->rays_processed = 0;
    // sw 0, [self.core_handled.rays_processed addr]

    self.core_handled->last_observed_cycle = current_cycle;
    // sw r[current_cycle], [self.core_handled.last_observed_cycle addr]

    rays_processed <<= 16;
    // sll r[rays_processed], r[rays_processed], 16

    uint32_t ratio = rays_processed / time_diff;
    // div r[ratio], r[rays_processed], r[time_diff]

    if (ratio >= IDLE_THRESHOLD) {    return 0;    }
    // bgteu r[ratio], IDLE_THRESHOLD, return_false

    add_idle_core();
    // jmp add_idle_core  // assume function call
idle_core_added:

    self.core_handled->previously_idle = 1;
    // add r[tmp], 0, 1
    // sb r[tmp], [addr_of_self.core_handled.previously_idle] // is it store byte???

    return 1;
    // add r[ret], 0, 1
    // jmp end_is_idle_leaf

return_false:
    // and r[ret], r[ret], 0

end_is_idle_leaf:
    // TODO ask Alex tf I do here

}


void add_idle_core() {

    uint32_t idle_queue_address_high = self.idle_queue_address_high;
    // lw r[idle_queue_address_high], [self.idle_queue_address_high addr]

    set_address_bits(idle_queue_address_high);
    // setmembits r[idle_queue_address_high]

    uint32_t idle_queue_address_low = self.idle_queue_address_low;
    // lw r[idle_queue_address_low], [self.idle_queue_address_low addr]

    idle_queue_address_low += 8;
    // add r[idle_queue_address_low], r[idle_queue_address_low], 8

idle_core_insert_spinlock:
    uint32_t old_count = atomic_add_dram(idle_queue_address_low, 1);
    // atomadd_d r[old_count], r[idle_queue_address_low], 1

    if(old_count > 256){
    // bgtu r[old_count], 256, undo_and_spin
    // jmp done_spinlock_idle_queue
undo_and_spin:
        atomic_add_dram(idle_queue_address_low, -1);
        // atomadd_d r[tmp], r[idle_queue_address_low], -1

        goto idle_core_insert_spinlock;
        // jmp idle_core_insert_spinlock
    }
done_spinlock_idle_queue:

    idle_queue_address_low -= 4;
    // add r[idle_queue_address_low], r[idle_queue_address_low], -4

    uint32_t slot_index = atomic_add_dram(idle_queue_address_low, 4);
    // atomadd_d r[slot_index], r[idle_queue_address_low], 4

    slot_index = slot_index & 0x3FF;
    // and r[slot_index], r[slot_index], 0x3FF

    uint32_t slot_address = idle_queue_address_low + slot_index;
    // add r[slot_address], r[idle_queue_address_low], r[slot_index]

wait_for_idle_queue_slot_to_open:
    uint32_t is_open = load_dram_half(slot_address + 10);
    // lhu_d r[is_open], r[slot_address], 10    ; load unsigned half from slot_address + 10

    if(is_open != 0){
    // bne r[is_open], 0, wait_for_idle_queue_slot_to_open

        goto wait_for_idle_queue_slot_to_open;
    }

    store_dram_half(self.core_id, slot_address + 8);
    // lw r[core_id], [self.core_id addr]
    // sh_d r[core_id], r[slot_address], 8    ; store half to slot_address + 8

    store_dram_byte(1, slot_address + 10);
    // add r[tmp], 0, 1
    // sb_d r[tmp], r[slot_address], 10    ; store byte to slot_address + 10

    // jmp idle_core_added  // assume function call returns here
}