// SPDX-License-Identifier: Apache-2.0
import argparse from "./vendor/goose-argparse";
import process from "./vendor/goose-process";
import fs from "./vendor/goose-fs";
import config from "./vendor/goose-config";
import .settings;
import std;
import os;

extern fn guard_begin() -> bool = "gc_guard_begin";
extern fn guard_take(pid: i64) -> i64 = "gc_guard_take";
extern fn guard_end() -> i64 = "gc_guard_end";
extern fn recover(pid: i64) = "gc_recover";
extern fn diagnostic(message: const u8[:]) = "gc_diagnostic";

fn usage() {
    diagnostic("usage: goose-check [--config ABSFILE.json|ABSFILE.toml] [--stdin ABSFILE] [--stdout ABSFILE] [--stderr ABSFILE] [--expect-exit N] [--timeout-ms N] [--output-limit N] -- /absolute/program [args...]\n");
}
fn fail(message: const u8[:], code: i32) {
    diagnostic(str("goose-check: ", message, "\n")); exit(code);
}
fn decimal(text: const u8[:], maximum: i64) -> i64 {
    if text.len == 0 { return -1; }
    var value: i64 = 0;
    for byte in text {
        if byte < '0' || byte > '9' { return -1; }
        let digit = (byte - '0') as i64;
        if value > (maximum - digit) / 10 { return -1; }
        value = value * 10 + digit;
    }
    return value;
}
fn main() {
    let argv = args();
    if argv.len == 2 && argv[1] == "--help" { usage(); return; }
    var expected_exit: i64 = 0;
    var timeout:       i64 = 30000;
    var limit:         i64 = 65536;
    var seen:          i64 = 0;
    var separator = argv.len;
    for argument, index in argv { if index > 0 && argument == "--" { separator = index; break; } }
    if separator + 1 >= argv.len { usage(); exit(2); }
    let spec = [argparse::option("stdin"), argparse::option("stdout"), argparse::option("stderr"),
                argparse::option("config"), argparse::option("expect-exit"),
                argparse::option("timeout-ms"), argparse::option("output-limit")];
    let options = argparse::parse(spec, argv[1..separator]);
    if options.error != argparse::Error.None || options.positionals.len != 0 { usage(); exit(2); }
    let input_path = str(options.get("stdin"));
    let expected_path = str(options.get("stdout"));
    let stderr_path = str(options.get("stderr"));
    let config_path = str(options.get("config"));
    for entry in options.entries {
        let bit: i64 = if entry.name == "stdin" { 1 } else if entry.name == "stdout" { 2 }
            else if entry.name == "expect-exit" { 4 } else if entry.name == "timeout-ms" { 8 }
            else if entry.name == "output-limit" { 16 } else if entry.name == "config" { 32 }
            else { 64 };
        if (seen & bit) != 0 { usage(); exit(2); }
        seen |= bit;
        let value = entry.value;
        if bit == 32 {
            if !settings::valid_path(value) { fail("config requires a strict absolute .json or .toml path", 2); }
        } else if bit == 1 || bit == 2 || bit == 64 {
            if !fs::valid_path(value) { fail("fixture requires a strict absolute path", 2); }
        } else {
            let maximum: i64 = if bit == 4 { 255 } else if bit == 8 { process::MAX_TIMEOUT_MS } else { process::MAX_OUTPUT_BYTES };
            let number = decimal(value, maximum);
            if number < 0 || (bit == 8 && number == 0) { fail("invalid numeric option", 2); }
            if bit == 4 { expected_exit = number; } else if bit == 8 { timeout = number; } else { limit = number; }
        }
    }
    var position = separator + 1;
    if position >= argv.len || argv[position].len == 0 || argv[position][0] != '/' { usage(); exit(2); }
    var command: (const u8[:])[>..] = [];
    while position < argv.len { command.push(argv[position]); position += 1; }
    if command.len > process::MAX_ARGUMENTS || command[0].len > process::MAX_PATH_BYTES {
        fail("command exceeds argument bounds", 2);
    }
    var argument_bytes: i64 = 0;
    for argument in command {
        argument_bytes += argument.len + 1;
        if argument.len > process::MAX_ARGUMENT_LENGTH || argument_bytes > process::MAX_ARGUMENT_BYTES {
            fail("command exceeds argument bounds", 2);
        }
    }
    if config_path.len > 0 {
        // Keep CLI's digit-only grammar and leading-zero acceptance. Canonical
        // validated integers avoid introducing the config token-length cap.
        let exit_text = str(expected_exit); let timeout_text = str(timeout); let limit_text = str(limit);
        var overrides: config::Override[>..] = [];
        if (seen & 4) != 0 { overrides.push(config::Override { "expect_exit", exit_text, "--expect-exit" }); }
        if (seen & 8) != 0 { overrides.push(config::Override { "timeout_ms", timeout_text, "--timeout-ms" }); }
        if (seen & 16) != 0 { overrides.push(config::Override { "output_limit", limit_text, "--output-limit" }); }
        var limits = settings::Limits { .. };
        let error = settings::load(config_path, overrides, limits);
        if error == settings::Error.Read { fail("cannot read bounded config file", 125); }
        if error != settings::Error.None { fail("invalid config defaults", 2); }
        expected_exit = limits.expected_exit; timeout = limits.timeout_ms; limit = limits.output_limit;
    }
    var input:           u8[>..] = [];
    var expected:        u8[>..] = [];
    var expected_stderr: u8[>..] = [];
    if input_path.len > 0 && fs::read(input_path, process::MAX_INPUT_BYTES, input).error != fs::Error.None {
        fail("cannot read bounded stdin fixture", 125);
    }
    if expected_path.len > 0 && fs::read(expected_path, limit, expected).error != fs::Error.None {
        fail("cannot read bounded expected stdout fixture", 125);
    }
    if stderr_path.len > 0 && fs::read(stderr_path, limit, expected_stderr).error != fs::Error.None {
        fail("cannot read bounded expected stderr fixture", 125);
    }
    if !guard_begin() { fail("cannot establish signal ownership guard", 125); }
    let before_start = guard_take(0);
    if before_start != 0 {
        let received = guard_end();
        if received > 0 { exit((128 + received) as! i32); }
        fail("signal guard failed", 125);
    }
    var child = process::Child { .. };
    var status = process::start(command, process::Options {
        timeout_ms: timeout, stdout: process::Output.Capture,
        stderr:     if stderr_path.len > 0 { process::Output.Stream } else { process::Output.Inherit }, stdin: process::Input.Bytes,
        input:      input, stdout_limit: limit,
    }, child);
    if status.unreaped_pid != 0 { recover(status.unreaped_pid); }
    var finished = false;
    var guard_failed = false;
    var stderr_chunk: u8[8192] = [0; 8192]; var no_stdout: u8[0] = [];
    var stderr_count: i64      = 0; var stderr_offset: i64 = -1;
    var stderr_limit_hit = false;
    while status.error == process::Error.None && !finished {
        // Query id only immediately before the observational group check.
        let pending = guard_take(process::id(child));
        if pending < 0 { guard_failed = true; break; }
        let number: i64 = if (pending & 4) != 0 { 15 } else if (pending & 3) != 0 { 2 } else { 0 };
        if number != 0 {
            let forwarded = process::send_signal(child, number);
            if forwarded.error != process::Error.None && forwarded.error != process::Error.InvalidState && forwarded.os_error != 3 {
                guard_failed = true; break;
            }
        }
        if stderr_path.len > 0 {
            let current, complete, n, m = process::stream_step(child, no_stdout[..], stderr_chunk[..], 20);
            status = current; finished = complete;
            if stderr_offset < 0 {
                for i in m {
                    if stderr_count + i >= expected_stderr.len || stderr_chunk[i] != expected_stderr[stderr_count + i] {
                        stderr_offset = stderr_count + i; break;
                    }
                }
            }
            if m > limit - stderr_count && status.error == process::Error.None {
                stderr_limit_hit = true;
                status = process::Status { error: process::Error.OutputLimit };
            }
            // Includes at most one bounded chunk beyond the configured cap.
            stderr_count += m;
        } else {
            let current, complete = process::step(child, 20);
            status = current; finished = complete;
        }
        if status.unreaped_pid != 0 { recover(status.unreaped_pid); }
    }
    let closed = process::close(child);
    if closed.unreaped_pid != 0 { recover(closed.unreaped_pid); }
    if (status.error == process::Error.None || stderr_limit_hit) && closed.error != process::Error.None { status = closed; }
    let received = guard_end();
    if received > 0 { exit((128 + received) as! i32); }
    if received < 0 || guard_failed { fail("signal guard or forwarding failed", 125); }
    if status.error == process::Error.LaunchFailed {
        fail("command launch failed", if status.os_error == 2 { 127 } else { 126 });
    }
    if status.error != process::Error.None {
        diagnostic(str("goose-check: process error ", status.error, "; errno ", status.os_error, "\n")); exit(125);
    }
    if status.signal != 0 || status.exit_code != expected_exit {
        diagnostic(str("goose-check: exit mismatch; expected ", expected_exit,
            ", actual ", status.exit_code, ", signal ", status.signal, "\n")); exit(1);
    }
    let actual = process::stdout(child);
    if actual != expected {
        var offset: i64 = 0;
        while offset < min(actual.len, expected.len) && actual[offset] == expected[offset] { offset += 1; }
        diagnostic(str("goose-check: stdout mismatch at byte ", offset,
            "; expected length ", expected.len, ", actual length ", actual.len, "\n")); exit(1);
    }
    if stderr_path.len > 0 && (stderr_offset >= 0 || stderr_count != expected_stderr.len) {
        let offset = if stderr_offset >= 0 { stderr_offset } else { stderr_count };
        diagnostic(str("goose-check: stderr mismatch at byte ", offset,
            "; expected length ", expected_stderr.len, ", actual length ", stderr_count, "\n")); exit(1);
    }
}
