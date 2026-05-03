#!/usr/bin/env python3
"""
DRÆM core placement pipeline.

Inputs:
  bvh_nodes.txt              full BVH node table (node_id, AABB, leftFirst, triCount)
  leaf_core_roots_78pct.txt  list of leaf core root node IDs (one per line)

Hard-coded constants:
  BRANCH_ROOTS                166 branch core root node IDs (antichain)
  TREE_ROOT = 0
  K_GROUPS  = 8               (4 wide x 2 tall arrangement of 32x32 tiles)
  TILE     = 32
  SUPER_W, SUPER_H = 128, 64

Pipeline:
  1. Parse BVH and leaf-core-roots files.
  2. Build child map and parent map.
  3. Compute left-to-right DFS order of the 166 branch roots (descending
     left child first, stopping at each branch root).
  4. For each leaf, walk up to find the unique branch-root ancestor (owner).
  5. Split the 166 branch roots into 8 contiguous groups of size 20 or 21
     in DFS order (166 = 6*21 + 2*20).
  6. Build each group's node set: branch roots + leaves they own.
     If size > 1024, evict leaves from the most overweight branches first;
     evicted leaves go to a global "set aside" pool.
  7. Within each 32x32 tile, place nodes to minimize sum of weighted
     Manhattan distances over the within-group edges:
         (a) leaf<->leaf edges along left-to-right DFS order of leaves
             (chain restricted to leaves present in this group),
         (b) branch<->leaf edges between each leaf and its branch root.
     Method: spectral 2D embedding -> greedy snap to grid -> simulated
     annealing with random pair swaps. (Edge weight = 1 each; geometric
     distance comes from grid placement.)
  8. Tile 8 grids into 128x64 (4 columns x 2 rows). Pack set-aside leaves
     into empty cells anywhere in the super-grid.
  9. Write outputs:
        placement.csv   x,y,node_id,kind,group
        summary.txt     stats per group + final cost

Usage:
  python3 place_cores.py bvh_nodes.txt leaf_core_roots_78pct.txt out_dir/
"""

import math
import random
import sys
from pathlib import Path

# --------------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------------
TREE_ROOT = 0
K_GROUPS  = 8
TILE      = 32
TILES_PER_ROW = 4   # 4 wide, 2 tall
TILES_PER_COL = 2
SUPER_W   = TILE * TILES_PER_ROW   # 128
SUPER_H   = TILE * TILES_PER_COL   # 64
TILE_CAP  = TILE * TILE            # 1024

# Simulated annealing params
SA_ITERS_PER_TILE = 200_000
SA_T0   = 4.0
SA_T1   = 0.01
SEED    = 0xC0FFEE


# --------------------------------------------------------------------------
# Parsing
# --------------------------------------------------------------------------
def owners_and_leaves_in_one_pass(children, branch_set, leaf_set, tree_root=TREE_ROOT):
    """Single DFS from tree_root. For each leaf core root encountered,
    record its current branch-root ancestor (if any). Returns:
      owner            dict leaf_id -> branch_id
      leaves_by_branch dict branch_id -> [leaf_ids in DFS order]
    DFS descends left first so leaves come out in left-to-right order.
    """
    owner = {}
    leaves_by_branch = {b: [] for b in branch_set}
    # Stack entries: (node, current_branch_owner_or_None, entered_branch_here)
    # We use the "entered_branch_here" flag with a post-pop marker via a
    # negative sentinel. Simpler: explicit stack with action codes.
    # ENTER: visit node, push children
    # LEAVE: pop branch owner if we entered a branch here
    ENTER, LEAVE = 0, 1
    stack = [(ENTER, tree_root, None)]
    cur_owner = None
    visited = 0
    while stack:
        action, n, payload = stack.pop()
        if action == LEAVE:
            cur_owner = payload  # restore previous owner
            continue
        visited += 1
        if visited % 200_000 == 0:
            print(f"    DFS progress: {visited} nodes")
        entered_here = False
        if n in branch_set:
            # Push a LEAVE marker that restores the *previous* owner.
            stack.append((LEAVE, n, cur_owner))
            cur_owner = n
            entered_here = True
        if n in leaf_set and cur_owner is not None:
            owner[n] = cur_owner
            leaves_by_branch[cur_owner].append(n)
        kids = children.get(n)
        if kids is not None:
            # push right first so left is processed first
            stack.append((ENTER, kids[1], None))
            stack.append((ENTER, kids[0], None))
        # if not entered_here, owner stays the same on return
    return owner, leaves_by_branch
