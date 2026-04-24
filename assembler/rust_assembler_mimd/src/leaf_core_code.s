.org IDK //TODO

    lw r2, ROOT_NODE_ID         # r2 = node
START_SEARCHING:
    yield r8                    # clobber r8
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
    lhu r6, r1, 26                  # r6 = node->right_child (uint16 at offset 25)
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
    beq r6, r7, CHECK_BOTH_ZERO, true   # if r6 == 0, neither both set - check other cases

    # uint32_t bitfield = *(ray.check_left + node->is_right * 4);
    lbu r6, r1, 32                  # r6 = node->is_right
    sll r6, r6, 2                   # r6 = node->is_right * 4
    add r6, r0, r6                  # r6 = &ray.check_left + is_right*4
    lw r8, r6, 44                    # r8 = bitfield


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

    # if (node->parent == 0) goto send_ray_up;
    lhu r6, r1, 28                  # r6 = node->parent
    beq r6, r7, send_ray_up, true  # r7 = 0

    # node = node->parent;
    and r1, r1, 0
    add r1, r1, r6                  # r1 = node->parent (SRAM pointer)
    beq r15, r15, START_SEARCHING, true
    
CHECK_BOTH_ZERO:
    # else if (left_bitfield_check == 0 && right_bitfield_check == 0)
    or r6, r4, r9                   # r6 = left | right
    bne r6, r7, TRAVERSE_LEFT_OR_RIGHT, false       # both zero -> do AABB test

    jmp r8, AABB_INTERSECT 
AABB_INTERSECT_RETURN:
    # if (hit)
    beq r11, r7, AABB_MISS, true

    # if (node->tri_count == 0) <- ASSUME RAY -> TRI_INDEX
    lbu r6, r0, 56                  # TODO confirm offset
    beq r6, r7, IS_INTERNAL_NODE, true
    beq r15, r15, IS_LEAF_NODE, true

IS_INTERNAL_NODE:
    # ray->ray_depth++
    lbu r5, r0, 62
    add r5, r5, 1
    sb r5, r0, 62
    # if (node->core_owner != 0xFFFF)
    lhu r6, r1, 30                  # r6 = node->core_owner (uint16 offset 32) TODO confirm offset
    and r7, r7, 0
    add r7, r7, 0xFFFF
    beq r6, r7, TRAVERSE_OWN_CHILD, true   # owner == 0xFFFF means we own it
    # uint16_t ray_send_pending_addr = self.ray_send_pending_addr;
    lw r8, RAY_SEND_PENDING_ADDR    # r8 = self.ray_send_pending_addr

    # atomic_add(ray_send_pending_addr, 1)
    atomadd r9, r8, 1               # r9 = clobber
    and r3, r3, 0                   # r3 = sent = 0
    and r4, r4, 0
    add r4, r4, -1                  # r4 = slot = 0xFFFFFFFF
    
    and r10, r15, 0xF               # r10 = thread_id
    and r11, r10, 1                 # r11 = is_thread_odd


TRAVERSE_OWN_CHILD:
IS_LEAF_NODE:
    

TRAVERSE_LEFT_OR_RIGHT:


