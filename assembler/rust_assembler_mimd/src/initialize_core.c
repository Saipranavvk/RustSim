
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



void initialize_core(){

    uint32_t dram_queue_array_address = self.dram_queue_array_low + (self.core_id << 3);
    // lw r0, dram_queue_array_low       
    // sll r1, r14, 3
    // add r0, r0, r1                   # r0 = dram_queue_array_address

    uint32_t upper_addr = self.dram_queue_array_high;
    // lw r1, dram_queue_array_high      # r1 = upper_addr

    set_address_bits(upper_addr);
    // setmembits r1

    uint32_t dram_queue_high = load_dram_word(dram_queue_array_address);
    // lw_d r2, r0                       # r2 = dram_queue_high

    uint32_t dram_queue_low = load_dram_word(dram_queue_array_address + 4);
    // add r1, r0, 4
    // lw_d r3, r1, 0                    # r3 = dram_queue_low

    self.dram_queue_high = dram_queue_high;
    // sw r2, DRAM_QUEUE_HIGH

    self.dram_queue_low = dram_queue_low;
    // sw r3, DRAM_QUEUE_LOW

    set_address_bits(dram_queue_high);
    // setmembits r2

    dram_queue_low += 12;
    // add r3, r3, 12

    uint32_t my_ticket = atomic_add_dram(dram_queue_low, 1);
    // atomadd_d r4, r3, 1               # r4 = my_ticket

    uint32_t cur_ticket = load_dram_word(dram_queue_low + 4);
    // add r1, r3, 4
    // wait_for_my_ticket:
    // lw_d r5, r1                       # r5 = cur_ticket

    if(my_ticket != cur_ticket){
        goto wait_for_my_ticket;
    }
    // bne r4, r5, wait_for_my_ticket, true

    dram_queue_low += 8;
    // add r3, r3, 8          

    atomic_add_dram(dram_queue_low, -32768);
    // atomadd_d r1, r3, -32768          # r1 = clobber

    uint32_t cur_val = load_dram_word(dram_queue_low);
    // equal_to_max_neg:
    // lw_d r5, r3, 0                       # r5 = cur_val

    if(cur_val != -32768) {
        goto equal_to_max_neg;
    }
    // and r1, r1, 0
    // add r1, r1, -32768                   # r1 = -32768
    // bne r5, r1, equal_to_max_neg, true

    dram_queue_low += 4;
    // add r3, r3, 4

    uint32_t core_slot = atomic_add_dram(dram_queue_low, 1);
    // atomadd_d r6, r3, 1               # r6 = core_slot

    uint32_t core_slot_address = dram_queue_low + core_slot;
    // add r1, r3, r6                    # r1 = core_slot_address

    core_slot_address += core_slot;
    // add r1, r1, r6                     

    core_slot_address += 4;
    // add r1, r1, 4

    store_dram_half(core_slot_address, self.core_id);
    // sri r7, r14                       # r7 = core_id
    // sh_d r7, r1                          

    dram_queue_low -= 4;
    // add r3, r3, -4

    atomic_add_dram(dram_queue_low, 32768);
    // atomadd_d r1, r3, 32768           

    dram_queue_low -= 4;
    // add r3, r3, -4                   

    atomic_add_dram(dram_queue_low, 1);
    // atomadd_d r1, r3, 1              # r1 = clobber

    uint32_t is_branch_core = load_dram_word(dram_queue_low, 16908);                            
    // lw_d r7, r3, 16908 

    uint32_t r0 = 0;
    // and r0, r0, 0

    if(is_branch_core == 0){
        goto download_branch_core_code;
    }
    // beq r7, r0, download_branch_core_code, true

    uint32_t r1 = self.num_instructions_branch;
    // lw r1, num_instructions_branch

    uint32_t r2 = self.branch_addr_high;
    // lw r2, branch_addr_high, 0       # r2 = branch_addr_high

    set_address_bits(r2);
    // setmembits r2

    uint32_t r2 = self.branch_addr_low;
    // lw r2, branch_addr_low

    goto bootloader_reuse;
    // beq r15, r15, bootloader_reuse, true

    uint32_t r1 = self.num_instructions_leaf;
    // download_branch_core_code:
    // lw r1, num_instructions_leaf     # r1 = num_instructions_leaf

    uint32_t r2 = self.leaf_addr_high;
    // lw r2, leaf_addr_high

    set_address_bits(r2);
    // setmembits r2

    uint32_t r2 = self.leaf_addr_low;
    // lw r2, leaf_addr_low             # r2 = leaf_addr_low

    uint32_t r3 = self.start_of_code_in_sram;
    // bootloader_reuse:
    // lw r3, start_of_code_in_sram

    goto bootloader_loop;
    // beq r15, r15, bootloader_loop, true   # unconditional jump to bootloader
    
    // dram_queue_array_low:
    //  .data -1    // TODO
    // dram_queue_array_high:
    //  .data -1    // TODO
    // dram_queue_high:
    //  .data -1    // TODO
    // dram_queue_low:
    //  .data -1    // TODO
    // num_instructions_branch:
    //  .data -1    // TODO
    // branch_addr_high:
    //  .data -1    // TODO
    // branch_addr_low:
    //  .data -1    // TODO
    // num_instructions_leaf:
    //  .data -1    // TODO
    // leaf_addr_high:
    //  .data -1    // TODO
    // leaf_addr_low:
    //  .data -1    // TODO


}

// # Caller sets up:
// #   r0 = 0           (loop counter, must be < r1)
// #   r1 = N           (number of words to copy)
// #   r2 = src_addr    (source pointer)
// #   r3 = dst_addr    (destination pointer)
// # Then jump to 0x14 (loop)