def parse_bvh(path: Path):
    """Return dict node_id -> (left_child, right_child) or None for leaves."""
    children = {}
    with path.open() as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) < 9:
                continue
            node_id    = int(parts[0])
            left_first = int(parts[7])
            tri_count  = int(parts[8])
            children[node_id] = None if tri_count != 0 else (left_first,
                                                              left_first + 1)
    return children


def parse_leaf_roots(path: Path):
    leaves = []
    with path.open() as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            leaves.append(int(line.split()[0]))
    return leaves


# --------------------------------------------------------------------------
# Tree utilities
# --------------------------------------------------------------------------

def build_parent_map(children):
    """node_id -> parent_id (root has no entry)."""
    parent = {}
    for n, kids in children.items():
        if kids is None:
            continue
        for c in kids:
            parent[c] = n
    return parent


def left_to_right_branch_order(branch_roots, children, tree_root=TREE_ROOT):
    """DFS from tree_root, descending left child first, stopping at any
    node in branch_roots. Returns branch roots in DFS-encounter order."""
    root_set = set(branch_roots)
    order = []
    stack = [tree_root]
    while stack:
        n = stack.pop()
        if n in root_set:
            order.append(n)
            continue
        kids = children.get(n)
        if kids is None:
            continue
        # push right first so left is processed first
        stack.append(kids[1])
        stack.append(kids[0])
    return order


def assign_owner(leaf_id, parent, branch_set):
    """Walk up from leaf until we hit a branch root. Returns branch id."""
    n = leaf_id
    while n not in branch_set:
        if n not in parent:
            return None  # walked off the top without finding an owner
        n = parent[n]
    return n


def collect_subtree_leaves_in_dfs(branch_root, children, leaf_set):
    """DFS from branch_root descending left first; emit nodes that are in
    leaf_set in the order encountered. Does NOT cross other branch roots
    (caller responsibility — but since branches form an antichain w.r.t.
    each other, and leaves live below them, walking the whole subtree is
    safe)."""
    out = []
    stack = [branch_root]
    while stack:
        n = stack.pop()
        if n in leaf_set:
            out.append(n)
            # don't descend further past a leaf core root either
            continue
        kids = children.get(n)
        if kids is None:
            continue
        stack.append(kids[1])
        stack.append(kids[0])
    return out

def fill_empty_with_capacity(super_occupant, width, height):
    """
    Fill empty cells by copying nearest node, with constraint:
    each node can appear at most twice total.
    """

    # Track node usage
    node_usage = {}
    node_positions = {}

    for (x, y), (nid, kind, gi) in super_occupant.items():
        node_usage[nid] = node_usage.get(nid, 0) + 1
        node_positions.setdefault(nid, []).append((x, y))

    # Build list of empty cells
    empty_cells = [
        (x, y)
        for y in range(height)
        for x in range(width)
        if (x, y) not in super_occupant
    ]

    # Flatten all placed nodes into a list of (nid, position)
    placed = []
    for nid, positions in node_positions.items():
        for pos in positions:
            placed.append((nid, pos))

    # Precompute candidates: for each empty cell, sort nodes by distance
    assignments = []

    for ex, ey in empty_cells:
        candidates = []
        for nid, (px, py) in placed:
            dist = abs(px - ex) + abs(py - ey)
            candidates.append((dist, nid))
        candidates.sort()
        assignments.append((ex, ey, candidates))

    # Sort empties by best available distance (greedy best-first)
    assignments.sort(key=lambda x: x[2][0][0] if x[2] else float("inf"))

    # Assign
    for ex, ey, candidates in assignments:
        for _, nid in candidates:
            if node_usage.get(nid, 0) < 2:
                # Find metadata (kind, group) from any existing instance
                for (px, py), (nid2, kind, gi) in super_occupant.items():
                    if nid2 == nid:
                        # mark as duplicate so scoring/rendering can tell
                        super_occupant[(ex, ey)] = (nid, kind + "_dup", -2)
                        break
                node_usage[nid] += 1
                break
        # If no node available (all at capacity), leave empty
# --------------------------------------------------------------------------
# Group splitting (contiguous, 6 groups of 21 + 2 groups of 20 for 166)
# --------------------------------------------------------------------------

def split_contiguous(items, k):
    """Split list into k contiguous groups whose sizes differ by at most 1.
    Larger groups come first."""
    n = len(items)
    base, rem = divmod(n, k)
    sizes = [base + 1] * rem + [base] * (k - rem)
    groups = []
    i = 0
    for s in sizes:
        groups.append(items[i:i + s])
        i += s
    return groups, sizes


