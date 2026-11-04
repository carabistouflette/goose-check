// SPDX-License-Identifier: Apache-2.0
// Application-owned opt-in defaults; process and fixture policy stays in main.
namespace settings;
import config;
import config.json_layer;
import config.toml;
import fs;
import process;
import std;

const MAX_FILE_BYTES = 65536;
enum Error { None, Invalid, Read }
struct Limits { expected_exit: i64 = 0, timeout_ms: i64 = 30000, output_limit: i64 = 65536 }
fn json_path(path: const u8[:]) -> bool { path.len >= 5 && path[path.len - 5..] == ".json" }
fn valid_path(path: const u8[:]) -> bool {
    fs::valid_path(path) && (json_path(path) || (path.len >= 5 && path[path.len - 5..] == ".toml"))
}
fn load(path: const u8[:], overrides: config::Override[:], out: Limits&) -> Error {
    if !valid_path(path) { return Error.Invalid; }
    var document: u8[>..] = [];
    if fs::read(path, MAX_FILE_BYTES, document).error != fs::Error.None { return Error.Read; }
    let schema = [config::Field { key: "expect_exit", kind: config::Kind.Integer, required: true, int_min: 0, int_max: 255 },
                  config::Field { key: "timeout_ms", kind: config::Kind.Integer, required: true, int_min: 1, int_max: process::MAX_TIMEOUT_MS },
                  config::Field { key: "output_limit", kind: config::Kind.Integer, required: true, int_min: 0, int_max: process::MAX_OUTPUT_BYTES }];
    let defaults = [config::Override { "expect_exit", "0", "defaults" },
                    config::Override { "timeout_ms", "30000", "defaults" },
                    config::Override { "output_limit", "65536", "defaults" }];
    var store = config::Store { .. };
    if config::init(schema, store).len > 0 || config::apply(store, defaults).len > 0 { return Error.Invalid; }
    let error = if json_path(path) { config::apply_json(store, document, "config.json") }
                else { config::apply_toml(store, document, "config.toml") };
    // Invalid lower layers cannot be repaired by command-line overrides.
    if error.len > 0 || config::apply(store, overrides).len > 0 || config::validate(store).len > 0 { return Error.Invalid; }
    let expected_exit, ee = config::get_integer(store, "expect_exit");
    let timeout_ms, te = config::get_integer(store, "timeout_ms");
    let output_limit, oe = config::get_integer(store, "output_limit");
    if ee.len > 0 || te.len > 0 || oe.len > 0 { return Error.Invalid; }
    // All values are scalars; nothing borrows the local Store on return.
    out.expected_exit = expected_exit; out.timeout_ms = timeout_ms; out.output_limit = output_limit;
    Error.None
}
