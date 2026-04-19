.org IDK //TODO

# ***RAY is R0, NODE is R1, R15 is reserved for context info and others**
    # initialize_core();
    beq r15, r15, initialize_core, true

start_ray_traversal:
    # yield();
    yield r8                        # r8 = scratch for yield

    # if (ray->check_left & 1 != 0 && ray->check_right & 1 != 0)
    # {
    #     goto complete_ray;
    # }
    lw r2, r0, 44                   # r2 = ray->check_left
    and r4, r2, 1
    lw r3, r0, 28                   # r3 = ray->check_right
    and r5, r3, 1
    and r4, r4, r5                  # r4 = (check_left & 1) & (check_right & 1)
    and r5, r5, 0
    add r5, r5, 1                   # r5 = 1
    beq r4, r5, complete_ray, true  # if both bits set goto complete_ray

    # uint32_t left_bitfield_check = ray->check_left & (1 << ray->ray_depth) | node->left_child == 0;
    lbu r5, r0, 62                  # r5 = ray->ray_depth
    and r4, r4, 0
    add r4, r4, 1                   # r4 = 1
    sll r4, r4, r5                  # r4 = 1 << ray->ray_depth
    and r4, r4, r2                  # r4 = ray->check_left & (1 << ray->ray_depth)
    lhu r6, r1, 24                  # r6 = node->left_child
    and r7, r7, 0
    add r7, r7, 0xFFFF              # r7 = 0xFFFF (null sentinel)
    beq r6, r7, LEFT_CHILD_NULL, true
    and r6, r6, 0                   # left_child != null => contribute 0
    beq r15, r15, LEFT_BITFIELD_DONE, true
LEFT_CHILD_NULL:
    add r6, r6, 1                   # left_child == null => contribute 1 (forces visited)
LEFT_BITFIELD_DONE:
    or r4, r4, r6                   # r4 = left_bitfield_check

    # uint32_t right_bitfield_check = ray->check_right & (1 << ray->ray_depth) | node->right_child == 0;
    lbu r5, r0, 62                  # r5 = ray->ray_depth
    and r9, r9, 0
    add r9, r9, 1
    sll r9, r9, r5                  # r9 = 1 << ray->ray_depth
    and r9, r9, r3                  # r9 = ray->check_right & (1 << ray->ray_depth)
    lhu r6, r1, 25                  # r6 = node->right_child (uint16 at offset 25)
    beq r6, r7, RIGHT_CHILD_NULL, true
    and r6, r6, 0
    beq r15, r15, RIGHT_BITFIELD_DONE, true
RIGHT_CHILD_NULL:
    add r6, r6, 1                   # right_child == null => contribute 1 (forces visited)
RIGHT_BITFIELD_DONE:
    or r9, r9, r6                   # r9 = right_bitfield_check

    # if (left_bitfield_check != 0 && right_bitfield_check != 0) { ... }
    and r6, r4, r9                  # r6 = left_bitfield_check & right_bitfield_check (nonzero if both set)
    and r7, r7, 0                   # r7 = 0
    beq r6, r7, CHECK_BOTH_ZERO, true   # if r6 == 0, neither both set — check other cases

    # if (ray->ray_depth == 0) goto complete_ray;
    lbu r5, r0, 62                  # r5 = ray->ray_depth
    beq r5, r7, complete_ray, true

    # TODO ASK ALEX ABOUT THIS
    # uint32_t bitfield = *(ray.check_left + node->is_right * 4);
    lbu r6, r1, 28                  # r6 = node->is_right
    sll r6, r6, 2                   # r6 = node->is_right * 4
    add r6, r0, r6                  # r6 = &ray.check_left + is_right*4
    add r6, r6, 18                  # r6 = absolute address of bitfield word in ray
    lw r8, r6, 0                    # r8 = bitfield


    # uint32_t or_value = 1 << (ray->ray_depth - 1);
    lbu r5, r0, 62                  # r5 = ray->ray_depth
    add r5, r5, -1                  # r5 = ray_depth - 1
    and r10, r10, 0
    add r10, r10, 1
    sll r10, r10, r5                # r10 = or_value

    # bitfield |= or_value;
    or r8, r8, r10
    sw r8, r6, 0                    # *(ray.check_left + is_right*4) = bitfield

    # ray->ray_depth--;
    lbu r5, r0, 62
    add r5, r5, -1
    sb r5, r0, 62

    # if (node->parent == 0) goto complete_ray;
    lhu r6, r1, 26                  # r6 = node->parent
    beq r6, r7, complete_ray, true  # r7 = 0

    # node = node->parent;
    and r1, r1, 0
    add r1, r1, r6                  # r1 = node->parent (SRAM pointer)
    beq r15, r15, start_ray_traversal, true

CHECK_BOTH_ZERO:
    # else if (left_bitfield_check == 0 && right_bitfield_check == 0)
    or r6, r4, r9                   # r6 = left | right
    beq r6, r7, DO_AABB, true       # both zero -> do AABB test
    beq r15, r15, TRAVERSE_LEFT_OR_RIGHT, true  # one is zero, one is not

DO_AABB:
    # int hit = AABB_Intersect(node, ray);
    # TODO ask alex abt function call protocl\ol
    beq r15, r15, AABB_INTERSECT, true 
AABB_INTERSECT_RETURN:             
    # ASSUME r11 CONTAINS INFO FROM FUNCTION
    # if (hit)
    beq r11, r7, AABB_MISS, true

    # if (node->tri_count == 0)
    lbu r6, r1, 30                  # TODO confirm offset
    beq r6, r7, IS_INTERNAL_NODE, true
    beq r15, r15, IS_LEAF_NODE, true