triangle_intersect: 
    #void Triangle_Intersect(Triangle *tri, Ray *ray, Vertex *vertices)
    # tri in r2 = index ptr, ray is in r0, i won't touch r3 or r2 or r1. 
    lw r13, VERTEX_ARRAY_BASE                   # r13 = Vertex * vertices
    and r14, r14, 0
    add r4, r14, RAY_TRIANGLE_REG_SPILL
    and r5, r15, 0xF
    sll r5, r5, 6
    add r4, r4, r5
    add r8, r2, r13
    lhu r5, r8, 4
    lhu r6, r8, 6
    lhu r7, r8, 8
    lw r8, TRIANGLE_ARRAY_BASE
    add r5, r5, r8 #v0
    add r6, r6, r8 #V1
    add r7, r7, r8 #V2
    lw r12, r5, 0 #v0x
    lw r9, r6, 0
    fpsub.32 r8, r9, r12 #e1x
    lw r9, r6, 4
    lw r13, r5, 4 #v0y
    fpsub.32 r9, r9, r13 #e1y
    lw r10, r6, 8 
    lw r14, r5, 8 #v0z
    fpsub.32 r10, r10, r14 #e1z
    sw r8, r4, 0
    sw r9, r4, 4
    sw r10, r4, 8
    lw r8, r7, 0
    lw r9, r7, 4
    lw r10, r7, 8
    fpsub.32 r8, r8, r12 #e2x
    fpsub.32 r9, r9, r13 #e2y
    fpsub.32 r10, r10, r14 #e2z i have 11-14 now i think
    sw r8, r4, 12
    sw r9, r4, 16
    sw r10, r4, 20
    lw r11, r0, 16 #dy
    fpmul.32 r11, r11, r10 # ray->dy * e2z
    lw r12, r0, 20 #dz
    fpmul.32 r13, r9, r12 #ray->dz * e2y I now have  r14, r10 available
    fpsub.32 r11, r11, r13 #px, now available registers are r13, r14, r10
    fpmul.32 r12, r12, r8 # ray->dz * e2x 
    lw r14, r0, 12 #dx
    fpmul.32 r13, r14, r10 #ray->dx * e2z
    fpsub.32 r13, r12, r13 #py i now have r12, r10
    fpmul.32 r14, r14, r9  #ray->dx * e2y
    lw r12, r0, 16 #dy
    fpmul.32 r12, r12, r8 #ray->dy * e2x
    fpsub.32 r14, r14, r12 #pz
    and r12, r12, 0
    fpsetaccum.32 r12
    lw r8, r4, 0
    lw r9, r4, 4
    lw r10, r4, 8
    fpmac.32 r8, r11
    fpmac.32 r9, r13
    fpmac.32 r10, r14
    fpstoreaccum.32 r8
    beq r8, r12, TRIANGLE_INTERSECT_RETURN, false #I have 9, 10, and 12 available
    lw r6, r0, 0
    lw r7, r5, 0
    fpsub.32 r6, r6, r7
    lw r7, r0, 4
    lw r9, r5, 4
    fpsub.32 r7, r7, r9
    lw r9, r0, 8
    lw r10, r5, 8
    fpsub.32 r9, r9, r10
    and r10, r10, 0
    fpsetaccum.32 r10
    fpmac.32 r6, r11 
    fpmac.32 r7, r13
    fpmac.32 r9, r14
    fpstoreaccum.32 r12
    sw r6, r4, 32
    sw r7, r4, 36
    sw r9, r4, 40
    fplt r6, r10, r8
    bne r6, r10, TRIANGLE_INTERSECT_ELSE_BLOCK_1, false
    fplt r6, r12, r10
    fplt r7, r8, r12
    or r6, r6, r7
    bne r6, r10, TRIANGLE_INTERSECT_RETURN, true
    beq r15, r15, TRIANGLE_INTERSECT_END_IF_BLOCK_1, true
TRIANGLE_INTERSECT_ELSE_BLOCK_1:
    fplt r6, r10, r12
    fplt r7, r12, r8
    or r6, r6, r7
    bne r6, r10, TRIANGLE_INTERSECT_RETURN, true
TRIANGLE_INTERSECT_END_IF_BLOCK_1:
    sw r11, r4, 44
    sw r13, r4, 48
    sw r14, r4, 52
    lw r6, r4, 40
    lw r7, r4, 0
    lw r9, r4, 4 #e1y
    fpmul.32 r10, r6, r7 #tz * e1x
    fpmul.32 r6, r6, r9  #tz * e1y
    lw r11, r4, 36 #ty
    fpmul.32 r13, r11, r7 #ty * e1x
    lw r7, r4, 8 #e1z
    fpmul.32 r14, r7, r11 #ty * e1z
    fpsub.32 r14, r14, r6 #qx
    lw r6, r4, 32 #tx
    fpmul.32 r7, r6, r7 #tx * e1z
    fpsub.32 r10, r10, r7 #qy
    fpmul.32 r9, r9, r6 #tx * e1y
    fpsub.32 r9, r9, r13 #qz
    and r11, r11, 0
    fpsetaccum.32 r11
    lw r6, r0, 12
    fpmac.32 r6, r14
    lw r6, r0, 16
    fpmac.32 r6, r10
    lw r6, r0, 20
    fpmac.32 r6, r9
    fpstoreaccum.32 r7 #r7 = v_unscaled
    fpadd.32 r12, r7, r12 #r12 = uv_sum
    fplt.32 r13, r11, r8 #r8 = det
    beq r13, r11, TRIANGLE_INTERSECT_ELSE_BLOCK_2, false
    fplt.32 r5, r7, r11
    fplt.32 r6, r8, r12
    or r5, r5, r6
    bne r5, r11, TRIANGLE_INTERSECT_END_IF_BLOCK_2, true
    beq r15, r15, TRIANGLE_INTERSECT_RETURN, true