# --------------------------------------------------------------------------
# Eviction when a tile is over-capacity
# --------------------------------------------------------------------------

def evict_to_capacity(group_branches, leaves_by_branch, capacity):
    """Return (kept_leaves_by_branch, evicted_leaves).

    Strategy: round-robin remove the *last* leaf from whichever branch
    currently owns the most leaves. This spreads eviction across
    overweight branches and tends to remove leaves at the tail end of
    each branch's DFS list (still arbitrary, but deterministic)."""
    kept = {b: list(leaves_by_branch[b]) for b in group_branches}
    total = sum(len(v) for v in kept.values()) + len(group_branches)
    evicted = []
    if total <= capacity:
        return kept, evicted

    # Min-heap by negative size for "largest first" peek.
    import heapq
    heap = [(-len(kept[b]), b) for b in group_branches if kept[b]]
    heapq.heapify(heap)
    while total > capacity and heap:
        neg, b = heapq.heappop(heap)
        if not kept[b]:
            continue
        evicted.append(kept[b].pop())  # drop tail-most leaf for that branch
        total -= 1
        if kept[b]:
            heapq.heappush(heap, (-len(kept[b]), b))
    return kept, evicted


# --------------------------------------------------------------------------
# Placement: spectral init + simulated annealing
# --------------------------------------------------------------------------

def spectral_layout(node_ids, edges_by_node):
    """Compute a 2D spectral embedding of the graph using power iteration
    on the normalized Laplacian (deflate the trivial eigenvector). Returns
    {node_id: (x, y)} as floats; absolute scale doesn't matter."""
    n = len(node_ids)
    idx = {nid: i for i, nid in enumerate(node_ids)}
    deg = [0] * n
    nbrs = [[] for _ in range(n)]
    for u_id, neigh_list in edges_by_node.items():
        if u_id not in idx:
            continue
        u = idx[u_id]
        for v_id in neigh_list:
            if v_id in idx:
                nbrs[u].append(idx[v_id])
        deg[u] = len(nbrs[u])

    if n == 0:
        return {}

    # Build symmetric normalized adjacency on the fly via mat-vec.
    # We want second & third eigenvectors of L_sym = I - D^{-1/2} A D^{-1/2},
    # which are the smallest non-trivial eigenvectors. Equivalent to the
    # largest eigenvectors of D^{-1/2} A D^{-1/2} after deflating the
    # trivial one.
    inv_sqrt_deg = [1.0 / math.sqrt(d) if d > 0 else 0.0 for d in deg]

    def matvec(x):
        # y = D^{-1/2} A D^{-1/2} x
        y = [0.0] * n
        for u in range(n):
            if not nbrs[u]:
                continue
            acc = 0.0
            for v in nbrs[u]:
                acc += inv_sqrt_deg[v] * x[v]
            y[u] = inv_sqrt_deg[u] * acc
        return y

    # Trivial eigenvector of L_sym (eigenvalue 0): proportional to D^{1/2}.
    sqrt_deg = [math.sqrt(d) for d in deg]
    norm0 = math.sqrt(sum(s * s for s in sqrt_deg)) or 1.0
    e0 = [s / norm0 for s in sqrt_deg]

    rng = random.Random(SEED)

    def deflate(v, against):
        for w in against:
            dot = sum(vi * wi for vi, wi in zip(v, w))
            v = [vi - dot * wi for vi, wi in zip(v, w)]
        # normalize
        norm = math.sqrt(sum(vi * vi for vi in v)) or 1.0
        return [vi / norm for vi in v]

    def power_iter(against, iters=120):
        v = [rng.uniform(-1.0, 1.0) for _ in range(n)]
        v = deflate(v, against)
        for _ in range(iters):
            v = matvec(v)
            v = deflate(v, against)
        return v

    e1 = power_iter([e0])
    e2 = power_iter([e0, e1])

    coords = {}
    for i, nid in enumerate(node_ids):
        coords[nid] = (e1[i], e2[i])
    return coords


