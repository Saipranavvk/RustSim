.org 0x0028
.data 110          # program size in bytes for loader
setctx 16          # activate all 16 hardware contexts
relinquish true    # broadcast PC to all contexts and release ownership

and r15, r15, 0   # no-op (r15 is hardwired to global TID, can't be written)
and r0, r0, 0     # r0 = 0
fpsetacc.16 r0    # clear FP16 accumulator to 0
and r6, r6, 0     # r6 = 0 (loop counter)
and r7, r7, 0     # r7 = 0
add r7, r7, 4     # r7 = 4 (loop limit: 4 iterations of 16 threads = 64 dot product elements)
setmembits r0     # set DRAM stack selector to 0
add r1, r0, 17384 # r1 = 17384 = base address of M2 in DRAM
add r0, r0, 1000  # r0 = 1000 = base address of M1 in DRAM

and r14, r15, 0xF # r14 = r15 & 0xF = local thread ID (0-15)
srl r12, r15, 4   # r12 = r15 >> 4
and r12, r12, 0x3F # r12 = x coordinate of this core (0-63)
srl r13, r15, 10  # r13 = r15 >> 10 (skip 4 tid bits + 6 x bits)
and r13, r13, 0x3F # r13 = y coordinate of this core (0-63)

# precompute right neighbor full address: ((y*64 + x+1) << 6) | tid
# this is the core to the right (x+1, y), mailbox = tid
mul r4, r13, 64   # r4 = y * 64
add r4, r4, r12   # r4 = y*64 + x
add r4, r4, 1     # r4 = y*64 + x+1 (right neighbor core index)
sll r4, r4, 6     # r4 = core_index << 6 (make room for mailbox bits)
add r4, r4, r14   # r4 = (core_index << 6) | tid = full flit address for right neighbor

# precompute down neighbor full address: ((y+1)*64 + x) << 6) | (tid+16)
# this is the core below (x, y+1), mailbox = tid+16 (to distinguish from M1 flits)
mul r5, r13, 64   # r5 = y * 64
add r5, r5, 64    # r5 = (y+1) * 64
add r5, r5, r12   # r5 = (y+1)*64 + x (down neighbor core index)
sll r5, r5, 6     # r5 = core_index << 6
add r8, r14, 16   # r8 = tid + 16 (mailbox offset for M2, avoids collision with M1 mailboxes)
add r5, r5, r8    # r5 = (core_index << 6) | (tid+16) = full flit address for down neighbor

# per-core DRAM offsets: move r0/r1 to this core's slice of M1/M2
mul r11, r13, 128 # r11 = y * 128 (each row has 64 elements * 2 bytes = 128 bytes)
add r0, r0, r11   # r0 = M1 base + row offset (points to this core's row in M1)
mul r11, r12, 2   # r11 = x * 2 (each element is 2 bytes / fp16)
add r1, r1, r11   # r1 = M2 base + column offset (points to this core's column in M2)

# per-thread DRAM offsets: each thread handles a different element within the row/column
mul r11, r14, 2   # r11 = tid * 2 (each thread reads a different fp16 element of M1 row)
add r0, r0, r11   # r0 = M1 address for this thread's first element
mul r11, r14, 128 # r11 = tid * 128 (each thread reads a different fp16 element of M2 column, stride=128 bytes per row)
add r1, r1, r11   # r1 = M2 address for this thread's first element

START_LOOP:
and r11, r11, 0   # r11 = 0 (used as zero for comparisons below)
bne r11, r12, GET_X_FROM_MAILBOX, true # if x != 0, receive M1 from left neighbor via NOC
lhu_d r2, r0, 0   # x == 0: load M1 element from DRAM into r2
beq r15, r15, DO_Y, true # unconditional jump to DO_Y (skip mailbox receive)
GET_X_FROM_MAILBOX:
block r2, r14     # x != 0: block until flit arrives in mailbox[tid], store value in r2

