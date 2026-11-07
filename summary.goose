// SPDX-License-Identifier: Apache-2.0
// Called only after direct-child ownership and the application guard are closed.
namespace summary;
import posix;
import std;
import os;
enum Mode { Never, Auto, Always }
fn mode(value: const u8[:]) -> Mode {
    if value == "always" { Mode.Always } else if value == "auto" { Mode.Auto } else { Mode.Never }
}
fn complete(policy: Mode, matched: bool) {
    if policy == Mode.Never { return; }
    let snapshot = terminal_posix::snapshot(2);
    if snapshot.os_error != 0 || (policy == Mode.Auto && !snapshot.tty) { return; }
    var out: u8[>..] = [];
    let style = if matched { terminal::Style.Success } else { terminal::Style.Failure };
    let message = if matched { "goose-check: matched" } else { "goose-check: check failed" };
    if terminal::line(snapshot.capabilities, style, message, out) != terminal::Error.None { return; }
    // A child may have left an unterminated diagnostic. Never erase it.
    insert_at(out, 0, '\n');
    var offset: i64 = 0;
    for attempt in 64 {
        let result = terminal_posix::write_step(2, out[offset..]);
        offset += result.written;
        if result.cleanup_error != 0 { exit(125); }
        if result.error == terminal_posix::WriteError.Interrupted { continue; }
        if result.error != terminal_posix::WriteError.None { return; }
        if offset == out.len || result.written == 0 { return; }
    }
}