IS_INTERNAL_NODE:
    # ray->ray_depth++
    lbu r5, r0, 59
    add r5, r5, 1
    sb r5, r0, 59

    # if (node->core_owner != 0xFFFF)
    lhu r6, r1, 32                  # r6 = node->core_owner (uint16 offset 32) TODO confirm offset
    and r7, r7, 0
    add r7, r7, 0xFFFF
    beq r6, r7, TRAVERSE_OWN_CHILD, true   # owner == 0xFFFF means we own it

    # uint16_t ray_send_pending_addr = self.ray_send_pending_addr;
    lw r8, RAY_SEND_PENDING_ADDR    # r8 = self.ray_send_pending_addr

    # atomic_add(ray_send_pending_addr, 1)
    atomadd r9, r8, 1               # r9 = clobber

    # uint32_t is_thread_odd = self.thread_id & 1;
    # is_thread_odd += 32;
    # disable_interrupts(is_thread_odd)
    and r10, r15, 0xF               # r10 = thread_id
    and r11, r10, 1                 # r11 = is_thread_odd
    add r11, r11, 32                

    # disable_interrupts(is_thread_odd);
    intdis r11          

    # uint32_t request_word = (node->node_id << 17) | self.thread_id;
    lw r12, r1, 40                  # r12 = node->node_id TODO confirm offset
    sll r12, r12, 17
    and r10, r15, 0xF               # r10 = thread_id
    or r12, r12, r10                # r12 = request_word

    # send_packet(request_word, node->core_owner, 32);
    lhu r6, r1, 32                  # r6 = node->core_owner
    sendflit r6, r12, 32            # TODO confirm notation w/ Alex

SEND_RAY_LOOP:
    # uint32_t msg_available = nb_recv(self.thread_id + 16);
    and r10, r15, 0xF               # r10 = thread_id
    add r11, r10, 16                # r11 = thread_id + 16
    nonblock r12, r11               # r12 = msg_available
    beq r12, r7, CHECK_DATA_MAILBOX, true  

    # uint32_t msg = blocking_receive(self.thread_id + 16);
    block r12, r11                  # r12 = msg

    # uint32_t header = msg >> 24;
    srl r13, r12, 24

    # if (header == ack_ray)
    and r11, r11, 0                 # TODO tf is ack_ray @ Alex write better code
    add r11, r11, 5
    bne r13, r11, REJECT_PATH, true

    # ACK path: send 16 words of ray to dest core
    lhu r6, r1, 32                  # r6 = node->core_owner TODO ckech offset
    and r11, r12, 0xF               # r11 = dest mailbox from ack msg
    and r10, r10, 0

    add r13, r0, 0                  # r13 = ray base
    and r14, r14, 0
RAY_SEND_LOOP:
    lw r9, r13, 0
    sendflit r6, r9, r11
    add r13, r13, 4
    add r14, r14, 1
    and r11, r11, 0
    add r11, r11, 16
    bgt r11, r14, RAY_SEND_LOOP, true
    # ray->active_ray = 0
    sb r7, r0, 63                   # TODO check offset
    # sent = 1
    # TODO forgot to set sent like a fucking chud 
    beq r15, r15, CHECK_DATA_MAILBOX, true

REJECT_PATH:
    # push ray to DRAM queue
    lhu r8, r1, 34                  # r8 = node->queue_high_bit_addr TODO confirm offset
    setmembits r8
    lw r9, r1, 36                   # r9 = node->queue_low_bit_addr TODO confirm offset

ENSURE_SPACE_IN_QUEUE:
    ; // ensure_space_in_queue:
    ; int cur_ray_count = load_dram_word(queue_address_low - 12);
    ; if (cur_ray_count > 255)
    ; {
    ;     goto ensure_space_in_queue;
    ; }
    lw r10, r9, -12                 # r10 = cur_ray_count
    and r11, r11, 0
    add r11, r11, 255
    bgt r10, r11, ENSURE_SPACE_IN_QUEUE, true

    add r9, r9, -16
    # tail = atomic_add(queue_address_low, 64)
    atomadd_d r10, r9, 64           
    and r10, r10, 0x3FFF    
    add r11, r9, 536
    add r11, r11, r10               # r11 = write_addr

WAIT_FOR_SLOT_TO_OPEN:
    lbu_d r10, r11, 63              # r10 = cur_ray_count
    bne r10, r7, WAIT_FOR_SLOT_TO_OPEN, true   # r7=0

    add r13, r0, 0                  # r13 = ray base
    and r14, r14, 0
RAY_DRAM_WRITE_LOOP:
    lw r10, r13, 0                  # r10 = ray word
    sw_d r10, r11, 0
    add r13, r13, 4
    add r11, r11, 4
    add r14, r14, 1
    and r12, r12, 0
    add r12, r12, 16
    bgt r12, r14, RAY_DRAM_WRITE_LOOP, true

    lw r9, r1, 36                   # r9 = queue_address_low
    add r9, r9, 20                  

ENSURE_NO_WRITERS:
    atomadd_d r10, r9, 1
    and r11, r11, 0
    bgt r11, r10, SKIP_UNDO_LOCK, true   # r10 >= 0 means no writer
    atomadd_d r11, r9, -1
ENSURE_NO_WRITERS_LOOP:                  # TODO DOUBLE CHECK W/ ALEX <- DEADLOCK
    lw_d r10, r9, 0                      # r10 = is_there_a_writer
    bgt r11, r10, ENSURE_NO_WRITERS_LOOP, true
    beq r15, r15, ENSURE_NO_WRITERS, true

SKIP_UNDO_LOCK:
    lw_d r10, r9, 4                 # r10 = core_owner_count
    beq r10, r7, NO_OWNER, true     

    # pick owner: idx = (core_id ^ clock) % core_owner_count
    getclk r11                      # clk
    srl r12, r15, 4                 # core_id
    xor r12, r12, r11               # idx
    lhu r13, r1, 38                 # r13 = ode->prev_index TODO confirm offset
    beq r12, r13, BUMP_IDX, true
    beq r15, r15, SKIP_BUMP, true
