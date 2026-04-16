
#define DRAM_QUEUE_ARRAY_BEGIN 0x10000000

// void dram_queue_array <- array of tuples (high and low dram queue address), size of it is the same as umber of cores (num core_id)
typedef struct
{                           // 16924 Bytes
    uint32_t head_relative; // relative to the start of the queue in DRAM
    uint32_t tail_relative; // relative to the start of the queue in DRAM
    uint32_t count;
    uint32_t next_ticket; // atomically incremented
    uint32_t now_serving; // spin on when this value equals your ticket, then increment when done
    uint32_t lock;
    uint32_t core_owner_count;
    uint16_t core_slots[256];
    struct Ray[256] rays; // 256 * 64 bytes for the rays
    uint32_t is_branch;
    struct leaf_geo_alloc_info leaf_alloc;
} ray_queue_dram;

void initialize_core(){
    // index into the dram_queue_array using core_id <- grab initial high and low addresses for our queue from dram
    uint32_t dram_queue_array_address = self.dram_queue_array_low + (self.core_id << 3); // 8 bytes per tuple
    // set high
    uint32_t upper_addr = self.dram_queue_array_high;
    set_address_bits(upper_addr);
    //load dram_queue info
    uint32_t dram_queue_high = load_dram_word(dram_queue_array_address);
    uint32_t dram_queue_low = load_dram_word(dram_queue_array_address + 4);

    // save the info
    self.dram_queue_high = dram_queue_high;
    self.dram_queue_low = dram_queue_low;

    set_address_bits(dram_queue_high);
    dram_queue_low += 12;
    uint32_t my_ticket = atomic_add_dram(dram_queue_low, 1);
    //wait_for_my_ticket:
    uint32_t cur_ticket = load_dram_word(dram_queue_low + 4);
    if(my_ticket != cur_ticket){
        goto cur_ticket;
    }
    dram_queue_low += 8;
    atomic_add_dram(dram_queue_low, -32768);
    //equal_to_max_neg:
    uint32_t cur_val = load_dram_word(dram_queue_low);
    if(cur_val != -32768) {
        goto equal_to_max_neg;
    }
    dram_queue_low += 4;
    uint32_t core_slot = atomic_add_dram(dram_queue_low, 1);
    uint32_t core_slot_address = dram_queue_low + core_slot;
    core_slot_address += core_slot;
    core_slot_address += 4;
    store_dram_half(core_slot_address, self.core_id);
    dram_queue_low -= 4;
    atomic_add_dram(dram_queue_low, 32768);
    dram_queue_low -= 4;
    atomic_add_dram(dram_queue_low, 1);
    uint32_t is_branch_core = load_dram_word(dram_queue_low, 16908);
    uint32_t r0 = 0;
    if(is_branch_core == 0){
        goto download_branch_core_code;
    }
    uint32_t r1 = self.num_instructions_branch;
    uint32_t r2 = self.branch_addr_high; // will copy each line of code in all mem stacks - pull from optimal stack, this is some algo
    set_address_bits(r2);
    uint32_t r2 = self.branch_addr_low; // hard set for each mem stack, identical i think
    goto bootloader_reuse;

    //download_branch_core_code:
    uint32_t r1 = self.num_instructions_leaf;
    uint32_t r2 = self.leaf_addr_high; // will copy each line of code in all mem stacks - pull from optimal stack, this is some algo
    set_address_bits(r2);
    uint32_t r2 = self.leaf_addr_low; // hard set for each mem stack, identical i think
    //bootloader_reuse:
    uint32_t r3 = self.start_of_code_in_sram;
    goto bootloader_loop; //preset constant, not in same assembled file
}

// # Caller sets up:
// #   r0 = 0           (loop counter, must be < r1)
// #   r1 = N           (number of words to copy)
// #   r2 = src_addr    (source pointer)
// #   r3 = dst_addr    (destination pointer)
// # Then jump to 0x14 (loop)