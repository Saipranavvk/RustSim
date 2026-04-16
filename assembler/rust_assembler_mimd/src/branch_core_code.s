.org IDK //TODO

    # initialize_core();
    beq r15, r15, initialize_core, true

    # yield();
    yield rD            # TODO determine rD 

    # if (ray->check_left & 1 != 0 && ray->check_right & 1 != 0)
    # {
    #     goto complete_ray;
    # }

    lw r2, r0, 18       # r2 = ray -> check_left
    and r4, r2, 1       
    lw r3, r0, 22       # r3 = ray -> check_right
    and r5, r3, 1
    and r4, r4, r5      # r4 = ray->check_left & 1 && ray->check_right & 1
    and r5, r5, 0
    add r5, r5, 1       # r5 = 1
    beq r4, r4, complete_ray, false

    # uint32_t left_bitfield_check = ray->check_left & (1 << ray->ray_depth) | node->left_child == 0;
    lw r5, r0, 56       # r5 = ray->ray_depth
    and r4, r4, 0       
    add r4, r4, 1       # r4 = 1
    sll r4, r4, r5      # r4 = 1 << ray->ray_depth
    and r4, r4, r2      # r4 = ray->check_left & (1 << ray->ray_depth)
    and r5, r5, 0


    






NODE_ID: .data -1
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
FLUSHING_LOCAL_QUEUE: .data -1
TILE_DATA: .data 0
.data 0 #count
.data 0 #is_active/tile_x_index/tile_y_index
.data 0 #cur_ray_spawned_from_tile[16] in bytes
.data 0 
.data 0 
.data 0
.data 0 #rays_spawned_from_tile
.data 0 #rays_forwarded_out_from_tile
RAYS_PROCESSED: .data 0
LAST_OBSERVED_CYCLE: .data 0
PREVIOUSLY_IDLE: .data 0
//DO NOT INCLUDE LINES BELOW THIS AS PULLED FROM DRAM
LIGHT_ARRAY: .data(18) 0
RAY_ARRAY: .data(256) 0
LEAF_CORE_LOOKUP_TABLE: .data(65) 0
SENDER_RAY_QUEUE: .data(1036)
RECEIVER_RAY_QUEUE: .data(1036)