BUMP_IDX:
    add r12, r12, 1
SKIP_BUMP:
    mod r12, r12, r10               # idx %= core_owner_count
    sh r12, r1, 38                  # node->prev_index = idx
    sll r12, r12, 1
    add r9, r9, r12
    lw_d r10, r9, 28                # core_to_cache
    sh r10, r1, 32                  # node->core_owner = core_to_cache
    beq r15, r15, RELEASE_LOCK, true

NO_OWNER:
    and r11, r11, 0
    add r11, r11, 0xFFFFFFFF            # r11 = 0xFFFFFFFF
    sw r11, r1, 32                  # node->core_owner = 0xFFFF
    and r11, r11, 0
    add r11, r11, 200
    # if (cur_ray_count > 200)
    blte r10, r11, RELEASE_LOCK, true

# TODO do this is statement @ ALEX
    

RELEASE_LOCK:
    lw r9, r1, 36                   # r9 = queue_address_low
    add r9, r9, 20
    atomadd_d r11, r9, -1           # r11 = clobber
    sb r7, r0, 63                   # ray->active_ray = 0

    # TODO set the sent value (im a chud and forgot)

CHECK_DATA_MAILBOX:
    and r10, r15, 0xF               # r10 = thread_id
    nonblock r12, r10               # r12 = nb_recv(thread_id)

    beq r12, r7, CHECK_INTERRUPT_MAILBOX, true
    and r13, r13, 0                 # TODO Alex wtf is slot
    and r14, r14, 0
DATA_RECV_LOOP:
    block r9, r10                   # r9 = ray_word

    # *slot = ray_word
    sw r9, r13, 0                   
    add r13, r13, 4
    add r14, r14, 1
    and r11, r11, 0
    add r11, r11, 16
    bgt r11, r14, DATA_RECV_LOOP, true
    # patch leaf_node_starting_point into slot
    lw r9, r0, 40                   # r9 = leaf_node_index
    sll r9, r9, 1
    lw r9, LEAF_CORE_LOOKUP_TABLE   # base of lookup table
    /*
    TODO indexing math for
    uint32_t leaf_core_data_addr = self.leaf_core_lookup_table->leaf_core_ptrs[leaf_node_index];
    with the loaded value being in r9
    */
    lw r9, r9, 0                   # leaf_core_data_addr
    sw r9, r13, -16                 # *(slot - 16) = leaf_core_data_addr
    and r13, r13, 0
    add r13, r13, 0xFFFFFFFF            # slot = 0xFFFFFFFF

# At this point I got tired of hand writing, below is AI-ish, istg Alex dont be upsetty spaggeti
# I labeled "CHECK_INTERRUPT_MAILBOX" in the C code, I plugged the above into AI and asked it to finish
# I will check it l8r so cool ur pants


CHECK_INTERRUPT_MAILBOX:
    and r10, r15, 0xF
    and r11, r10, 1
    add r11, r11, 32
    nonblock r12, r11
    beq r12, r7, DONE_WITH_INTERRUPT, true
    block r12, r11                  # message
    srl r8, r12, 17                 # supposed_node_id
    lw r9, ROOT_NODE_ID
    bne r8, r9, WRONG_CORE_SEND, true

    lw r8, LOCAL_QUEUE
    add r8, r8, 8
    and r9, r10, 1
    and r11, r11, 0
    add r11, r11, 1036
    mul r9, r9, r11
    add r8, r8, r9
    atomadd r9, r8, 1               # old_count
    lbu r11, LOCAL_QUEUE_FLUSHING
    and r14, r14, 0
    add r14, r14, 16
    bgt r9, r14, REJECT_INTERRUPT, true
    beq r11, r7, NO_FLUSH, true     # r7=0
REJECT_INTERRUPT:
    atomadd r9, r8, -1
    and r9, r9, 0
    add r9, r9, 7                   # reject_ray = 7
    sll r9, r9, 24
    srl r11, r12, 4
    and r11, r11, 0x1FFF
    and r14, r12, 0xF
    add r14, r14, 16
    sendflit r11, r9, r14
    beq r15, r15, DONE_WITH_INTERRUPT, true

NO_FLUSH:
    add r8, r8, -4
    atomadd r9, r8, 64              # tail_relative
    and r9, r9, 0x3FF
    add r8, r8, 8
    add r8, r8, r9                  # slot = local_queue + tail_relative
    and r14, r14, 0
    add r14, r14, 5                 # ray_ack = 5
    sll r14, r14, 24
    and r10, r15, 0xF
    or r14, r14, r10
    srl r11, r12, 4
    and r11, r11, 0x1FFF
    and r9, r12, 0xF
    add r9, r9, 16
    sendflit r11, r14, r9

WRONG_CORE_SEND:
    and r9, r9, 0
    add r9, r9, 8                   # wrong_core = 8
    sll r9, r9, 24
    srl r11, r12, 4
    and r11, r11, 0x1FFF
    and r14, r12, 0xF
    add r14, r14, 16
    sendflit r11, r9, r14

DONE_WITH_INTERRUPT:
    # if (sent == 1 && slot == 0xFFFFFFFF) -> ray_done
    # sent tracked by whether active_ray was cleared; check active_ray
    lbu r9, r0, 63
    beq r9, r7, DECREMENT_PENDING, true   # active_ray == 0 means sent
    beq r15, r15, SEND_RAY_LOOP, true

DECREMENT_PENDING:
    and r10, r15, 0xF
    and r11, r10, 1
    add r11, r11, 32
    intdis r11
    lw r8, RAY_SEND_PENDING_ADDR
    atomadd r9, r8, -1
    beq r15, r15, ray_done, true

