// SPDX-License-Identifier: Apache-2.0
import posix from "../vendor/goose-terminal";
import summary from "..";
import std;
import os;
extern fn select_mode(mode: i64) = "gc_summary_mode";
extern fn calls() -> i64 = "gc_summary_calls";
fn main() {
    var text: u8[>..] = []; arg(1, text);
    let mode, ok = parse_int(text); assert(ok && mode >= 0 && mode <= 4);
    select_mode(mode);
    summary::complete(summary::Mode.Always, true);
    let counts = [8, 9, 2, 64];
    assert(mode < 4 && calls() == counts[mode]);
    print("checker outcome preserved");
}
