// use std::collections::HashMap;
// use std::fs;

// #[derive(Debug, Clone)]
// struct BvhNode {
//     left_first: usize,
//     tri_count: usize,
// }

// #[derive(Debug, Clone)]
// struct BvhLeaf {
//     first_tri: usize,
//     tri_count: usize,
// }

// type Triangle = [f32; 9];


// // ------------------------------------------------------------
// // Parse BVH nodes
// // ------------------------------------------------------------
// fn parse_bvh_nodes(path: &str) -> HashMap<usize, BvhNode> {
//     let content = fs::read_to_string(path).expect("failed to read nodes file");

//     let mut map = HashMap::new();

//     for line in content.lines() {
//         if line.starts_with('#') || line.trim().is_empty() {
//             continue;
//         }

//         // Format: node_id  min.x min.y min.z  max.x max.y max.z  leftFirst  triCount
//         //         [0]      [1]   [2]   [3]    [4]   [5]   [6]    [7]        [8]
//         let parts: Vec<&str> = line.split_whitespace().collect();
//         if parts.len() < 9 {
//             continue;
//         }

//         let node_id: usize    = parts[0].parse().unwrap();
//         let left_first: usize = parts[7].parse().unwrap();
//         let tri_count: usize  = parts[8].parse().unwrap();

//         map.insert(node_id, BvhNode { left_first, tri_count });
//     }

//     map
// }


// // ------------------------------------------------------------
// // FUNCTION 1 (memory-efficient):
// // Recursively walk the subtree rooted at `node_id` and write
// // triangles directly into `out`, with NO intermediate storage.
// //
// // Old approach allocated:
// //   - a cache HashMap<usize, Vec<usize>> holding leaf IDs for every
// //     ancestor — O(N * depth) total entries, ~20x redundancy on a
// //     balanced tree of depth 20.
// //   - a second identical node_to_leaves HashMap copied from cache.
// //   - a third node_to_tris HashMap<usize, Vec<Triangle>> holding the
// //     fully expanded triangle data for every node — ancestors store
// //     all their descendants' triangles again, so the root alone
// //     duplicates the entire triangle set.
// // That stacked duplication is what caused the 20 GB spike.
// //
// // New approach: one pass, write once, no per-node intermediate vecs.
// // ------------------------------------------------------------
// fn collect_triangles_for_node(
//     node_id: usize,
//     nodes:     &HashMap<usize, BvhNode>,
//     leaves:    &HashMap<usize, BvhLeaf>,
//     triangles: &[Triangle],
//     out:       &mut Vec<Triangle>,
// ) {
//     let node = match nodes.get(&node_id) {
//         Some(n) => n,
//         None => return, // dangling reference — skip silently
//     };

//     if node.tri_count > 0 {
//         // This IS a leaf in the node tree — look it up in bvh_leaves
//         let leaf = match leaves.get(&node_id) {
//             Some(l) => l,
//             None => {
//                 // eprintln!("Warning: leaf node_id {} not found in bvh_leaves.txt", node_id);
//                 return;
//             }
//         };

//         let start = leaf.first_tri;
//         let count = leaf.tri_count;

//         for i in 0..count {
//             let tri_idx = start + i;
//             match triangles.get(tri_idx) {
//                 Some(tri) => out.push(*tri),
//                 None => eprintln!(
//                     "Warning: tri index {} out of range (total {})",
//                     tri_idx,
//                     triangles.len()
//                 ),
//             }
//         }
//         return;
//     }

//     // Internal node — recurse into both children
//     let left  = node.left_first;
//     let right = node.left_first + 1;
//     collect_triangles_for_node(left,  nodes, leaves, triangles, out);
//     collect_triangles_for_node(right, nodes, leaves, triangles, out);
// }


// // ------------------------------------------------------------
// // Parse BVH leaves
// // ------------------------------------------------------------
// fn parse_bvh_leaves(path: &str) -> HashMap<usize, BvhLeaf> {
//     let content = fs::read_to_string(path).expect("failed to read leaves file");

//     let mut map = HashMap::new();

//     for line in content.lines() {
//         if line.starts_with('#') || line.trim().is_empty() {
//             continue;
//         }

//         // Format: node_id  firstTri  triCount
//         //         [0]      [1]       [2]
//         let parts: Vec<&str> = line.split_whitespace().collect();
//         if parts.len() < 3 {
//             continue;
//         }