TRAVERSE_OWN_CHILD:
    # node = node->left_child
    lhu r1, r1, 24                  # r1 = node->left_child
    beq r15, r15, start_ray_traversal, true

IS_LEAF_NODE:
    # bitfield = *(ray.check_left + node->is_right * 4)
    lbu r6, r1, 31                  # node->is_right
    sll r6, r6, 2
    add r6, r0, r6
    add r6, r6, 18
    lw r8, r6, 0

    lbu r5, r0, 59                  # ray->ray_depth
    add r5, r5, -1
    and r10, r10, 0
    add r10, r10, 1
    sll r10, r10, r5
    or r8, r8, r10
    sw r8, r6, 0

    # tri loop
    lhu r9, r1, 22                  # tri_start TODO confirm offset
    lbu r10, r1, 30                 # tri_count
    and r14, r14, 0
TRI_LOOP:
    beq r14, r10, TRI_LOOP_DONE, true
    # Triangle_Intersect(tri_index=r9, ray=r0) -- call convention TBD
    beq r15, r15, Triangle_Intersect, true
TRI_INTERSECT_RETURN:
    add r9, r9, 12
    add r14, r14, 1
    beq r15, r15, TRI_LOOP, true
TRI_LOOP_DONE:
    lbu r5, r0, 59
    add r5, r5, -1
    sb r5, r0, 59
    lhu r1, r1, 28                  # node = node->parent
    beq r15, r15, start_ray_traversal, true

AABB_MISS:
    lbu r5, r0, 59
    beq r5, r7, MISS_AT_ROOT, true
    lbu r6, r1, 31                  # node->is_right
    sll r6, r6, 2
    add r6, r0, r6
    add r6, r6, 18
    lw r8, r6, 0
    add r5, r5, -1
    and r10, r10, 0
    add r10, r10, 1
    sll r10, r10, r5
    or r8, r8, r10
    sw r8, r6, 0
    lbu r5, r0, 59
    add r5, r5, -1
    sb r5, r0, 59
    lhu r1, r1, 28
    beq r15, r15, start_ray_traversal, true

MISS_AT_ROOT:
    and r8, r8, 0
    add r8, r8, 0xFFFF              # 0xFFFF as 32-bit all-ones approx; need two stores
    sw r8, r0, 22                   # ray->check_right = 0xFFFFFFFF
    sw r8, r0, 18                   # ray->check_left  = 0xFFFFFFFF
    beq r15, r15, start_ray_traversal, true

TRAVERSE_LEFT_OR_RIGHT:
    # clear bits below current depth in check_left and check_right
    lbu r5, r0, 59
    add r5, r5, 1
    and r8, r8, 0
    add r8, r8, 0xFFFFFFFF
    sll r8, r8, r5                  # mask = 0xFFFFFFFF << (ray_depth+1)... TODO: need NOT
    # workaround: xor with all-ones to get ~mask
    and r11, r11, 0
    add r11, r11, 0xFFFFFFFF
    xor r8, r8, r11                 # r8 = zero_out_subtree
    lw r2, r0, 18
    and r2, r2, r8
    sw r2, r0, 18
    lw r3, r0, 22
    and r3, r3, r8
    sw r3, r0, 22

    # node = *(node.left_child + (left_bitfield_check != 0) * 2)
    and r6, r6, 0
    beq r4, r7, USE_LEFT, true      # r4=left_bitfield_check, r7=0
    add r6, r6, 2                   # offset by 2 if left already visited -> use right
USE_LEFT:
    add r6, r6, 24                  # base offset of left_child in AABB_Node
    lhu r1, r1, r6

    lbu r5, r0, 59
    add r5, r5, 1
    sb r5, r0, 59
    beq r15, r15, start_ray_traversal, true

ray_done:
    lbu r9, r0, 63                  # ray->active_ray
    bne r9, r7, start_ray_traversal, true   # r7=0

    yield r8

    # check local ray queue
    and r10, r15, 0xF               # thread_id
    and r11, r10, 1                 # odd_thread
    and r12, r12, 0
    add r12, r12, 1036
    mul r11, r11, r12               # offset = odd_thread * 1036
    lw r12, LOCAL_RAY_QUEUE
    add r11, r11, r12               # offset += self.local_ray_queue
    lw r12, r11, 8                  # local_ray_count

    beq r12, r7, CHECK_ODD_FOR_NO_RAYS, true

    lw r12, LOCAL_RAY_QUEUE_HEAD
    atomadd r13, r12, 64            # slot = atomic_add(head, 64)
    add r12, r12, 8
    atomadd r14, r12, -1            # decrement count
    and r13, r13, 0x7FF
    add r12, r12, -8
    add r12, r12, r13               # queue_head + slot
    add r12, r12, 4

    # copy 16 words from local queue into ray slot r0
    lw r9, r12, 0 
    sw r9, r0, 0
    lw r9, r12, 4
    sw r9, r0, 4
    lw r9, r12, 8
    sw r9, r0, 8
    lw r9, r12, 12
    sw r9, r0, 12
    lw r9, r12, 16
    sw r9, r0, 16
    lw r9, r12, 20
    sw r9, r0, 20
    lw r9, r12, 24
    sw r9, r0, 24
    lw r9, r12, 28
    sw r9, r0, 28
    lw r9, r12, 32
    sw r9, r0, 32
    lw r9, r12, 36
    sw r9, r0, 36
    and r9, r9, 0
    add r9, r9, 128                 # leaf_node_starting_point hardcoded
    sw r9, r0, 40
    lw r9, r12, 44
    sw r9, r0, 44
    lw r9, r12, 48
    sw r9, r0, 48
    lw r9, r12, 52
    sw r9, r0, 52
    lw r9, r12, 56
    sw r9, r0, 56
    lw r9, r12, 60
    sw r9, r0, 60
    and r9, r9, 0
    sb r9, r12, 63                  # clear slot
    lw r1, r0, 40                   # node = ray->leaf_node_starting_point
    #ABOVE, WE ASSUME THE QUEUE HAS BEEN INSERTED WITH THE CORRECT SRAM ADDRESS TODO
    beq r15, r15, start_ray_traversal, true  