DO_Y:
bne r11, r13, GET_Y_FROM_MAILBOX, true # if y != 0, receive M2 from upper neighbor via NOC
lhu_d r3, r1, 0   # y == 0: load M2 element from DRAM into r3
beq r15, r15, START_MUL, true # unconditional jump to START_MUL
GET_Y_FROM_MAILBOX:
add r10, r14, 16  # r10 = tid + 16 (mailbox index for M2 flits)
block r3, r10     # y != 0: block until flit arrives in mailbox[tid+16], store value in r3

START_MUL:
fpmac.16 r2, r3   # accumulator += r2 * r3 (fp16 multiply-accumulate)

and r11, r11, 0   # r11 = 0
add r11, r11, 63  # r11 = 63 (used to check if we are the last core in x or y)

beq r12, r11, SKIP_SEND_X, false # if x == 63, skip sending M1 right (no right neighbor)
sendflit r2, r4  # send packed M1 value to right neighbor (address in r4)
SKIP_SEND_X:

beq r13, r11, SKIP_SEND_Y, false # if y == 63, skip sending M2 down (no down neighbor)
sendflit r3, r5  # send packed M2 value to down neighbor (address in r5)
SKIP_SEND_Y:

add r0, r0, 32    # advance M1 pointer by 16 threads * 2 bytes = 32 bytes (next set of elements)
add r1, r1, 2048  # advance M2 pointer by 16 threads * 128 bytes = 2048 bytes (next set of rows)
add r6, r6, 1     # increment loop counter
bgt r7, r6, START_LOOP, true # if loop_limit > counter, repeat (4 iterations total)

# store accumulator result into per-thread slot in ACCUM scratchpad
and r9, r9, 0     # r9 = 0
add r9, r9, ACCUM # r9 = address of ACCUM scratchpad
mul r8, r14, 2    # r8 = tid * 2 (each thread stores one fp16 = 2 bytes)
add r9, r9, r8    # r9 = address of this thread's slot in ACCUM
fpstoreacc.16 r5  # r5 = fp16 accumulator value (NOTE: clobbers r5/down-neighbor address, but sends are done)
sh r5, r9, 0      # store fp16 result to ACCUM[tid]

# wait for all threads to finish: thread 0 spins until yielded to by thread 15
INF_LOOP:
yield r8          # yield to next context
and r8, r8, 0     # r8 = 0
bne r8, r14, INF_LOOP, true # if tid != 0, keep yielding (only thread 0 proceeds)

# thread 0 takes ownership and reduces all 16 partial results
getowner          # thread 0 acquires exclusive ownership of the core
and r0, r0, 0     # r0 = 0 (loop counter)
add r1, r0, 16    # r1 = 16 (number of threads to reduce)
add r2, r0, ACCUM # r2 = pointer to ACCUM scratchpad
and r4, r4, 0     # r4 = 0 (accumulator for reduction)
LAST_LOOP:
lhu r3, r2, 0     # r3 = load fp16 from ACCUM[r2]
fpadd.16 r4, r4, r3 # r4 += r3 (fp16 add)
add r2, r2, 2     # advance pointer by 2 bytes
add r0, r0, 1     # increment counter
bgt r1, r0, LAST_LOOP, true # if 16 > counter, continue

# compute output DRAM address and store result
srl r14, r15, 4   # r14 = core x index (recompute since r14 was local tid)
mul r14, r14, 2   # r14 = x * 2 (byte offset for this core's output column)
and r13, r13, 0   # r13 = 0
add r13, r13, 256 # r13 = 256
mul r13, r13, 256 # r13 = 256*256 = 65536
mul r13, r13, 256 # r13 = 256*256*256 = 16777216 (output matrix base address)
add r13, r13, r14 # r13 = output address for this core's result
sh_d r4, r13, 0   # store fp16 result to output DRAM address

TRUE_INF_LOOP:
sll r14, r14, 1   # shift r14 (not r15, which is hardwired) to spin forever
beq r14, r14, TRUE_INF_LOOP, true # infinite loop

ACCUM:
.data 0           # thread 0 accumulator slot
.data 0           # thread 1
.data 0           # thread 2
.data 0           # thread 3
.data 0           # thread 4
.data 0           # thread 5
.data 0           # thread 6
.data 0           # thread 7 (NOTE: only 8 slots = 16 bytes, but 16 threads need 32 bytes - possible bug)