def snap_to_grid(coords, side):
    """Take continuous coords and place each node on a unique grid cell in
    a side x side grid (0..side-1). Strategy: rank by x, then by y, then
    serpentine fill columns to keep neighbors close.
    Returns {node_id: (gx, gy)}."""
    nodes = list(coords.keys())
    if not nodes:
        return {}

    # Sort by x first.
    nodes.sort(key=lambda n: coords[n][0])
    # Bin into `side` columns by rank.
    placement = {}
    per_col = math.ceil(len(nodes) / side)
    cols = [nodes[i * per_col:(i + 1) * per_col] for i in range(side)]
    # Within each column, sort by y; alternate column direction.
    for cx, col in enumerate(cols):
        col.sort(key=lambda n: coords[n][1])
        if cx % 2 == 1:
            col = list(reversed(col))
        for cy, nid in enumerate(col):
            if cy >= side:
                break
            placement[nid] = (cx, cy)
    return placement


def manhattan(a, b):
    return abs(a[0] - b[0]) + abs(a[1] - b[1])


def placement_cost(placement, edges):
    """edges = list of (u, v) with u < v as ids; weight = 1 each."""
    cost = 0
    for u, v in edges:
        if u in placement and v in placement:
            cost += manhattan(placement[u], placement[v])
    return cost


def simulated_anneal(placement, edges_by_node, side,
                     iters=SA_ITERS_PER_TILE, t0=SA_T0, t1=SA_T1, seed=0):
    """Random pair-swap SA. Cells with no node are represented as None
    placeholders so we can swap a node with an empty cell.
    Returns (final_placement, final_cost)."""
    rng = random.Random(seed)
    cells = [(x, y) for y in range(side) for x in range(side)]
    occupant = {c: None for c in cells}
    for nid, c in placement.items():
        occupant[c] = nid
    pos = dict(placement)  # node_id -> cell

    # Precompute neighbor-list with weights (here all weight 1).
    nbr = {nid: list(neighs) for nid, neighs in edges_by_node.items()
           if nid in pos}

    def node_cost(nid):
        if nid is None:
            return 0
        c = pos[nid]
        s = 0
        for m in nbr.get(nid, ()):
            if m in pos:
                s += manhattan(c, pos[m])
        return s

    # Total cost (counts each edge twice via endpoint sums; we just track
    # delta consistently so absolute factor doesn't matter for SA).
    def delta_swap(a, b):
        """If we swap occupants of cells a and b, what is the change in the
        sum-over-endpoints cost? Since each edge appears in both
        endpoints' lists, halve at the end if you want the real edge sum;
        for SA acceptance only delta sign+magnitude matter."""
        na = occupant[a]
        nb = occupant[b]
        if na is None and nb is None:
            return 0, 0, 0
        before = 0
        after  = 0
        # Cost contribution of na at position a, plus nb at position b.
        if na is not None:
            for m in nbr.get(na, ()):
                if m in pos and m != nb:
                    before += manhattan(a, pos[m])
                    after  += manhattan(b, pos[m])
                elif m == nb:
                    # Edge na-nb: before uses (a,b), after uses (b,a) -- same
                    before += manhattan(a, b)
                    after  += manhattan(b, a)
        if nb is not None:
            for m in nbr.get(nb, ()):
                if m in pos and m != na:
                    before += manhattan(b, pos[m])
                    after  += manhattan(a, pos[m])
                # nb-na edge already counted above
        return after - before, before, after

    n_cells = len(cells)
    if n_cells < 2:
        return pos, placement_cost(pos, _edges_from_nbr(nbr))

    # Initial cost (real edge cost, not endpoint sum).
    edge_list = _edges_from_nbr(nbr)
    cur_cost = placement_cost(pos, edge_list)

    log_t0, log_t1 = math.log(t0), math.log(t1)
    for it in range(iters):
        frac = it / max(1, iters - 1)
        T = math.exp(log_t0 + (log_t1 - log_t0) * frac)
        a = cells[rng.randrange(n_cells)]
        b = cells[rng.randrange(n_cells)]
        if a == b:
            continue
        d_endpoint, _, _ = delta_swap(a, b)
        # Endpoint-sum delta = 2 * edge-sum delta (each affected edge
        # counted from both endpoints when both endpoints are inside the
        # affected set; when only one endpoint is in {a,b} the factor is 1.
        # The signs are still correct, just the magnitude is inflated for
        # internal edges. For SA acceptance this is fine.)
        if d_endpoint <= 0 or rng.random() < math.exp(-d_endpoint / T):
            na = occupant[a]
            nb = occupant[b]
            occupant[a], occupant[b] = nb, na
            if na is not None:
                pos[na] = b
            if nb is not None:
                pos[nb] = a
            cur_cost += d_endpoint  # approximation; recomputed below

    # Recompute exact final cost.
    cur_cost = placement_cost(pos, edge_list)
    return pos, cur_cost