//         let node_id:   usize = parts[0].parse().unwrap();
//         let first_tri: usize = parts[1].parse().unwrap();
//         let tri_count: usize = parts[2].parse().unwrap();

//         map.insert(node_id, BvhLeaf { first_tri, tri_count });
//     }

//     map
// }


// // ------------------------------------------------------------
// // Parse triangles
// // ------------------------------------------------------------
// fn parse_triangles(path: &str) -> Vec<Triangle> {
//     let content = fs::read_to_string(path).expect("failed to read triangles file");

//     let mut tris = Vec::new();

//     for line in content.lines() {
//         if line.starts_with('#') || line.trim().is_empty() {
//             continue;
//         }

//         // Format: tri_id  v0.x v0.y v0.z  v1.x v1.y v1.z  v2.x v2.y v2.z
//         //         [0]     [1]  [2]  [3]   [4]  [5]  [6]   [7]  [8]  [9]
//         let parts: Vec<&str> = line.split_whitespace().collect();
//         if parts.len() < 10 {
//             continue;
//         }

//         let mut vals = [0f32; 9];
//         for i in 0..9 {
//             vals[i] = parts[i + 1].parse().unwrap();
//         }

//         tris.push(vals);
//     }

//     tris
// }





// pub fn run_data_acquisition() {
//     // ---- File paths ----
//     let nodes_path     = "../bvh_data/bvh_nodes.txt";
//     let leaves_path    = "../bvh_data/bvh_leaves.txt";
//     let triangles_path = "../bvh_data/bvh_triangles.txt";

//     // ---- Parse all inputs ----
//     let nodes     = parse_bvh_nodes(nodes_path);
//     let leaves    = parse_bvh_leaves(leaves_path);
//     let triangles = parse_triangles(triangles_path);

//     println!(
//         "Parsed {} nodes, {} leaves, {} triangles",
//         nodes.len(),
//         leaves.len(),
//         triangles.len()
//     );

//     // ---- Build node -> triangles directly, no intermediate maps ----
//     // For each node we walk its subtree once and write triangles straight
//     // into the output Vec.  Nothing is stored twice.
//     let mut node_to_tris: HashMap<usize, Vec<Triangle>> = HashMap::new();

//     let mut node_ids: Vec<usize> = nodes.keys().cloned().collect();
//     node_ids.sort();

//     for node_id in &node_ids {
//         let mut tris: Vec<Triangle> = Vec::new();
//         collect_triangles_for_node(*node_id, &nodes, &leaves, &triangles, &mut tris);
//         node_to_tris.insert(*node_id, tris);
//     }

//     // ---- Output ----
//     println!("Processed {} nodes", node_to_tris.len());

//     for node_id in node_ids.iter().take(10) {
//         let tris = &node_to_tris[node_id];
//         println!("Node {:>4} -> {} triangles", node_id, tris.len());
//     }
// }

// fn main() {
//     run_data_acquisition();
// }



/*

Above is single threaded version, but is slow

*/




// Cargo.toml dependencies needed:
//   rayon = "1"
//   dashmap = "6"

// Cargo.toml dependencies needed:
//   rayon = "1"
//   dashmap = "6"

use dashmap::DashMap;
use rayon::prelude::*;
use std::collections::HashMap;
use std::fs;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

// ------------------------------------------------------------
// How many bytes the triangle cache is allowed to occupy before
// new results are computed-but-not-stored.
// 512 MB is a reasonable starting point; tune as needed.
// Each Triangle is 9 x f32 = 36 bytes.
// ------------------------------------------------------------
const CACHE_BYTE_LIMIT: usize = 512 * 1024 * 1024;

// ------------------------------------------------------------
// Data types
// ------------------------------------------------------------

#[derive(Debug, Clone)]
struct BvhNode {
    left_first: usize,
    tri_count:  usize,
}

#[derive(Debug, Clone)]
struct BvhLeaf {
    first_tri: usize,
    tri_count: usize,
}

// A triangle is three vertices, each with x/y/z → 9 floats.
type Triangle = [f32; 9];

const TRIANGLE_BYTES: usize = std::mem::size_of::<Triangle>(); // 36


// ------------------------------------------------------------
// Parsers — purely sequential; file I/O doesn't benefit from
// parallelism and these run once at startup.
// ------------------------------------------------------------