TRIANGLE_INTERSECT_ELSE_BLOCK_2:
    fplt.32 r5, r11, r7
    fplt.32 r6, r12, r8
    or r5, r5, r6
    bne r5, r11, TRIANGLE_INTERSECT_END_IF_BLOCK_2, true
    beq r15, r15, TRIANGLE_INTERSECT_RETURN, true
TRIANGLE_INTERSECT_END_IF_BLOCK_2:
    fpsetaccum.32 r11
    lw r5, r4, 12
    fpmac.32 r5, r14
    lw r5, r4, 16
    fpmac.32 r5, r10
    lw r5, r4, 20
    fpmac.32 r5, r9
    fpstoreaccum.32 r5 #t_unscaled
    lw r6, EPSILON
    fpmul.32 r6, r6, r8 #tmin_scaled
    lw r7, r0, 36
    fpmul.32 r7, r7, r8 #tmax_scaled
    fplt.32 r9, r11, r8
    beq r9, r11, TRIANGLE_INTERSECT_ELSE_BLOCK_3, false
    fplt.32 r6, r5, r6
    fplt.32 r7, r7, r5
    or r6, r6, r7
    beq r11, r6, TRIANGLE_INTERSECT_END_IF_BLOCK_3, false
    beq r15, r15, TRIANGLE_INTERSECT_RETURN, true
TRIANGLE_INTERSECT_ELSE_BLOCK_3:
    fplt.32 r6, r6, r5
    fplt.32 r7, r5, r7
    or r6, r6, r7
    beq r11, r6, TRIANGLE_INTERSECT_END_IF_BLOCK_3, false
    beq r15, r15, TRIANGLE_INTERSECT_RETURN, true
TRIANGLE_INTERSECT_END_IF_BLOCK_3:
    add r9, r8, 0
    jmp r10, RECIPROCAL
    fpmul.32 r5, r5, r9
    sw r5, r0, 36
    lw r6, r2, 0
    sw r6, r0, 56
    beq r15, r15, TRIANGLE_INTERSECT_RETURN, true



AABB_INTERSECT: #do not use r4, r9. r0 = ray, r1 = node, r7 = 0
    lw r2, r1, 0                        
    lw r3, r0, 0
    fpsub.32 r2, r2, r3                   # float t1 = (node->min_x - ray->ox) * ray->inv_dx
    lw r5, r0, 24
    fpmul.32 r2, r2, r5                   # t1 *= ray->inv_dx
    lw r6, r1, 4
    fpsub.32 r3, r6, r3                   # float t2 = (node->max_x - ray->ox) * ray->inv_dx
    fpmul.32 r3, r3, r5                   # t2 *= ray->inv_dx
    fpminmax.32 r12, r2, r3, false         # float tmin = min(t1, t2)
    fpminmax.32 r3, r2, r3, true          # float tmax = max(t1, t2)
    lw r2, r0, 36
    fpminmax.32 r13, r2, r3, false          # tmax = min(tmax, ray->t_max)
    fplt.32 r6, r12, r13                  # r6 = tmin < tmax
    lw r10, EPSILON                 # float epsilon = self.epsilon
    fplt.32 r8, r10, r13                # r8 = epsilon < tmax
    and r11, r6, r8                     # r11 = (tmax >= tmin) && (tmax > epsilon)
    blte r7, r11, AABB_INTERSECT_RETURN, false  # if (tmax < EPSILON) return false
    #doing y now
    lw r2, r1, 8
    lw r3, r0, 4
    fpsub.32 r2, r2, r3                   # float t1 = (node->min_x - ray->ox) * ray->inv_dx
    lw r5, r0, 28
    fpmul.32 r2, r2, r5                   # t1 *= ray->inv_dx
    lw r6, r1, 12
    fpsub.32 r3, r6, r3                   # float t2 = (node->max_x - ray->ox) * ray->inv_dx
    fpmul.32 r3, r3, r5                   # t2 *= ray->inv_dx
    fpminmax.32 r5, r2, r3, false         # float tmin = min(t1, t2)
    fpminmax.32 r3, r2, r3, true          # float tmax = max(t1, t2)
    fpminmax.32 r13, r13, r3, false          # tmax = min(tmax, ray->t_max)
    fpminmax.32 r12, r12, r5, true          # tmin = max(tmin, t1)
    fplt.32 r6, r12, r13                  # r6 = tmin < tmax
    fplt.32 r8, r10, r13                # r8 = epsilon < tmax
    and r11, r6, r8                     # r11 = (tmax >= tmin) && (tmax > epsilon)
    blte r7, r11, AABB_INTERSECT_RETURN, false  # if (tmax < EPSILON) return false
    #doing z now
    lw r2, r1, 16                           # r2 = node->z_min
    lw r3, r0, 8                            # r3 = ray->oz
    fpsub.32 r2, r2, r3                     # r2 = node->z_min - ray->oz
    lw r5, r0, 32                           # r5 = ray->inv_dz
    fpmul.32 r2, r2, r5                     # tz1 = (node->z_min - ray->oz) * ray->inv_dz
    lw r6, r1, 20                           # r6 = node->z_max
    fpsub.32 r3, r6, r3                     # r3 = node->z_max - ray->oz
    fpmul.32 r3, r3, r5                     # tz2 = (node->z_max - ray->oz) * ray->inv_dz
    fpminmax.32 r5, r2, r3, false           # r5 = min(tz1, tz2)
    fpminmax.32 r3, r2, r3, true            # r3 = max(tz1, tz2)
    fpminmax.32 r13, r13, r3, false         # tmax = min(tmax, max(tz1, tz2))
    fpminmax.32 r12, r12, r5, true          # tmin = max(tmin, min(tz1, tz2))
    fplt.32 r6, r12, r13                    # r6 = tmin < tmax
    fplt.32 r8, r10, r13                     # r8 = epsilon < tmax
    and r11, r6, r8                         # r11 = (tmin <= tmax) && (0.0 < tmax)
    beq r15, r15, AABB_INTERSECT_RETURN, true # return r11



