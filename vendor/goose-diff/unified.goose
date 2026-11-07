// SPDX-License-Identifier: Apache-2.0
namespace patch;
import .diff;
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