fn parse_bvh_nodes(path: &str) -> HashMap<usize, BvhNode> {
    let content = fs::read_to_string(path).expect("failed to read bvh_nodes.txt");
    let mut map = HashMap::new();

    for line in content.lines() {
        if line.starts_with('#') || line.trim().is_empty() {
            continue;
        }
        // Format: node_id  min.x min.y min.z  max.x max.y max.z  leftFirst  triCount
        //         [0]      [1]   [2]   [3]    [4]   [5]   [6]    [7]        [8]
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 9 {
            continue;
        }
        let node_id:    usize = parts[0].parse().unwrap();
        let left_first: usize = parts[7].parse().unwrap();
        let tri_count:  usize = parts[8].parse().unwrap();
        map.insert(node_id, BvhNode { left_first, tri_count });
    }
    map
}

fn parse_bvh_leaves(path: &str) -> HashMap<usize, BvhLeaf> {
    let content = fs::read_to_string(path).expect("failed to read bvh_leaves.txt");
    let mut map = HashMap::new();

    for line in content.lines() {
        if line.starts_with('#') || line.trim().is_empty() {
            continue;
        }
        // Format: node_id  firstTri  triCount
        //         [0]      [1]       [2]
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 3 {
            continue;
        }
        let node_id:   usize = parts[0].parse().unwrap();
        let first_tri: usize = parts[1].parse().unwrap();
        let tri_count: usize = parts[2].parse().unwrap();
        map.insert(node_id, BvhLeaf { first_tri, tri_count });
    }
    map
}

fn parse_triangles(path: &str) -> Vec<Triangle> {
    let content = fs::read_to_string(path).expect("failed to read bvh_triangles.txt");
    let mut tris = Vec::new();

    for line in content.lines() {
        if line.starts_with('#') || line.trim().is_empty() {
            continue;
        }
        // Format: tri_id  v0.x v0.y v0.z  v1.x v1.y v1.z  v2.x v2.y v2.z
        //         [0]     [1]  [2]  [3]   [4]  [5]  [6]   [7]  [8]  [9]
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 10 {
            continue;
        }
        let mut vals = [0f32; 9];
        for i in 0..9 {
            vals[i] = parts[i + 1].parse().unwrap();
        }
        tris.push(vals);
    }
    tris
}


// ------------------------------------------------------------
// Core recursive walk
//
// Visits the subtree rooted at `node_id`.  When it reaches a
// node whose tri_count > 0 in bvh_nodes (a true leaf), it:
//   1. Looks that node_id up in bvh_leaves to get firstTri + triCount.
//   2. Copies triCount consecutive triangles starting at firstTri
//      from the bvh_triangles array into `out`.
//
// Internal nodes (tri_count == 0) recurse into:
//   left  child = left_first
//   right child = left_first + 1
// ------------------------------------------------------------
fn walk(
    node_id:   usize,
    nodes:     &HashMap<usize, BvhNode>,
    leaves:    &HashMap<usize, BvhLeaf>,
    triangles: &[Triangle],
    out:       &mut Vec<Triangle>,
) {
    let node = match nodes.get(&node_id) {
        Some(n) => n,
        None    => return,
    };

    if node.tri_count > 0 {
        // ---- True leaf: left_first IS the bvh_leaves node_id to look up.
        // The current node's tri_count tells us how many triangles to expect,
        // but the actual firstTri offset lives in bvh_leaves under left_first.
        // e.g. node 15 has left_first=71, tri_count=1 → look up node 71 in
        // bvh_leaves to find where in bvh_triangles to read from.
        let leaf_id = node.left_first;
        let leaf = match leaves.get(&leaf_id) {
            Some(l) => l,
            None => {
                eprintln!(
                    "Warning: node {} points to leaf {} which is missing from bvh_leaves",
                    node_id, leaf_id
                );
                return;
            }
        };

        // Collect leaf.tri_count consecutive triangles starting at leaf.first_tri
        let end = leaf.first_tri + leaf.tri_count;
        if end > triangles.len() {
            eprintln!(
                "Warning: leaf {} requests tris {}..{} but only {} exist",
                leaf_id, leaf.first_tri, end, triangles.len()
            );
            return;
        }
        out.extend_from_slice(&triangles[leaf.first_tri..end]);
        return;
    }

    // ---- Internal node: recurse into both children ----
    let left  = node.left_first;
    let right = node.left_first + 1;
    walk(left,  nodes, leaves, triangles, out);
    walk(right, nodes, leaves, triangles, out);
}


