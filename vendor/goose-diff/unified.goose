// SPDX-License-Identifier: Apache-2.0
namespace patch;
import .diff;
import .sparse;
import std;

const MAX_OUTPUT_BYTES = 8388608;

fn append(out: u8[>..]&, text: const u8[:], limit: i64) -> bool {
    if text.len > limit - out.len { return false; }
    out.append(text); return true;
}

// Counts never exceed MAX_LINES. Construct ASCII digits without application
// formatting overloads, locale, or temporary unbounded strings.
fn decimal(out: u8[>..]&, value: i64, limit: i64) -> bool {
    var digits: u8[20];
    var at = 20; var left = value;
    while true {
        at--; digits[at] = ('0' + left % 10) as! u8; left /= 10;
        if left == 0 { break; }
    }
    return append(out, digits[at..], limit);
}

// Advance one input line and append its complete raw bytes. Content is not
// terminal escaped; the caller decides where raw patch bytes may be exposed.
fn line(out: u8[>..]&, text: const u8[:], cursor: i64&, prefix: const u8[:], limit: i64) -> bool {
    let start = cursor;
    while cursor < text.len && text[cursor] != '\n' { cursor++; }
    if cursor < text.len { cursor++; }
    if !append(out, prefix, limit) || !append(out, text[start..cursor], limit) { return false; }
    if cursor > start && text[cursor - 1] != '\n' {
        if !append(out, "\n\\ No newline at end of file\n", limit) { return false; }
    }
    return true;
}

fn render(old: const u8[:], fresh: const u8[:], edits: const diff::Edit[:], out: u8[>..]&, limit: i64) -> bool {
    var changed = false;
    var old_count = 0; var new_count = 0;
    for edit in edits {
        if edit.kind != diff::Kind.Equal { changed = true; }
        old_count = edit.old_end; new_count = edit.new_end;
    }
    if !changed { return true; }
    if !append(out, "--- a/input\n+++ b/input\n@@ -", limit) ||
       !decimal(out, if old_count == 0 { 0 } else { 1 }, limit) ||
       !append(out, ",", limit) || !decimal(out, old_count, limit) ||
       !append(out, " +", limit) || !decimal(out, if new_count == 0 { 0 } else { 1 }, limit) ||
       !append(out, ",", limit) || !decimal(out, new_count, limit) ||
       !append(out, " @@\n", limit) { return false; }
    var a = 0; var b = 0;
    for edit in edits {
        if edit.kind == diff::Kind.Equal {
            for i in edit.old_end - edit.old_start {
                if !line(out, old, a, " ", limit) { return false; }
                while b < fresh.len && fresh[b] != '\n' { b++; }
                if b < fresh.len { b++; }
            }
        } else if edit.kind == diff::Kind.Delete {
            for i in edit.old_end - edit.old_start {
                if !line(out, old, a, "-", limit) { return false; }
            }
        } else {
            for i in edit.new_end - edit.new_start {
                if !line(out, fresh, b, "+", limit) { return false; }
            }
        }
    }
    return true;
}

// One full-file unified hunk with fixed labels. Identical inputs yield empty
// output. On error output is empty; its retained capacity is caller-owned.
fn unified(old: const u8[:], fresh: const u8[:], out: u8[>..]&, limits: diff::Limits, output_limit: i64) -> diff::Error {
    out.clear();
    if output_limit < 0 || output_limit > MAX_OUTPUT_BYTES { return diff::Error.InvalidOptions; }
    var edits: diff::Edit[>..] = [];
    let error = diff::compare(old, fresh, edits, limits);
    if error != diff::Error.None { return error; }
    if !render(old, fresh, edits, out, output_limit) { out.clear(); return diff::Error.LimitExceeded; }
    return diff::Error.None;
}

struct Row { kind: diff::Kind, old_start: i64, new_start: i64 }
struct Hunk { start: i64, end: i64 }

// Expand only the library's validated script. At most old_lines + new_lines
// rows, plus one coordinate sentinel; nothing borrows either input.
fn rows_from_edits(edits: const diff::Edit[:], rows: Row[>..]&) {
    var a = 0; var b = 0;
    for edit in edits {
        let count = if edit.kind == diff::Kind.Insert { edit.new_end - edit.new_start }
                    else { edit.old_end - edit.old_start };
        for i in count {
            rows.push(Row { kind: edit.kind, old_start: a, new_start: b });
            if edit.kind != diff::Kind.Insert { a++; }
            if edit.kind != diff::Kind.Delete { b++; }
        }
    }
    rows.push(Row { kind: diff::Kind.Equal, old_start: a, new_start: b });
}