CHECK_ODD_FOR_NO_RAYS:
    and r11, r10, 1
    bne r11, r7, ray_done, true     # odd thread loops back
    beq r15, r15, no_rays_available, true

no_rays_available:
    # (continues in rest of main loop file)
    lw r3, LOCAL_QUEUE_FLUSHING
    and r14, r3, 0
    bne r3, r14, INF_LOOP, false
    yield r8
    lw r3, RAY_QUEUE_HIGH
    setmembits r3
    lw r3, RAY_QUEUE_LOW
    and r14, r15, 1
    mul r14, r14, 16924
    add r3, r3, r14
    lw_d r4, r3, 8
    blte r4, r14, DRAM_RAY_QUEUE_EMPTY, true
    add r5, r14, 256
    blte r4, r5, RESET_PULLED_FROM_FULL_QUEUE_CNT, true
    add r5, r14, PULLED_FROM_FULL_QUEUE_CNT
    atomadd r5, r5, 1
    add r6, r14, 1 # BRANCH_BUSY_THRESHOLD
    blteu r6, r5, PULL_ELEM_FROM_DRAM_QUEUE, false
    jmp r7, BRANCH_CORE_ASK_FOR_HELP
RESET_PULLED_FROM_FULL_QUEUE_CNT:
    sw r14, PULLED_FROM_FULL_QUEUE_CNT
PULL_ELEM_FROM_DRAM_QUEUE:
    add r3, r3, 8
    atomadd_d r4, r3, -1
    bgt r4, r14, STILL_ELEM_IN_QUEUE, true
    atomadd_d r4, r3, 1
    beq r15, r15, ray_done, true
STILL_ELEM_IN_QUEUE:
    add r3, r3, -8
    atomadd_d r4, r3, 64
    add r3, r3, 540
    and r4, r4, 0x3FFF
    add r4, r3, r4
WAIT_FOR_WRITE:
    lbu_d r5, r4, 63
    beq r5, r14, WAIT_FOR_WRITE, false   # r7=0
    lw_d r6, r4, 0
    lw_d r7, r4, 4
    lw_d r8, r4, 8
    lw_d r9, r4, 12
    lw_d r10, r4, 16
    lw_d r11, r4, 20
    lw_d r12, r4, 24
    lw_d r13, r4, 28
    sw_d r6, r0, 0
    sw_d r7, r0, 4
    sw_d r8, r0, 8
    sw_d r9, r0, 12
    sw_d r10, r0, 16
    sw_d r11, r0, 20
    sw_d r12, r0, 24
    sw_d r13, r0, 28
    lw_d r6, r4, 32
    lw_d r7, r4, 36
    lw_d r8, r4, 40
    lw_d r9, r4, 44
    lw_d r10, r4, 48
    lw_d r11, r4, 52
    lw_d r12, r4, 56
    lw_d r13, r4, 60
    sw_d r6, r0, 32
    sw_d r7, r0, 36
    sw_d r8, r0, 40
    sw_d r9, r0, 44
    sw_d r10, r0, 48
    sw_d r11, r0, 52
    sw_d r12, r0, 56
    sw_d r13, r0, 60
    sb_d r14, r4, 63
    add r6, r14, 1
    sb r6, r0, 63
    lw r1, r0, 40                   # node = ray->leaf_node_starting_point
    sll r1, r1, 1
    lhu r1, r1, LEAF_CORE_LOOKUP_TABLE
    beq r15, r15, start_ray_traversal, true
DRAM_RAY_QUEUE_EMPTY:
    yield r8
    lw r3, RAY_QUEUE_HIGH
    setmembits r3
    lw r3, RAY_QUEUE_LOW
    lw_d r4, r3, 8
    blte r4, r14, CHECK_SPAWNED_RAY_POOL, true
    add r3, r3, 8
    atomadd_d r4, r3, 1
    blte r4, r14, EMERGENCY_SWITCH_BEGIN, false
    atomadd_d r4, r3, -1
    beq r15, r15, CHECK_SPAWNED_RAY_POOL, true
EMERGENCY_SWITCH_BEGIN:
    add r3, r3, -8
    atomadd_d r4, r3, 4
    and r4, r4, 0xFF
    add r3, r3, r4
    add r3, r3, 12
ENSURE_EMERGENCY_SLOT_READY:
    lhu_d r4, r3, 2
    beq r4, r14, ENSURE_EMERGENCY_SLOT_READY, false
    lhu_d r4, r3, 0
    add r5, r14, 1
    sh_d r5, r3, 0
    sw r5, LOCAL_QUEUE_FLUSHING
    sw r4, CORE_ID_TO_SWITCH_TO
    beq r15, r15, SWITCH_DRAM_QUEUE, true

CHECK_SPAWNED_RAY_POOL:
    jmp r2, IS_IDLE_BRANCH
    lw r2, SPAWNED_RAY_POOL_HIGH
    setmembits r2
    lw r2, SPAWNED_RAY_POOL_LOW
    lw_d r3, r2, 8
    blte r3, r14, GRAB_FROM_TILE, true
    add r2, r2, 8
    atomadd_d r3, r2, -1
    blte r14, r3, CONTINUE_REMOVING_FROM_SPAWNED_RAY_POOL, true
    atomadd_d r3, r2, 1
    beq r15, r15, GRAB_FROM_TILE, true
CONTINUE_REMOVING_FROM_SPAWNED_RAY_POOL:
    add r2, r2, -8
    atomadd_d r3, r2, 32
    lw r4, SPAWNED_RAY_POOL_MASK
    and r3, r3, r4
    add r2, r2, r3