VERTEX_ARRAY_BASE:       .data 0
SRAM_ALLOC_COUNT:       .data 0
SRAM_NODE_ALLOC_PTR:     .data 0
NODE_ARRAY_TOP:         .data 0
ROOT_NODE_ID:           .data 0
BRANCH_START_OF_CODE:    .data -1
BRANCH_NUM_INSTRUCTION_BYTES: .data -1
BRANCH_START_OF_GEO:     .data -1
BRANCH_SIZE_OF_GEO:      .data -1
SAVED_BRANCH_HIGH:       .data -1
SAVED_BRANCH_LOW:        .data -1
SEARCH_FOR_IDLE_CORES_STORAGE: .data -1
BRANCH_IDLE_THRESHOLD:    .data -1
IDLE_WINDOW:             .data 100000
EAT_RAY_MASK:            .data 0x0001FFFF
HALF:                    .data 0x3F000000
TWO:                     .data 0x40000000
RECIPROCAL_STORAGE:      .data -1
NEG_MAX:                 .data 0x80000000
ONE_POINT_FIVE:          .data 0x3FC00000
RANDOM_FLOAT_AND_MASK:    .data 0x3FFFFFFF
RANDOM_TABLE_MASK:       .data 0x0003FFF0
MAX_RAYS_IN_RAY_POOL:    .data 260000
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
ROOT_NODE_ID_SENDER:    .data -1
ROOT_NODE_ID_RECEIVER:  .data -1
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
LIGHT0_X: .data -1
LIGHT0_Y: .data -1
LIGHT0_Z: .data -1
LIGHT0_R: .data -1
LIGHT0_G: .data -1
LIGHT0_B: .data -1
LIGHT1_X: .data -1
LIGHT1_Y: .data -1
LIGHT1_Z: .data -1
LIGHT1_R: .data -1
LIGHT1_G: .data -1
LIGHT1_B: .data -1
LIGHT2_X: .data -1
LIGHT2_Y: .data -1
LIGHT2_Z: .data -1
LIGHT2_R: .data -1
LIGHT2_G: .data -1
LIGHT2_B: .data -1
ROOT_NODE_ADDRESS: .data 0
//DO NOT INCLUDE LINES BELOW THIS AS PULLED FROM DRAM
RAY_ARRAY: .data(256) 0
LEAF_CORE_LOOKUP_TABLE: .data(64) 0
SENDER_RAY_QUEUE: .data(1036) 0
RECEIVER_RAY_QUEUE: .data(1036) 0
DFS_STACK: .data(256) 0
RAY_TRIANGLE_REG_SPILL: .data(256) 0