// ------------------------------------------------------------
// Build triangles for a single node_id, using the cache when
// available and inserting into it when space permits.
//
// The cache stores Arc<Vec<Triangle>> so that many ancestor nodes
// can share the same leaf data read-only without cloning the floats.
//
// cache_bytes tracks total allocated bytes. Once it would exceed
// CACHE_BYTE_LIMIT, results are still computed correctly — they
// just aren't stored in the cache.
// ------------------------------------------------------------
fn triangles_for_node(
    node_id:     usize,
    nodes:       &HashMap<usize, BvhNode>,
    leaves:      &HashMap<usize, BvhLeaf>,
    triangles:   &[Triangle],
    cache:       &DashMap<usize, Arc<Vec<Triangle>>>,
    cache_bytes: &AtomicUsize,
) -> Arc<Vec<Triangle>> {

    // Cache hit
    if let Some(entry) = cache.get(&node_id) {
        return Arc::clone(&entry);
    }

    // Compute
    let mut tris: Vec<Triangle> = Vec::new();
    walk(node_id, nodes, leaves, triangles, &mut tris);
    let arc = Arc::new(tris);

    // Insert only if budget allows
    let cost = arc.len() * TRIANGLE_BYTES;
    let prev = cache_bytes.fetch_add(cost, Ordering::Relaxed);
    if prev + cost <= CACHE_BYTE_LIMIT {
        cache.insert(node_id, Arc::clone(&arc));
    } else {
        cache_bytes.fetch_sub(cost, Ordering::Relaxed);
    }

    arc
}


// ------------------------------------------------------------
// Main entry point
// ------------------------------------------------------------
pub fn run_data_acquisition() {
    let nodes_path     = "./bvh_data/bvh_nodes.txt";
    let leaves_path    = "./bvh_data/bvh_leaves.txt";
    let triangles_path = "./bvh_data/bvh_triangles.txt";

    // ---- Parse inputs (sequential — I/O bound, runs once) ----
    let nodes     = parse_bvh_nodes(nodes_path);
    let leaves    = parse_bvh_leaves(leaves_path);
    let triangles = parse_triangles(triangles_path);

    println!(
        "Parsed {} nodes, {} leaves, {} triangles",
        nodes.len(), leaves.len(), triangles.len()
    );

    // ---- Sorted node ID list ----
    let mut node_ids: Vec<usize> = nodes.keys().cloned().collect();
    node_ids.sort_unstable();

    // ---- TEST LIMIT: only process the first 10 nodes ----
    // Remove or comment this line out when ready for the full run.
    let node_ids = &node_ids[..10.min(node_ids.len())];
    let max_id = *node_ids.last().unwrap_or(&0);

    // ---- Shared state (all read-only inputs + concurrent cache) ----
    // No Arc needed for inputs — rayon borrows are scoped to this fn.
    let cache:       DashMap<usize, Arc<Vec<Triangle>>> = DashMap::new();
    let cache_bytes: AtomicUsize                        = AtomicUsize::new(0);

    // Pre-allocate output indexed by node_id so parallel writes need
    // no locking — each task writes to a unique index.
    let mut output: Vec<Arc<Vec<Triangle>>> =
        vec![Arc::new(Vec::new()); max_id + 1];

    // ---- Parallel computation via rayon ----
    // All inputs are & (shared read-only) — zero synchronisation needed.
    // DashMap handles concurrent cache access with fine-grained locking.
    let results: Vec<(usize, Arc<Vec<Triangle>>)> = node_ids
        .par_iter()
        .map(|&node_id| {
            let tris = triangles_for_node(
                node_id,
                &nodes,
                &leaves,
                &triangles,
                &cache,
                &cache_bytes,
            );
            (node_id, tris)
        })
        .collect(); // rayon collects in parallel, returns in order

    // Sequential write into the output array (already parallel above)
    for (node_id, tris) in results {
        output[node_id] = tris;
    }

    // ---- Summary ----
    println!(
        "Processed {} nodes | cache: {:.1} MB used / {:.0} MB limit",
        node_ids.len(),
        cache_bytes.load(Ordering::Relaxed) as f64 / (1024.0 * 1024.0),
        CACHE_BYTE_LIMIT as f64 / (1024.0 * 1024.0),
    );

    for node_id in node_ids.iter() {
        println!("Node {:>4} -> {} triangles", node_id, output[*node_id].len());
    }

    // `output` is your final result:
    //   output[node_id] → Arc<Vec<Triangle>> of all triangles in that subtree
}

fn main() {
    run_data_acquisition();
}


// 231296 <- example to ask Alex about