// Equal rows are one line in both inputs. Change windows overlap or touch
// exactly when their intervening equal gap is at most twice the context.
fn plan_hunks(rows: const Row[:], context_lines: i64, hunks: Hunk[>..]&) {
    let count = rows.len - 1;
    for i in count {
        if rows[i].kind == diff::Kind.Equal { continue; }
        let start = max(0, i - context_lines);
        let end = min(count, i + 1 + context_lines);
        if hunks.len > 0 && start <= hunks[hunks.len - 1].end {
            hunks[hunks.len - 1].end = end;
        } else { hunks.push(Hunk { start: start, end: end }); }
    }
}

fn skip_line(text: const u8[:], cursor: i64&) {
    while cursor < text.len && text[cursor] != '\n' { cursor++; }
    if cursor < text.len { cursor++; }
}

fn coordinate(out: u8[>..]&, start: i64, count: i64, limit: i64) -> bool {
    return decimal(out, if count == 0 { start } else { start + 1 }, limit) &&
           append(out, ",", limit) && decimal(out, count, limit);
}

fn render_context(old: const u8[:], fresh: const u8[:], edits: const diff::Edit[:], out: u8[>..]&, limit: i64, context_lines: i64) -> bool {
    var changed = false;
    for edit in edits { if edit.kind != diff::Kind.Equal { changed = true; break; } }
    if !changed { return true; }
    var rows:  Row[>..]  = []; rows_from_edits(edits, rows);
    var hunks: Hunk[>..] = []; plan_hunks(rows, context_lines, hunks);
    if hunks.len == 0 { return true; }
    if !append(out, "--- a/input\n+++ b/input\n", limit) { return false; }
    var a = 0; var b = 0; var at = 0;
    for hunk in hunks {
        let first = rows[hunk.start]; let after = rows[hunk.end];
        if !append(out, "@@ -", limit) ||
           !coordinate(out, first.old_start, after.old_start - first.old_start, limit) ||
           !append(out, " +", limit) ||
           !coordinate(out, first.new_start, after.new_start - first.new_start, limit) ||
           !append(out, " @@\n", limit) { return false; }
        // Both input cursors advance monotonically. Omitted context is scanned
        // once, not rescanned from the beginning for each subsequent hunk.
        while at < hunk.start {
            if rows[at].kind != diff::Kind.Insert { skip_line(old, a); }
            if rows[at].kind != diff::Kind.Delete { skip_line(fresh, b); }
            at++;
        }
        while at < hunk.end {
            let kind = rows[at].kind;
            if kind == diff::Kind.Equal {
                if !line(out, old, a, " ", limit) { return false; }
                skip_line(fresh, b);
            } else if kind == diff::Kind.Delete {
                if !line(out, old, a, "-", limit) { return false; }
            } else {
                if !line(out, fresh, b, "+", limit) { return false; }
            }
            at++;
        }
    }
    return true;
}

// Context is measured in unchanged lines on either side of every change.
// Zero-count ranges use the preceding line, including zero at file start.
fn unified_context(old: const u8[:], fresh: const u8[:], out: u8[>..]&, limits: diff::Limits, output_limit: i64, context_lines: i64) -> diff::Error {
    out.clear();
    if output_limit < 0 || output_limit > MAX_OUTPUT_BYTES ||
       context_lines < 0 || context_lines > diff::MAX_LINES { return diff::Error.InvalidOptions; }
    var edits: diff::Edit[>..] = [];
    let error = diff::compare(old, fresh, edits, limits);
    if error != diff::Error.None { return error; }
    if !render_context(old, fresh, edits, out, output_limit, context_lines) {
        out.clear(); return diff::Error.LimitExceeded;
    }
    return diff::Error.None;
}

// Explicit sparse strategy with independent trace-state limits. The validated
// script uses the same byte-exact context renderer; LCS APIs stay unchanged.
fn unified_sparse_context(old: const u8[:], fresh: const u8[:], out: u8[>..]&, limits: sparse::Limits, output_limit: i64, context_lines: i64) -> diff::Error {
    out.clear();
    if output_limit < 0 || output_limit > MAX_OUTPUT_BYTES ||
       context_lines < 0 || context_lines > diff::MAX_LINES { return diff::Error.InvalidOptions; }
    var edits: diff::Edit[>..] = [];
    let error = sparse::compare(old, fresh, edits, limits);
    if error != diff::Error.None { return error; }
    if !render_context(old, fresh, edits, out, output_limit, context_lines) {
        out.clear(); return diff::Error.LimitExceeded;
    }
    return diff::Error.None;
}
