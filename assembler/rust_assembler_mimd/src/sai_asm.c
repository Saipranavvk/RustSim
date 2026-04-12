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
    return;
}