ENSURE_RAY_POOL_SLOT_READY:
    lbu_d r3, r2, 43
    beq r3, r14, ENSURE_RAY_POOL_SLOT_READY, false
    lw_d r3, r2, 12
    lw_d r4, r2, 16
    lw_d r5, r2, 20
    lw_d r6, r2, 24
    lw_d r7, r2, 28
    lw_d r8, r2, 32
    lw_d r9, r2, 36
    lh_d r10, r2, 40
    sb_d r14, r2, 43
    sw r3, r0, 0
    sw r4, r0, 4
    sw r5, r0, 8
    sw r6, r0, 12
    sw r7, r0, 16
    sw r8, r0, 20
    sw r9, r0, 52
    and r3, r10, 0xFF #bounce count
    srl r4, r10, 8
    and r4, r4, 0xFF # light_id
    sb r3, r0, 60
    sb r4, r0, 61
    lw r5, r0, 12
    lw r6, r0, 16
    lw r7, r0, 20
    fpmul.32 r8, r5, r5
    fpmul.32 r9, r6, r6
    fpmul.32 r10, r7, r7
    fadd r8, r8, r9
    fadd r8, r8, r10
    jmp r9, INV_SQRT
    fmul.32 r5, r5, r8
    fmul.32 r6, r6, r8
    fmul.32 r7, r7, r8
    add r9, r5, 0
    jmp r10, RECIPROCAL
    sw r9, r0, 24
    add r9, r6, 0
    jmp r10, RECIPROCAL
    sw r9, r0, 28
    add r9, r7, 0
    jmp r10, RECIPROCAL
    sw r9, r0, 32
    AND R14, R14, 0
    blte r14, r4, IS_NOT_SHADOW, false
    add r9, r8, 0
    jmp r10, RECIPROCAL
    beq r15, r15, FINISH_SETTING_OTHER_RAY_FIELDS, true
IS_NOT_SHADOW:
    lw r2, INFINITY
    sw r2, r0, 36
FINISH_SETTING_OTHER_RAY_FIELDS:
    AND R14, R14, 0
    sw r14, r0, 44
    sw r14, r0, 48
    add r13, r14, -1
    sw r13, r0, 56
    add r12, r14, 1
    sb r12, r0, 63
    sb r14, r0, 62
    lw r1, ROOT_NODE_ADDRESS
    beq r15, r15, start_ray_traversal, true
GRAB_FROM_TILE:
    lh r2, TILE_IS_ACTIVE
    and r14, r14, 0
    beq r2, r14, GET_NEW_TILE, false
    lw r2, TILE_DATA_COUNT
    add r3, r14, 255
    bgt r2, r3, SKIP_RETURNING_TILE, true
    lw r2, RAYS_SPAWNED_FROM_TILE
    add r3, r14, 7 # TODO, Threshold for when to return tile to queue
    bgt r3, r2, SPAWN_FROM_TILE, false
    lw r4, RAYS_FORWARDED_OUT_FROM_TILE
    sll r4, r4, 1
    bgt r2, r4, SPAWN_FROM_TILE, true
GET_NEW_TILE:
    getowner
    and r14, r14, 0
    lw r2, TILE_QUEUE_HIGH
    setmembits r2
    lw r2, TILE_QUEUE_LOW
    lhu r3, TILE_IS_ACTIVE
    bne r3, r14, SKIP_RETURNING_TILE, false
    lw r3, RAYS_SPAWNED_FROM_TILE
    add r4, r14, 255
    bgt r3, r4, SKIP_RETURNING_TILE, true
    add r2, r2, 8
    atomadd_d r15, r2, 1
    add r2, r2 -4
    atomadd_d r3, r2, 4
    add r4, r14, 255
    sll r4, r4, 8
    add r4, r4, 255
    and r3, r3, r4
    add r2, r2, r3
    add r2, r2, 8
WAIT_FOR_TILE_SLOT_TO_OPEN:
    lbu r3, r2, 3
    beq r3, r14, WAIT_FOR_TILE_SLOT_TO_OPEN, false
    lhu_d r3, r2, 0 #index
    lbu_d r4, r2, 2 #cnt
    sb_d r14, r2, 3 #mark slot as taken
    sw r4, TILE_DATA_COUNT
    div r5, r4, 160
    mul r6, r5, 160
    sub r6, r4, r6
    add r2, r14, TILE_INTER_INDEX
    sh r6, r2, 0
    sh r5, r2, 2
    sw r14, r2, 4
    sw r14, r2, 8
    sw r14, r2, 12
    sw r14, r2, 16
    and r3, r15, 0xF
    add r2, r3, r2
    add r4, r14, 1
    sb r4, r2, 4
    sw r14, RAYS_FORWARDED_OUT_FROM_TILE
    sw r14, RAYS_SPAWNED_FROM_TILE
    setctx 16
    relinquish 0
