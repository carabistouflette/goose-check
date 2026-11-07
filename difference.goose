// SPDX-License-Identifier: Apache-2.0
// Application policy: capped escaped diagnostics, no I/O in the renderer.
namespace difference;
import diff;
import diff.unified;
import std;
const MAX_DIAGNOSTIC_BYTES = 16384;
const HEADER = "goose-check: escaped stdout diff (expected -> actual)\n";
const TRUNCATED = "\n[diff truncated]\n";
const OMITTED = "goose-check: stdout diff omitted (resource limit)\n";
const HEX = "0123456789ABCDEF";
fn render(expected: const u8[:], actual: const u8[:], out: u8[>..]&) {
    out.clear();
    var raw: u8[>..] = [];
    let error = patch::unified(expected, actual, raw, diff::Limits {
        max_bytes: 65536, max_lines: 4096, max_cells: 262144, max_work: 1048576,
    }, MAX_DIAGNOSTIC_BYTES);
    if error != diff::Error.None { out.append(OMITTED); return; }
    if raw.len == 0 { return; }
    out.append(HEADER);
    let end = MAX_DIAGNOSTIC_BYTES - TRUNCATED.len;
    for byte in raw {
        let literal = byte == '\n' || (byte >= 32 && byte <= 126 && byte != '\\');
        let width = if literal { 1 } else { 4 };
        if width > end - out.len { out.append(TRUNCATED); return; }
        if literal { out.push(byte); }
        else { out.append("\\x"); out.push(HEX[byte as i64 / 16]); out.push(HEX[byte as i64 % 16]); }
    }
}