def _edges_from_nbr(nbr):
    """Convert adjacency dict to undirected edge list (u<v)."""
    seen = set()
    out = []
    for u, neigh in nbr.items():
        for v in neigh:
            if u < v:
                key = (u, v)
            else:
                key = (v, u)
            if key in seen:
                continue
            seen.add(key)
            out.append(key)
    return out


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

def main():
    if len(sys.argv) < 5:
        print("usage: place_cores.py bvh_nodes.txt leaf_core_roots.txt "
              "branch_core_roots.txt out_dir/", file=sys.stderr)
        sys.exit(1)
    bvh_path    = Path(sys.argv[1])
    leaf_path   = Path(sys.argv[2])
    branch_path = Path(sys.argv[3])
    out_dir     = Path(sys.argv[4])
    out_dir.mkdir(parents=True, exist_ok=True)

    children      = parse_bvh(bvh_path)
    parent        = build_parent_map(children)
    leaves        = parse_leaf_roots(leaf_path)
    branch_roots  = parse_leaf_roots(branch_path)   # same format
    leaf_set      = set(leaves)
    branch_set    = set(branch_roots)

    print(f"Loaded {len(children)} BVH nodes, {len(leaves)} leaf core roots, "
          f"{len(branch_roots)} branch core roots.")
    # 1. Branch-root DFS order.
    branch_order = left_to_right_branch_order(branch_roots, children)
    if len(branch_order) != len(branch_roots):
        print(f"WARN: DFS reached {len(branch_order)} of "
              f"{len(branch_roots)} branch roots")

    # 2. Owner assignment.
    owner = {}
    orphans = []
    print("Single-pass DFS to compute owners and leaves-by-branch...")
    owner, leaves_by_branch = owners_and_leaves_in_one_pass(
        children, branch_set, leaf_set
    )
    orphans = [lf for lf in leaves if lf not in owner]
    if orphans:
        print(f"WARN: {len(orphans)} leaf cores have no branch ancestor "
              f"(first few: {orphans[:5]})")
    placed = sum(len(v) for v in leaves_by_branch.values())
    print(f"  owners assigned: {placed}/{len(leaves)} leaves")
    counts = sorted((len(v) for v in leaves_by_branch.values()), reverse=True)
    print(f"  leaves per branch: max={counts[0]}, "
          f"median={counts[len(counts)//2]}, min={counts[-1]}, "
          f"top5={counts[:5]}")
    # 4. Leaf left-to-right global DFS order (for the leaf<->leaf chain).
    global_leaf_order = []
    for b in branch_order:
        global_leaf_order.extend(leaves_by_branch[b])
    leaf_chain_index = {lf: i for i, lf in enumerate(global_leaf_order)}

    # 5. Group the branch roots into K_GROUPS contiguous chunks.
    groups, sizes = split_contiguous(branch_order, K_GROUPS)
    print(f"Group sizes (branch counts): {sizes}")

    # 6. Build node sets per group, evict if over capacity.
    set_aside = []
    group_data = []  # list of dicts
    for gi, gbranches in enumerate(groups):
        gleaves_by_b = {b: leaves_by_branch[b] for b in gbranches}
        kept, evicted = evict_to_capacity(gbranches, gleaves_by_b, TILE_CAP)
        n_kept_leaves = sum(len(v) for v in kept.values())
        total_in_tile = n_kept_leaves + len(gbranches)
        print(f"  group {gi}: {len(gbranches)} branches + "
              f"{n_kept_leaves} leaves = {total_in_tile} nodes "
              f"(evicted {len(evicted)})")
        set_aside.extend(evicted)
        group_data.append({
            "branches": gbranches,
            "leaves_by_branch": kept,
            "all_leaves": [l for b in gbranches for l in kept[b]],
        })

    # 7. Place each group on its 32x32 tile.
    tile_placements = []  # list of {node_id: (x,y)} per group
    for gi, gd in enumerate(group_data):
        node_ids = list(gd["branches"]) + list(gd["all_leaves"])
        # Build adjacency
        adj = {nid: [] for nid in node_ids}
        leaf_set_local = set(gd["all_leaves"])
        # leaf-leaf chain: connect leaves consecutive in the global DFS
        # order, restricted to those present in this group.
        chain_local = [lf for lf in global_leaf_order if lf in leaf_set_local]
        for i in range(len(chain_local) - 1):
            a, b = chain_local[i], chain_local[i + 1]
            adj[a].append(b)
            adj[b].append(a)
        # branch-leaf edges
        for b, ls in gd["leaves_by_branch"].items():
            for lf in ls:
                adj[b].append(lf)
                adj[lf].append(b)

        coords = spectral_layout(node_ids, adj)
        place  = snap_to_grid(coords, TILE)
        place, cost = simulated_anneal(place, adj, TILE,
                                       iters=SA_ITERS_PER_TILE,
                                       seed=SEED + gi)
        edges = _edges_from_nbr({n: adj[n] for n in adj if n in place})
        cost  = placement_cost(place, edges)
        print(f"  group {gi}: {len(node_ids)} nodes, "
              f"{len(edges)} edges, final cost = {cost}")
        tile_placements.append(place)