SPAWN_FROM_TILE:
    AND r14, r14, 0
    add r2, r14, TILE_DATA_COUNT
    atomadd r3, r2, 1
    add r4, r14, 255
    bgt r3, r4, GET_NEW_TILE, false
    add r2, r2, 28
    atomadd r15, r2, 1
    and r4, r3, 0xF #intra x
    srl r5, r3, 4 # intra y
    lhu r6, r2, 8 # inter x
    lhu r7, r2, 10 # inter y
    sll r6, r6, 4
    sll r7, r7, 4
    add r6, r6, r4 #tile_x_index
    add r7, r7, r5  #tile_y_index
    sh r6, r0, 52
    sh r7, r0, 54
    lw r2, INT_TO_FLOAT_TABLE_HIGH
    setmembits r2
    lw r2, INT_TO_FLOAT_TABLE_LOW
    sll r6, r6, 2
    sll r7, r7, 2
    add r6, r2, r6
    add r7, r2, r7
    lw_d r3, r6, 0 #fpix_x
    lw_d r4, r7, 0 #fpix_y
    lw r5, CAM_X
    sw r5, r0, 0
    lw r6, CAM_Y
    sw r6, r0, 4
    lw r7, CAM_INV_FOCAL
    sw r7, r0, 8
    fsub.32 r8, r3, r5
    fsub.32 r9, r4, r6
    fmul.32 r2, r8, r7 #r2 = dx
    fmul.32 r3, r9, r7 #r3 = dy
    lw r4, NEG_ONE #r4 = dz
    fmul.32 r5, r2, r2
    fmul.32 r6, r3, r3
    fmul.32 r7, r4, r4)
    fadd.32 r5, r5, r6
    fadd.32 r9, r5, r7 
    add r6, r8, 0
    add r7, r9, 0
    jmp r9, INV_SQRT
    fmul.32 r9, r8, r2
    jmp r10, RECIPROCAL
    sw r9, r0, 24
    fmul.32 r9, r8, r3
    jmp r10, RECIPROCAL
    sw r9, r0, 28
    fmul.32 r9, r8, r4
    jmp r10, RECIPROCAL
    sw r9, r0, 32
    sw r2, r0, 12
    sw r3, r0, 16
    sw r4, r0, 20
    lw r2, INFINITY
    sw r2, r0, 36
    and r14, r14, 0
    sw r14, r0, 44
    sw r14, r0, 48
    sw r14, r0, 60
    add r13, r14, 1
    add r12, r14, -1
    sw r12, r0, 56
    sb r13, r0, 63
    lw r1, ROOT_NODE_ADDRESS
    goto start_ray_traversal
SKIP_GRABBING_TILE_RAYS:
    yield r8
    lw r2, RAYS_COMPLETED_HIGH
    setmembits r2
    lw r2, RAYS_COMPLETED_LOW
    lw_d r2, r2, 0
    lw r3, MAX_RAYS
    yield r8
    bne r2, r3, ray_done, true

#below is the final pass of the main loop, calculating the color of the final image
    getowner
    setctx 14
    relinquish 1
    yield r15
    lw r0, RAYS_COMPLETED_HIGH
    setmembits r0
    lw r0, RAYS_COMPLETED_LOW
    srl r1, r15, 4
    and r2, r15, 0xF
    mul r1, r1, 15
    srl r1, r1, 8 #r1 = pix_increment
    add r0, r0, r1
    and r14, r14, 0
    and r1, r1, 0

LOOP_PIXEL:
    add r2, r14, 2 #NUM_BOUNCES - 1
    add r4, r14, RAY_ARRAY
    and r5, r15, 0xF
    sll r5, r5, 6
    add r4, r4, r5 #r4 = backup for register pressure
    sw r14, r4, 0 #carried_r
    sw r14, r4, 4 #carried_g
    sw r14, r4, 8 #carried_b
BOUNCE_LOOP:
    sll r5, r2, 6
    add r5, r0, r5 #bounce address, it's the address of a ray slot
    lw_d r6, r5, 0 #sr
    lw_d r7, r5, 4 #sg
    lw_d r8, r5, 8 #sb
    lw_d r9, r5, 12 #metallic
    sw r6, r4, 12
    sw r7, r4, 16
    sw r8, r4, 20
    sw r9, r4, 24
    sw r14, r4, 28 #acc_r
    sw r14, r4, 32 #acc_g
    sw r14, r4, 36 #acc_b
    add r5, r5, 16
    and r6, r6, 0 #light
SHADOW_LOOP:
    lw_d r9, r5, 12 #len_sq
    or r8, r8, 0xFFFFFFFF
    beq r9, r8, SHADOW_SKIP
    jmp r10, RECIPROCAL
    lw_d r7, r5, 0
    lw_d r8, r5, 4
    lw_d r10, r5, 8
    fmul.32 r7, r7, r9
    fmul.32 r8, r8, r9
    fmul.32 r10, r10, r9
    lw r11, r4, 28
    lw r12, r4, 32
    lw r13, r4, 36
    fmul.32 r11, r11, r7
    fmul.32 r12, r12, r8
    fmul.32 r13, r13, r10
    sw r11, r4, 28
    sw r12, r4, 32
    sw r13, r4, 36
SHADOW_SKIP:
    add r5, r5, 16
    add r6, r6, 1
    add r7, r14, 3
    bgt r7, r6, SHADOW_LOOP, true 

    lw r6, r4, 28 
    lw r7, r4, 32 
    lw r8, r4, 36
    lw r9, r4, 12 #sr
    lw r10, r4, 16 #sg
    lw r11, r4, 20 #sb
    lw r12, r4, 24
    lw r13, ONE
    fsub r13, r13, r12 #1-metallic
    fmul.32 r6, r6, r9 #diffuse_r
    fmul.32 r7, r7, r10 #diffuse_g
    fmul.32 r8, r8, r11 #diffuse_b
    fmul.32 r6, r6, r13 #diffuse_r * metallic
    fmul.32 r7, r7, r13 #diffuse_g * metallic
    fmul.32 r8, r8, r13 #diffuse_b * metallic
    lw r13, r4, 0
    fmul.32 r13, r13, r9
    fmul.32 r13, r13, r12 #light_r * metallic
    fmul.32 r6, r6, r13 #diffuse_r * metallic * light_r
    sw r6, r4, 0
    lw r13, r4, 4
    fmul.32 r13, r13, r10
    fmul.32 r13, r13, r12 #light_g * metallic
    fmul.32 r7, r7, r13 #diffuse_g * metallic * light_g
    sw r7, r4, 4
    lw r13, r4, 8
    fmul.32 r13, r13, r11
    fmul.32 r13, r13, r12 #light_b * metallic
    fmul.32 r8, r8, r13 #diffuse_b * metallic * light_b
    sw r8, r4, 8
    add r2, r2, -1
    bgte r14, r2, BOUNCE_LOOP, true
