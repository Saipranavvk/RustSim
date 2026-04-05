#[derive(Debug, Copy, Clone, PartialEq)]
pub struct Point {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

#[derive(Hash, Eq, PartialEq, Copy, Clone, Debug)]
struct QPoint {
    x: i64,
    y: i64,
    z: i64,
}

fn snap(point: Point) -> QPoint {
    QPoint {
        x: (point.x * 10000.0) as i64,
        y: (point.y * 10000.0) as i64,
        z: (point.z * 10000.0) as i64,
    }
}

impl Point {
    pub fn new(x: f32, y: f32, z: f32) -> Self {
        Self { x, y, z }
    }
}

#[derive(Debug, Copy, Clone, PartialEq)]
pub struct Node {
    index: usize,
    min: Point,
    max: Point,
    left_child: usize,
    is_leaf: bool,
    right_child: usize,
    tri_count: usize,
    first_tri: usize,
}

#[derive(Debug, Copy, Clone, PartialEq)]
pub struct Indices {
    pub node_index: usize,
    pub first_triangle_index: usize,
    pub num_triangles: usize,
}

#[derive(Debug, Copy, Clone)]
pub struct Triangle {
    pub index: usize,
    pub v0: Point,
    pub v1: Point,
    pub v2: Point,
}

use std::collections::HashSet;
use std::fs::File;
use std::io::{BufRead, BufReader, Write};
use hashbrown::HashMap;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const INDEX_SIZE:            usize = 2;
const POINT_SIZE:            usize = 12;
const NODE_SIZE:             usize = 48;
const MATERIAL_POINTER_SIZE: usize = 4;
const MAX_ALLOC:             usize = 32 * 1024;

/// Phase 1: leaf cores use 65% of SRAM for owned geometry.
const LEAF_OWNED_PCT: usize = 85;
const LEAF_OWNED_BUDGET: usize = MAX_ALLOC * LEAF_OWNED_PCT / 100;

/// Phase 2: branch treelets (above leaf cores) use the remaining 35%.
const LEAF_OVERHEAD_BUDGET: usize = MAX_ALLOC - LEAF_OWNED_BUDGET;

/// Phase 3: spine must fit in 65% of a core's SRAM.
const SPINE_BUDGET: usize = MAX_ALLOC * 65 / 100;

// ---------------------------------------------------------------------------
// File readers (unchanged)
// ---------------------------------------------------------------------------

fn read_nodes(path: &str) -> Vec<Node> {
    let reader = BufReader::new(File::open(path).expect("failed to open node file"));
    let mut nodes = Vec::new();

    for line in reader.lines() {
        let line = line.expect("failed to read line");
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') { continue; }

        let parts: Vec<&str> = line.split_whitespace().collect();
        assert!(
            parts.len() == 8 || parts.len() == 9,
            "expected 8 or 9 fields, got {}: {}", parts.len(), line
        );

        let offset = if parts.len() == 9 { 1 } else { 0 };
        let index: usize = if offset == 1 {
            parts[0].parse().unwrap()
        } else {
            nodes.len()
        };

        let min = Point::new(
            parts[offset + 0].parse().unwrap(),
            parts[offset + 1].parse().unwrap(),
            parts[offset + 2].parse().unwrap(),
        );
        let max = Point::new(
            parts[offset + 3].parse().unwrap(),
            parts[offset + 4].parse().unwrap(),
            parts[offset + 5].parse().unwrap(),
        );

        let left_first: usize = parts[offset + 6].parse().unwrap();
        let tri_count:  usize = parts[offset + 7].parse().unwrap();

        if index != 0 && left_first == 0 && tri_count == 0 {
            nodes.push(Node {
                index, min, max, is_leaf: false,
                left_child: 0, right_child: 0,
                tri_count: 0, first_tri: 0,
            });
            continue;
        }

        let (left_child, right_child) = if tri_count == 0 {
            (left_first, left_first + 1)
        } else {
            (0, 0)
        };

        nodes.push(Node {
            index, min, max,
            is_leaf: tri_count != 0,
            left_child, right_child,
            tri_count, first_tri: 0,
        });
    }
    nodes
}

fn read_indices(path: &str) -> Vec<Indices> {
    let reader = BufReader::new(File::open(path).expect("failed to open indices file"));
    let mut indices = Vec::new();

    for line in reader.lines() {
        let line = line.expect("failed to read line");
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') { continue; }

        let parts: Vec<&str> = line.split_whitespace().collect();
        assert!(parts.len() == 3, "expected 3 fields, got {}: {}", parts.len(), line);

        indices.push(Indices {
            node_index:           parts[0].parse().unwrap(),
            first_triangle_index: parts[1].parse().unwrap(),
            num_triangles:        parts[2].parse().unwrap(),
        });
    }
    indices
}

fn read_triangles(path: &str) -> Vec<Triangle> {
    let reader = BufReader::new(File::open(path).expect("failed to open triangle file"));
    let mut tris = Vec::new();

    for line in reader.lines() {
        let line = line.expect("failed to read line");
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') { continue; }

        let parts: Vec<&str> = line.split_whitespace().collect();
        assert!(
            parts.len() == 9 || parts.len() == 10,
            "expected 9 or 10 fields, got {}: {}", parts.len(), line
        );

        let offset = if parts.len() == 10 { 1 } else { 0 };
        let index = if offset == 1 { parts[0].parse().unwrap() } else { tris.len() };

        let v0 = Point::new(
            parts[offset + 0].parse().unwrap(),
            parts[offset + 1].parse().unwrap(),
            parts[offset + 2].parse().unwrap(),
        );
        let v1 = Point::new(
            parts[offset + 3].parse().unwrap(),
            parts[offset + 4].parse().unwrap(),
            parts[offset + 5].parse().unwrap(),
        );
        let v2 = Point::new(
            parts[offset + 6].parse().unwrap(),
            parts[offset + 7].parse().unwrap(),
            parts[offset + 8].parse().unwrap(),
        );

        tris.push(Triangle { index, v0, v1, v2 });
    }
    tris
}

// ---------------------------------------------------------------------------
// Parent map
// ---------------------------------------------------------------------------

fn build_parent_map(nodes: &[Node]) -> Vec<Option<usize>> {
    let mut parents = vec![None; nodes.len()];
    for node in nodes {
        if !node.is_leaf && !(node.left_child == 0 && node.right_child == 0) {
            if node.left_child < nodes.len() {
                parents[node.left_child] = Some(node.index);
            }
            if node.right_child < nodes.len() {
                parents[node.right_child] = Some(node.index);
            }
        }
    }
    parents
}

// ---------------------------------------------------------------------------
// Size computation helpers
// ---------------------------------------------------------------------------

/// Compute the SRAM cost of a leaf subtree rooted at `index`.
/// Counts: NODE_SIZE per internal/leaf node, plus geometry at leaves
/// (deduplicated vertex points + index/material overhead per triangle).
/// Stops (inclusive) at nodes in `boundary` — they count as NODE_SIZE stubs.
fn subtree_leaf_size(
    index: usize,
    nodes: &[Node],
    triangles: &[Triangle],
    boundary: &HashSet<usize>,
    points: &mut HashMap<QPoint, ()>,
) -> usize {
    // If this node is a boundary stub (and not the root of the query),
    // we handle it at the call site. This function always includes `index`.
    let node = &nodes[index];

    if node.is_leaf {
        let mut size = NODE_SIZE;
        for i in node.first_tri .. node.first_tri + node.tri_count {
            size += INDEX_SIZE * 3 + MATERIAL_POINTER_SIZE;
            points.insert(snap(triangles[i].v0), ());
            points.insert(snap(triangles[i].v1), ());
            points.insert(snap(triangles[i].v2), ());
        }
        return size;
    }

    let mut size = NODE_SIZE;

    // Left child
    if boundary.contains(&node.left_child) {
        size += NODE_SIZE; // stub
    } else {
        size += subtree_leaf_size(node.left_child, nodes, triangles, boundary, points);
    }

    // Right child
    if boundary.contains(&node.right_child) {
        size += NODE_SIZE; // stub
    } else {
        size += subtree_leaf_size(node.right_child, nodes, triangles, boundary, points);
    }

    size
}

/// Full cost of a leaf treelet rooted at `index`, bounded by `boundary`.
/// Returns total bytes (nodes + geometry with deduplicated vertices).
fn leaf_treelet_cost(
    index: usize,
    nodes: &[Node],
    triangles: &[Triangle],
    boundary: &HashSet<usize>,
) -> usize {
    let mut points: HashMap<QPoint, ()> = HashMap::new();
    let node_bytes = subtree_leaf_size(index, nodes, triangles, boundary, &mut points);
    node_bytes + points.len() * POINT_SIZE
}

/// Size of a branch treelet: traverse from `index` down, stopping
/// (inclusive as NODE_SIZE stubs) at nodes in `leaf_roots`.
fn branch_treelet_size(
    index: usize,
    nodes: &[Node],
    leaf_roots: &HashSet<usize>,
) -> usize {
    if leaf_roots.contains(&index) {
        return NODE_SIZE; // stub for leaf core root
    }
    let node = &nodes[index];
    if node.is_leaf {
        // Shouldn't normally happen — a BVH leaf not claimed by any leaf core
        return NODE_SIZE;
    }
    NODE_SIZE
        + branch_treelet_size(node.left_child, nodes, leaf_roots)
        + branch_treelet_size(node.right_child, nodes, leaf_roots)
}

/// Size of the spine: traverse from root down, stopping (inclusive as
/// NODE_SIZE stubs) at branch core roots.
fn spine_size(
    index: usize,
    nodes: &[Node],
    branch_roots: &HashSet<usize>,
) -> usize {
    if branch_roots.contains(&index) {
        return NODE_SIZE; // stub
    }
    let node = &nodes[index];
    if node.is_leaf {
        return NODE_SIZE;
    }
    NODE_SIZE
        + spine_size(node.left_child, nodes, branch_roots)
        + spine_size(node.right_child, nodes, branch_roots)
}

// ---------------------------------------------------------------------------
// Phase 1: Bottom-up greedy leaf treelet growth
// ---------------------------------------------------------------------------

/// Collect all BVH leaf node indices.
fn collect_bvh_leaves(nodes: &[Node]) -> Vec<usize> {
    nodes.iter()
        .filter(|n| n.is_leaf)
        .map(|n| n.index)
        .collect()
}

/// Phase 1: Starting from each unclaimed BVH leaf, greedily grow upward.
///
/// At each step we try to move from the current root to its parent,
/// which would absorb the parent node and the sibling's entire subtree.
/// We re-evaluate the full cost of the new subtree (with deduplication).
/// If it fits in LEAF_OWNED_BUDGET, we absorb it: mark all newly-claimed
/// BVH leaves as covered and continue climbing.
///
/// Returns the set of leaf core roots.
fn phase1_leaf_partition(
    nodes: &[Node],
    triangles: &[Triangle],
    parents: &[Option<usize>],
) -> Vec<usize> {
    let mut unclaimed: HashSet<usize> = collect_bvh_leaves(nodes)
        .into_iter()
        .collect();

    let mut leaf_core_roots: Vec<usize> = Vec::new();

    // Process leaves smallest-first for better packing.
    // We'll iterate until unclaimed is empty.
    while !unclaimed.is_empty() {
        // Pick an arbitrary unclaimed BVH leaf to seed a new treelet.
        let seed = *unclaimed.iter().next().unwrap();
        let mut current_root = seed;

        // The set of BVH leaves currently inside this treelet.
        let mut owned_leaves: HashSet<usize> = HashSet::new();
        owned_leaves.insert(seed);
        unclaimed.remove(&seed);

        // Try to grow upward.
        loop {
            let parent = match parents[current_root] {
                Some(p) => p,
                None => break, // reached BVH root
            };

            // The sibling is the other child of parent.
            let parent_node = &nodes[parent];
            let sibling = if parent_node.left_child == current_root {
                parent_node.right_child
            } else {
                parent_node.left_child
            };

            // Compute cost if we expand to `parent` as new root.
            // The boundary is empty — we own everything below `parent`.
            let cost = leaf_treelet_cost(parent, nodes, triangles, &HashSet::new());

            if cost > LEAF_OWNED_BUDGET {
                break; // can't grow further
            }

            // Absorb: collect all BVH leaves under sibling and mark them claimed.
            let sibling_leaves = collect_leaves_under(sibling, nodes);
            for &sl in &sibling_leaves {
                unclaimed.remove(&sl);
                owned_leaves.insert(sl);
            }

            current_root = parent;
        }

        leaf_core_roots.push(current_root);
    }

    leaf_core_roots
}

/// Collect all BVH leaf indices under a given subtree root.
fn collect_leaves_under(index: usize, nodes: &[Node]) -> Vec<usize> {
    let node = &nodes[index];
    if node.is_leaf {
        return vec![index];
    }
    let mut result = collect_leaves_under(node.left_child, nodes);
    result.extend(collect_leaves_under(node.right_child, nodes));
    result
}

// ---------------------------------------------------------------------------
// Phase 2: Branch treelet growth from leaf core roots
// ---------------------------------------------------------------------------

/// Phase 2: Starting from each unclaimed leaf core root, greedily grow
/// upward, building branch treelets.
///
/// A branch treelet's cost = all interior nodes from its root down to
/// (inclusive) leaf core roots, which appear as NODE_SIZE stubs.
///
/// We use the remaining 35% of SRAM (LEAF_OVERHEAD_BUDGET).
///
/// At each step, move from current root to its parent. Re-evaluate the
/// branch treelet cost from the parent down to all leaf core root stubs.
/// If it fits, absorb (mark all newly-claimed leaf core roots). If not,
/// emit the previous root as a branch core root.
///
/// Returns the set of branch core roots.
fn phase2_branch_partition(
    nodes: &[Node],
    leaf_core_roots: &HashSet<usize>,
    parents: &[Option<usize>],
) -> Vec<usize> {
    let mut unclaimed: HashSet<usize> = leaf_core_roots.clone();
    let mut branch_core_roots: Vec<usize> = Vec::new();

    while !unclaimed.is_empty() {
        let seed = *unclaimed.iter().next().unwrap();
        let mut current_root = seed;

        // Leaf core roots owned by this branch treelet so far.
        let mut owned_lcrs: HashSet<usize> = HashSet::new();
        owned_lcrs.insert(seed);
        unclaimed.remove(&seed);

        // The initial cost is just one stub: NODE_SIZE.
        // But we need to start climbing to actually form a branch treelet.
        // A single leaf core root by itself isn't a branch treelet —
        // we need to go up at least to the parent to get interior nodes.

        loop {
            let parent = match parents[current_root] {
                Some(p) => p,
                None => break, // reached BVH root
            };

            // Cost of branch treelet rooted at `parent`, with all leaf
            // core roots as stubs.
            let cost = branch_treelet_size(parent, nodes, leaf_core_roots);

            if cost > LEAF_OVERHEAD_BUDGET {
                break; // can't grow further
            }

            // Absorb: collect all leaf core roots under sibling.
            let parent_node = &nodes[parent];
            let sibling = if parent_node.left_child == current_root {
                parent_node.right_child
            } else {
                parent_node.left_child
            };

            let sibling_lcrs = collect_lcrs_under(sibling, nodes, leaf_core_roots);
            for &sl in &sibling_lcrs {
                unclaimed.remove(&sl);
                owned_lcrs.insert(sl);
            }

            current_root = parent;
        }

        branch_core_roots.push(current_root);
    }

    branch_core_roots
}

/// Collect all leaf core roots that exist under a given subtree.
fn collect_lcrs_under(
    index: usize,
    nodes: &[Node],
    leaf_core_roots: &HashSet<usize>,
) -> Vec<usize> {
    if leaf_core_roots.contains(&index) {
        return vec![index];
    }
    let node = &nodes[index];
    if node.is_leaf {
        return vec![];
    }
    let mut result = collect_lcrs_under(node.left_child, nodes, leaf_core_roots);
    result.extend(collect_lcrs_under(node.right_child, nodes, leaf_core_roots));
    result
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

fn count_subtree_nodes(index: usize, nodes: &[Node]) -> (usize, usize) {
    let node = &nodes[index];
    if node.is_leaf {
        return (node.tri_count, 1);
    }
    let (a, b) = count_subtree_nodes(node.left_child, nodes);
    let (c, d) = count_subtree_nodes(node.right_child, nodes);
    (a + c, 1 + b + d)
}

fn count_subtree_tris_bounded(
    index: usize,
    nodes: &[Node],
    boundary: &HashSet<usize>,
) -> usize {
    if boundary.contains(&index) {
        return 0; // stub — no tris
    }
    let node = &nodes[index];
    if node.is_leaf {
        return node.tri_count;
    }
    count_subtree_tris_bounded(node.left_child, nodes, boundary)
        + count_subtree_tris_bounded(node.right_child, nodes, boundary)
}

fn count_subtree_nodes_bounded(
    index: usize,
    nodes: &[Node],
    boundary: &HashSet<usize>,
) -> usize {
    if boundary.contains(&index) {
        return 1; // stub
    }
    let node = &nodes[index];
    if node.is_leaf {
        return 1;
    }
    1 + count_subtree_nodes_bounded(node.left_child, nodes, boundary)
        + count_subtree_nodes_bounded(node.right_child, nodes, boundary)
}

/// Map each leaf core root to the branch core root that owns it.
fn map_lcrs_to_branches(
    branch_roots: &[usize],
    leaf_core_roots: &HashSet<usize>,
    nodes: &[Node],
) -> HashMap<usize, usize> {
    let mut result = HashMap::new();
    for &br in branch_roots {
        assign_lcrs(br, br, nodes, leaf_core_roots, &mut result);
    }
    result
}

fn assign_lcrs(
    index: usize,
    branch_root: usize,
    nodes: &[Node],
    leaf_core_roots: &HashSet<usize>,
    result: &mut HashMap<usize, usize>,
) {
    if leaf_core_roots.contains(&index) {
        result.insert(index, branch_root);
        return;
    }
    let node = &nodes[index];
    if node.is_leaf { return; }
    assign_lcrs(node.left_child, branch_root, nodes, leaf_core_roots, result);
    assign_lcrs(node.right_child, branch_root, nodes, leaf_core_roots, result);
}

// ---------------------------------------------------------------------------
// Skew score: measures how balanced a subtree is.
//   depth_skew = max_depth - min_depth (of leaves under the root).
//   0 = perfectly balanced; higher = more skewed.
// ---------------------------------------------------------------------------

/// Returns (min_leaf_depth, max_leaf_depth) for the subtree rooted at
/// `index`, stopping at `boundary` nodes (treated as leaves at that depth).
fn subtree_depth_range(
    index: usize,
    nodes: &[Node],
    boundary: &HashSet<usize>,
    depth: usize,
) -> (usize, usize) {
    if boundary.contains(&index) {
        return (depth, depth);
    }
    let node = &nodes[index];
    if node.is_leaf {
        return (depth, depth);
    }
    let (lmin, lmax) = subtree_depth_range(node.left_child,  nodes, boundary, depth + 1);
    let (rmin, rmax) = subtree_depth_range(node.right_child, nodes, boundary, depth + 1);
    (lmin.min(rmin), lmax.max(rmax))
}

/// Skew score = max_leaf_depth - min_leaf_depth for the owned subtree.
fn skew_score(
    root: usize,
    nodes: &[Node],
    boundary: &HashSet<usize>,
) -> usize {
    let (min_d, max_d) = subtree_depth_range(root, nodes, boundary, 0);
    max_d - min_d
}

// ---------------------------------------------------------------------------
// Statistics helpers
// ---------------------------------------------------------------------------

fn stats_summary(values: &[f64]) -> (f64, f64, f64, f64, f64) {
    // Returns (min, max, mean, median, std)
    if values.is_empty() {
        return (0.0, 0.0, 0.0, 0.0, 0.0);
    }
    let mut sorted = values.to_vec();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let n = sorted.len();
    let min = sorted[0];
    let max = sorted[n - 1];
    let mean = sorted.iter().sum::<f64>() / n as f64;
    let median = if n % 2 == 0 {
        (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
    } else {
        sorted[n / 2]
    };
    let variance = sorted.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / n as f64;
    let std = variance.sqrt();
    (min, max, mean, median, std)
}

fn print_stats(label: &str, values: &[f64]) {
    let (min, max, mean, median, std) = stats_summary(values);
    println!(
        "  {}: min={:.1} max={:.1} mean={:.1} median={:.1} std={:.1}",
        label, min, max, mean, median, std
    );
}

/// Count triangles owned by a branch treelet (interior nodes between
/// branch root and leaf core root stubs — stubs contribute 0 tris).
fn branch_owned_tris(
    index: usize,
    nodes: &[Node],
    leaf_core_roots: &HashSet<usize>,
) -> usize {
    if leaf_core_roots.contains(&index) {
        return 0; // stub — leaf core owns these tris
    }
    let node = &nodes[index];
    if node.is_leaf {
        return node.tri_count;
    }
    branch_owned_tris(node.left_child, nodes, leaf_core_roots)
        + branch_owned_tris(node.right_child, nodes, leaf_core_roots)
}

/// Count nodes owned by a branch treelet (including stubs).
fn branch_owned_nodes(
    index: usize,
    nodes: &[Node],
    leaf_core_roots: &HashSet<usize>,
) -> usize {
    if leaf_core_roots.contains(&index) {
        return 1; // stub node
    }
    let node = &nodes[index];
    if node.is_leaf {
        return 1;
    }
    1 + branch_owned_nodes(node.left_child, nodes, leaf_core_roots)
        + branch_owned_nodes(node.right_child, nodes, leaf_core_roots)
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

pub fn assemble_tree(subfolder: String) {
    let bvh_leaves_path    = format!("{}\\bvh_leaves.txt",    subfolder);
    let bvh_nodes_path     = format!("{}\\bvh_nodes.txt",     subfolder);
    let bvh_triangles_path = format!("{}\\bvh_triangles.txt", subfolder);

    let triangles = read_triangles(&bvh_triangles_path);
    let indices   = read_indices(&bvh_leaves_path);
    let mut nodes = read_nodes(&bvh_nodes_path);

    let mut expanded: Vec<Indices> = vec![
        Indices { node_index: 0, first_triangle_index: 0, num_triangles: 0 };
        nodes.len().max(2_000_000)
    ];
    for idx in indices {
        expanded[idx.node_index] = idx;
    }
    for node in nodes.iter_mut() {
        node.first_tri = expanded[node.index].first_triangle_index;
    }

    println!("Loaded {} nodes, {} triangles", nodes.len(), triangles.len());
    println!(
        "Budgets: leaf_owned={}B ({:.1}KB) [{}%], leaf_overhead={}B ({:.1}KB) [{}%], spine={}B ({:.1}KB) [65%]",
        LEAF_OWNED_BUDGET, LEAF_OWNED_BUDGET as f32 / 1024.0, LEAF_OWNED_PCT,
        LEAF_OVERHEAD_BUDGET, LEAF_OVERHEAD_BUDGET as f32 / 1024.0, 100 - LEAF_OWNED_PCT,
        SPINE_BUDGET, SPINE_BUDGET as f32 / 1024.0,
    );

    // ── Build parent map ────────────────────────────────────────────────────
    println!("\nBuilding parent map...");
    let parents = build_parent_map(&nodes);

    // ── Phase 1: Leaf treelet partitioning ──────────────────────────────────
    println!("Phase 1: growing leaf treelets bottom-up (budget = {}B)...", LEAF_OWNED_BUDGET);
    let leaf_core_roots_vec = phase1_leaf_partition(&nodes, &triangles, &parents);
    let leaf_core_roots: HashSet<usize> = leaf_core_roots_vec.iter().cloned().collect();
    println!("  → {} leaf core roots", leaf_core_roots.len());

    // ── Phase 2: Branch treelet partitioning ────────────────────────────────
    println!(
        "Phase 2: growing branch treelets bottom-up from leaf core roots (budget = {}B)...",
        LEAF_OVERHEAD_BUDGET
    );
    let branch_core_roots_vec = phase2_branch_partition(&nodes, &leaf_core_roots, &parents);
    let branch_core_roots: HashSet<usize> = branch_core_roots_vec.iter().cloned().collect();
    println!("  → {} branch core roots", branch_core_roots_vec.len());

    // ── Phase 3: Spine validation ───────────────────────────────────────────
    println!("Phase 3: validating spine (budget = {}B)...", SPINE_BUDGET);
    let spine_total = spine_size(0, &nodes, &branch_core_roots);
    let spine_fits = spine_total <= SPINE_BUDGET;
    println!(
        "  Spine: {}B ({:.1}KB) / {}B budget ({:.1}%) — {}",
        spine_total, spine_total as f32 / 1024.0,
        SPINE_BUDGET, 100.0 * spine_total as f32 / SPINE_BUDGET as f32,
        if spine_fits { "OK" } else { "FAILURE — spine exceeds 65% of core SRAM" },
    );

    // ── Validate leaf treelet sizes ─────────────────────────────────────────
    println!("\nValidating leaf treelet sizes...");
    let mut leaf_violations = 0usize;
    let mut leaf_sizes: Vec<(usize, usize)> = Vec::new();
    for &lr in &leaf_core_roots_vec {
        let cost = leaf_treelet_cost(lr, &nodes, &triangles, &HashSet::new());
        leaf_sizes.push((lr, cost));
        if cost > LEAF_OWNED_BUDGET {
            leaf_violations += 1;
            println!(
                "  VIOLATION: leaf root {:>8}: {}B > {}B budget",
                lr, cost, LEAF_OWNED_BUDGET
            );
        }
    }
    if leaf_violations == 0 {
        println!("  All {} leaf treelets fit within budget.", leaf_core_roots.len());
    }

    // ── Validate branch treelet sizes ───────────────────────────────────────
    println!("\nValidating branch treelet sizes...");
    let mut branch_violations = 0usize;
    for &br in &branch_core_roots_vec {
        let cost = branch_treelet_size(br, &nodes, &leaf_core_roots);
        if cost > LEAF_OVERHEAD_BUDGET {
            branch_violations += 1;
            println!(
                "  VIOLATION: branch root {:>8}: {}B > {}B budget",
                br, cost, LEAF_OVERHEAD_BUDGET
            );
        }
    }
    if branch_violations == 0 {
        println!("  All {} branch treelets fit within budget.", branch_core_roots_vec.len());
    }

    // ── Final report ────────────────────────────────────────────────────────
    println!("\n── Final partition ──────────────────────────────────────────────");
    println!("  Leaf cores:   {}", leaf_core_roots.len());
    println!("  Branch cores: {}", branch_core_roots_vec.len());
    println!(
        "  Total cores:  {}",
        leaf_core_roots.len() + branch_core_roots_vec.len()
    );
    println!("  Spine size:   {}B ({:.1}KB) — {}",
        spine_total, spine_total as f32 / 1024.0,
        if spine_fits { "OK" } else { "FAIL" },
    );

    // ── Detailed statistics ─────────────────────────────────────────────────
    let lcr_to_branch = map_lcrs_to_branches(&branch_core_roots_vec, &leaf_core_roots, &nodes);
    let empty_boundary: HashSet<usize> = HashSet::new();

    // -- Leaf core stats --
    let leaf_tri_counts: Vec<f64> = leaf_core_roots_vec
        .iter()
        .map(|&lr| count_subtree_nodes(lr, &nodes).0 as f64)
        .collect();
    let leaf_node_counts: Vec<f64> = leaf_core_roots_vec
        .iter()
        .map(|&lr| count_subtree_nodes(lr, &nodes).1 as f64)
        .collect();
    let leaf_skew_scores: Vec<f64> = leaf_core_roots_vec
        .iter()
        .map(|&lr| skew_score(lr, &nodes, &empty_boundary) as f64)
        .collect();
    let leaf_sz_values: Vec<f64> = leaf_sizes
        .iter()
        .map(|(_, s)| *s as f64)
        .collect();

    println!("\n── Leaf core statistics ─────────────────────────────────────────");
    print_stats("Triangles per leaf core ", &leaf_tri_counts);
    print_stats("Nodes per leaf core     ", &leaf_node_counts);
    print_stats("SRAM bytes per leaf core", &leaf_sz_values);
    print_stats("Skew score (leaf cores) ", &leaf_skew_scores);

    // -- Branch core stats --
    let branch_tri_counts: Vec<f64> = branch_core_roots_vec
        .iter()
        .map(|&br| count_subtree_nodes(br, &nodes).0 as f64)
        .collect();
    let branch_node_counts: Vec<f64> = branch_core_roots_vec
        .iter()
        .map(|&br| branch_owned_nodes(br, &nodes, &leaf_core_roots) as f64)
        .collect();
    let branch_skew_scores: Vec<f64> = branch_core_roots_vec
        .iter()
        .map(|&br| skew_score(br, &nodes, &leaf_core_roots) as f64)
        .collect();
    let branch_sz_values: Vec<f64> = branch_core_roots_vec
        .iter()
        .map(|&br| branch_treelet_size(br, &nodes, &leaf_core_roots) as f64)
        .collect();

    println!("\n── Branch core statistics ───────────────────────────────────────");
    print_stats("Tris under branch core     ", &branch_tri_counts);
    print_stats("Nodes owned by branch core ", &branch_node_counts);
    print_stats("SRAM bytes per branch core ", &branch_sz_values);
    print_stats("Skew score (branch cores)  ", &branch_skew_scores);

    // -- Per-branch detail listing --
    println!("\nBranch core details:");
    let mut branch_info: Vec<(usize, usize, usize, usize)> = branch_core_roots_vec
        .iter()
        .map(|&br| {
            let lcr_count = lcr_to_branch.iter().filter(|(_, b)| **b == br).count();
            let treelet_sz = branch_treelet_size(br, &nodes, &leaf_core_roots);
            let owned_n = branch_owned_nodes(br, &nodes, &leaf_core_roots);
            (br, lcr_count, treelet_sz, owned_n)
        })
        .collect();
    branch_info.sort_by_key(|&(_, c, _, _)| std::cmp::Reverse(c));

    for (br, lcr_count, treelet_sz, owned_n) in &branch_info {
        let sk = skew_score(*br, &nodes, &leaf_core_roots);
        println!(
            "  Branch {:>8}: {:>5} leaf cores, {:>6} nodes | \
             treelet {}B ({:.1}KB) / {}B  skew={}",
            br, lcr_count, owned_n,
            treelet_sz, *treelet_sz as f32 / 1024.0, LEAF_OVERHEAD_BUDGET, sk,
        );
    }

    // ── Write output files ──────────────────────────────────────────────────
    let leaf_out_path = format!(
        "{}\\leaf_core_roots_{}pct.txt", subfolder, LEAF_OWNED_PCT
    );
    let branch_out_path = format!(
        "{}\\branch_core_roots_{}pct.txt", subfolder, LEAF_OWNED_PCT
    );

    {
        let mut f = File::create(&leaf_out_path)
            .expect("failed to create leaf core roots file");
        writeln!(f, "# Leaf core root node indices (LEAF_OWNED_PCT={}%)", LEAF_OWNED_PCT)
            .unwrap();
        writeln!(f, "# {} leaf cores total", leaf_core_roots_vec.len()).unwrap();
        let mut sorted_lcrs = leaf_core_roots_vec.clone();
        sorted_lcrs.sort();
        for lr in &sorted_lcrs {
            writeln!(f, "{}", lr).unwrap();
        }
        println!("\nWrote leaf core roots to:   {}", leaf_out_path);
    }

    {
        let mut f = File::create(&branch_out_path)
            .expect("failed to create branch core roots file");
        writeln!(f, "# Branch core root node indices (LEAF_OWNED_PCT={}%)", LEAF_OWNED_PCT)
            .unwrap();
        writeln!(f, "# {} branch cores total", branch_core_roots_vec.len()).unwrap();
        let mut sorted_brs = branch_core_roots_vec.clone();
        sorted_brs.sort();
        for br in &sorted_brs {
            writeln!(f, "{}", br).unwrap();
        }
        println!("Wrote branch core roots to: {}", branch_out_path);
    }
}
