// SPDX-License-Identifier: Apache-2.0
// Explicit opt-in bounded sparse comparison. LCS remains a separate strategy.
namespace sparse;
import .diff;
import std;

const MAX_BYTES = 1048576;
const MAX_LINES = 16384;
const MAX_STATES = 4194304;
const MAX_WORK = 67108864;
struct Limits {
    max_bytes:  i64 = 1048576,
    max_lines:  i64 = 16384,
    max_states: i64 = 1048576,
    max_work:   i64 = 16777216,
}

fn valid(limits: Limits) -> bool {
    return limits.max_bytes >= 0 && limits.max_bytes <= MAX_BYTES &&
           limits.max_lines >= 0 && limits.max_lines <= MAX_LINES &&
           limits.max_states >= 0 && limits.max_states <= MAX_STATES &&
           limits.max_work >= 0 && limits.max_work <= MAX_WORK;
}
struct Step { x: i64 = -1, y: i64 = -1, deleted: bool = false, valid: bool = false }

// A compact distance-d row stores d+1 furthest x values, for k=-d+2*j.
// Choose the farther candidate x BEFORE its snake; equal candidates delete.
// Both candidates are checked against the input rectangle before use.
fn predecessor(trace: const i64[:], d: i64, j: i64, n: i64, m: i64) -> Step {
    let start = (d - 1) * d / 2;
    let k = -d + 2 * j;
    var insert = Step { .. }; var remove = Step { .. };
    if j < d {
        let x = trace[start + j]; let y = x - (k + 1);
        if x >= 0 && x <= n && y >= 0 && y < m {
            insert = Step { x: x, y: y, deleted: false, valid: true };
        }
    }
    if j > 0 {
        let x = trace[start + j - 1]; let y = x - (k - 1);
        if x >= 0 && x < n && y >= 0 && y <= m {
            remove = Step { x: x, y: y, deleted: true, valid: true };
        }
    }
    if remove.valid && (!insert.valid || remove.x + 1 >= insert.x) { return remove; }
    return insert;
}

fn restore(trace: const i64[:], distance: i64, n: i64, m: i64, prefix: i64, out: diff::Edit[>..]&) {
    var reverse: diff::Edit[>..] = [];
    var x = n; var y = m; var d = distance;
    while d > 0 {
        let j = (x - y + d) / 2;
        let step = predecessor(trace, d, j, n, m);
        assert(step.valid);
        let sx = step.x + (if step.deleted { 1 } else { 0 });
        let sy = step.y + (if step.deleted { 0 } else { 1 });
        assert(x >= sx && y >= sy && x - sx == y - sy);
        if x > sx {
            reverse.push(diff::Edit { kind: diff::Kind.Equal,
                old_start: prefix + sx, old_end: prefix + x,
                new_start: prefix + sy, new_end: prefix + y });
        }
        reverse.push(diff::Edit { kind: if step.deleted { diff::Kind.Delete } else { diff::Kind.Insert },
            old_start: prefix + step.x, old_end: prefix + sx,
            new_start: prefix + step.y, new_end: prefix + sy });
        x = step.x; y = step.y; d--;
    }
    assert(x == y);
    if x > 0 {
        reverse.push(diff::Edit { kind: diff::Kind.Equal,
            old_start: prefix, old_end: prefix + x,
            new_start: prefix, new_end: prefix + y });
    }
    var at = reverse.len;
    while at > 0 {
        at--; let edit = reverse[at];
        diff::emit(out, edit.kind, edit.old_start, edit.old_end, edit.new_start, edit.new_end);
    }
}

fn search(old: const u8[:], fresh: const u8[:], a: const diff::Line[:], b: const diff::Line[:], prefix: i64, n: i64, m: i64,
          out: diff::Edit[>..]&, budget: diff::Budget&, max_states: i64) -> diff::Error {
    var trace: i64[>..] = [];
    var d = 0;
    while d <= n + m {
        // Count even unreachable or not-yet-visited slots in the complete row.
        // No separate frontier array or uncounted row snapshots are retained.
        if d + 1 > max_states - trace.len { return diff::Error.LimitExceeded; }
        let start = trace.len;
        for i in d + 1 { trace.push(-1); }
        for j in d + 1 {
            var x = 0; var y = 0;
            if d > 0 {
                let step = predecessor(trace, d, j, n, m);
                if !step.valid { continue; }
                x = step.x + (if step.deleted { 1 } else { 0 });
                y = step.y + (if step.deleted { 0 } else { 1 });
            }
            while x < n && y < m && diff::same(old, a[prefix + x], fresh, b[prefix + y], budget) { x++; y++; }
            if budget.exhausted { return diff::Error.LimitExceeded; }
            trace[start + j] = x;
            if x == n && y == m {
                restore(trace, d, n, m, prefix, out);
                return diff::Error.None;
            }
        }
        d++;
    }
    return diff::Error.LimitExceeded;
}

fn compare_impl(old: const u8[:], fresh: const u8[:], out: diff::Edit[>..]&, limits: Limits) -> diff::Error {
    if !valid(limits) { return diff::Error.InvalidOptions; }
    if old.len > limits.max_bytes || fresh.len > limits.max_bytes { return diff::Error.LimitExceeded; }
    var a: diff::Line[>..] = []; var b: diff::Line[>..] = [];
    if !diff::split(old, a, limits.max_lines) || !diff::split(fresh, b, limits.max_lines) { return diff::Error.LimitExceeded; }
    var budget = diff::Budget { remaining: limits.max_work };
    var prefix = 0;
    while prefix < a.len && prefix < b.len && diff::same(old, a[prefix], fresh, b[prefix], budget) { prefix++; }
    if budget.exhausted { return diff::Error.LimitExceeded; }
    var ae = a.len; var be = b.len;
    while ae > prefix && be > prefix && diff::same(old, a[ae - 1], fresh, b[be - 1], budget) { ae--; be--; }
    if budget.exhausted { return diff::Error.LimitExceeded; }
    diff::emit(out, diff::Kind.Equal, 0, prefix, 0, prefix);
    let n = ae - prefix; let m = be - prefix;
    if n == 0 || m == 0 {
        diff::emit(out, diff::Kind.Delete, prefix, ae, prefix, prefix);
        diff::emit(out, diff::Kind.Insert, ae, ae, prefix, be);
    } else {
        let error = search(old, fresh, a, b, prefix, n, m, out, budget, limits.max_states);
        if error != diff::Error.None { return error; }
    }
    diff::emit(out, diff::Kind.Equal, ae, a.len, be, b.len);
    return diff::Error.None;
}

// max_states bounds ALL retained trace slots (8 logical bytes each), including
// unreachable and unvisited final-row positions; it also bounds frontier visits.
// Token storage and reverse/output edits have separate input-line bounds.
// Farthest candidate-x ties delete; returned optimal scripts may differ from LCS.
// No automatic strategy selection or fallback occurs. Errors clear output.
fn compare(old: const u8[:], fresh: const u8[:], out: diff::Edit[>..]&, limits: Limits) -> diff::Error {
    out.clear();
    let error = compare_impl(old, fresh, out, limits);
    if error != diff::Error.None { out.clear(); }
    return error;
}