BOUNCE_DONE: //Label not used lol
    lw r13, ONE
    lw r10, r4, 0
    lw r11, r4, 4
    lw r12, r4, 8
    fadd.32 r10, r10, r13
    fadd.32 r11, r11, r13
    fadd.32 r12, r12, r13
    srl r10, r10, 14
    srl r11, r11, 14
    srl r12, r12, 14
    and r10, r10, 0x1FF
    and r11, r11, 0x1FF
    and r12, r12, 0x1FF
    lbu r10, r10, FLOAT_TO_BYTE_RGB_TABLE
    lbu r11, r11, FLOAT_TO_BYTE_RGB_TABLE
    lbu r12, r12, FLOAT_TO_BYTE_RGB_TABLE
    lw r13, FRAME_BUF_HIGH
    setmembits r13
    lw r13, FRAME_BUF_LOW
    srl r14, r15, 4
    mul r14, r14, 15
    and r9, r14, 0xF
    add r14, r9, r14
    sll r14, r14, 2
    add r13, r13, r14
    mul r9, r1, 8192
    mul r9, r9, 60
    add r13, r13, r9
    sb r10, r13, 0
    sb r11, r13, 1
    sb r12, r13, 2
    add r1, r1, 1
    mul r13, r1, 8192
    mul r13, r13, 3840
    add r0, r0, r13
    and r14, r14, 0
    add r14, r14, 30
    lw r13, FINISHED_PIXELS_HIGH
    setmembits r13
    lw r13, FINISHED_PIXELS_LOW
    atomadd_d r13, r13, 1
    bgt r14, r1, LOOP_PIXEL, true

INF_LOOP:
    yield r15
    beq r15, r15, INF_LOOP, true



FINISHED_PIXELS_HIGH:   .data -1
FINISHED_PIXELS_LOW:    .data -1
ONE:                    .data 0x3F800000
MAX_RAYS:              .data 58982400
EPSILON:                .data 0x38D1B717
NEG_ONE:                .data 0xBF800000
INFINITY:               .data 0x7F800000
SPAWNED_RAY_POOL_MASK:  .data 0x007FFFFF
RAY_SEND_PENDING_ADDR:  .data 0
LOCAL_QUEUE:            .data 0
LOCAL_QUEUE_FLUSHING:   .data 0
LOCAL_RAY_QUEUE:        .data 0
LOCAL_RAY_QUEUE_HEAD:   .data 0
ROOT_NODE_ID:           .data 0
LEAF_CORE_LOOKUP_TABLE: .data 0    
IS_BRANCH_CORE: .data -1
RAY_QUEUE_HIGH: .data -1
RAY_QUEUE_LOW: .data -1
EMERGENCY_QUEUE_HIGH: .data -1
EMERGENCY_QUEUE_LOW: .data -1
SPAWNED_RAY_POOL_HIGH: .data -1
SPAWNED_RAY_POOL_LOW: .data -1
TILE_QUEUE_HIGH: .data -1
TILE_QUEUE_LOW: .data -1
RAY_RESULT_HIGH: .data -1
RAY_RESULT_LOW: .data -1
RAYS_COMPLETED_HIGH: .data -1
RAYS_COMPLETED_LOW: .data -1
FRAME_BUF_HIGH: .data -1
FRAME_BUF_LOW: .data -1
NODE_ARRAY_HIGH: .data -1
NODE_ARRAY_LOW: .data -1
TRIANGLE_ARRAY_HIGH: .data -1
TRIANGLE_ARRAY_LOW: .data -1
INT_TO_FLOAT_TABLE_HIGH: .data -1
INT_TO_FLOAT_TABLE_LOW: .data -1
DIV_TABLE_HIGH: .data -1
DIV_TABLE_LOW: .data -1
INV_SQRT_TABLE_HIGH: .data -1
INV_SQRT_TABLE_LOW: .data -1
IDLE_QUEUE_HIGH: .data -1
IDLE_QUEUE_LOW: .data -1
RANDOM_TABLE_HIGH: .data -1
RANDOM_TABLE_LOW: .data -1
CAM_X: .data -1
CAM_Y: .data -1
CAM_Z: .data -1
CAM_CX: .data -1
CAM_CY: .data -1
CAM_INV_FOCAL: .data -1
RAY_SEND_PENDING: .data -1
PULLED_FROM_FULL_QUEUE_CNT: .data -1
FLUSHING_LOCAL_QUEUE: .data 0
CORE_ID_TO_SWITCH_TO: .data -1
TILE_DATA_COUNT: .data 0 #count
TILE_IS_ACTIVE: .data 0 
TILE_INTER_INDEX: .data 0 #tile_x_index/tile_y_index
TILE_CUR_RAY_SPAWNED:.data 0 #cur_ray_spawned_from_tile[16] in bytes
.data 0 
.data 0 
.data 0
RAYS_SPAWNED_FROM_TILE: .data 0 #rays_spawned_from_tile
RAYS_FORWARDED_OUT_FROM_TILE: .data 0 #rays_forwarded_out_from_tile
RAYS_PROCESSED: .data 0
LAST_OBSERVED_CYCLE: .data 0
PREVIOUSLY_IDLE: .data 0
FLOAT_TO_BYTE_RGB_TABLE: .data(128) 0
LIGHT_ARRAY: .data(18) 0
ROOT_NODE_ADDRESS: .data 0
//DO NOT INCLUDE LINES BELOW THIS AS PULLED FROM DRAM
RAY_ARRAY: .data(256) 0
LEAF_CORE_LOOKUP_TABLE: .data(64) 0
SENDER_RAY_QUEUE: .data(1036) 0
RECEIVER_RAY_QUEUE: .data(1036) 0