# 8. Stitch tiles into 128 x 64 super-grid (4 cols x 2 rows), with
    #    the bottom row of tiles reversed so the global DFS order forms
    #    a snake (groups 0..7 are spatially contiguous end-to-end).
    super_occupant = {}  # (X, Y) -> (node_id, kind, group)
    for gi, place in enumerate(tile_placements):
        tile_row = gi // TILES_PER_ROW
        if tile_row == 0:
            tile_col = gi % TILES_PER_ROW                          # 0,1,2,3
        else:
            tile_col = (TILES_PER_ROW - 1) - (gi % TILES_PER_ROW)  # 3,2,1,0
        ox = tile_col * TILE
        oy = tile_row * TILE
        gd = group_data[gi]
        branches_set = set(gd["branches"])
        for nid, (lx, ly) in place.items():
            if tile_row == 1:
                lx = (TILE - 1) - lx        # mirror within tile too
            kind = "branch" if nid in branches_set else "leaf"
            super_occupant[(ox + lx, oy + ly)] = (nid, kind, gi)

    # 9. Pack set-aside leaves into remaining empty cells.
    empty_cells = [(x, y) for y in range(SUPER_H) for x in range(SUPER_W)
                   if (x, y) not in super_occupant]
    print(f"Set-aside leaves: {len(set_aside)}; "
          f"empty cells available: {len(empty_cells)}")
    for nid in set_aside:
        if not empty_cells:
            print(f"WARN: ran out of empty cells, "
                  f"{len(set_aside)} leaves still unplaced")
            break
        x, y = empty_cells.pop(0)
        super_occupant[(x, y)] = (nid, "leaf_setaside", -1)

    fill_empty_with_capacity(super_occupant, SUPER_W, SUPER_H)


    # for gi, place in enumerate(tile_placements):
    #     tile_row = gi // TILES_PER_ROW
    #     if tile_row == 0:
    #         tile_col = gi % TILES_PER_ROW              # 0,1,2,3
    #     else:
    #         tile_col = (TILES_PER_ROW - 1) - (gi % TILES_PER_ROW)  # 3,2,1,0
    #     ox = tile_col * TILE
    #     oy = tile_row * TILE
    #     gd = group_data[gi]
    #     branches_set = set(gd["branches"])
    #     for nid, (lx, ly) in place.items():
    #         if tile_row == 1:
    #             lx = (TILE - 1) - lx        # mirror within tile too
    #         super_occupant[(ox + lx, oy + ly)] = (nid, kind, gi)
    
    
    
    # 10. Outputs.
    csv_path = out_dir / "placement.csv"
    with csv_path.open("w") as f:
        f.write("x,y,node_id,kind,group\n")
        for y in range(SUPER_H):
            for x in range(SUPER_W):
                if (x, y) in super_occupant:
                    nid, kind, gi = super_occupant[(x, y)]
                    f.write(f"{x},{y},{nid},{kind},{gi}\n")
                else:
                    f.write(f"{x},{y},,empty,-1\n")
    print(f"Wrote {csv_path}")

    sum_path = out_dir / "summary.txt"
    with sum_path.open("w") as f:
        f.write(f"branches: {len(branch_roots)}\n")
        f.write(f"leaves:   {len(leaves)}\n")
        f.write(f"groups:   {K_GROUPS}\n")
        f.write(f"super:    {SUPER_W} x {SUPER_H}\n")
        f.write(f"set_aside_leaves: {len(set_aside)}\n\n")
        for gi, gd in enumerate(group_data):
            f.write(f"group {gi}: {len(gd['branches'])} branches, "
                    f"{len(gd['all_leaves'])} leaves\n")
            f.write(f"  branch ids: {gd['branches']}\n")
    print(f"Wrote {sum_path}")


if __name__ == "__main__":
    main()