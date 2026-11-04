// SPDX-License-Identifier: Apache-2.0
namespace fs;
import std;

enum Error { None, InvalidInput, LimitExceeded, NotRegular, SystemError }
enum Kind { Unknown, File, Directory, Symlink, Other, Fifo, Socket, CharacterDevice, BlockDevice }
struct Status { error: Error = Error.None, os_error: i64 = 0 }
struct Entry { kind: Kind = Kind.Unknown, name: u8[] }
const MAX_PATH_BYTES = 4095;
const MAX_BYTES = 1048576;
const MAX_ENTRIES = 4096;
// Full staging preserves one-pass behavior; adaptive is an explicit cost tradeoff.
struct ListOptions { byte_limit: i64 = MAX_BYTES, entry_limit: i64 = MAX_ENTRIES, adaptive: bool = false }
extern fn native_call(op: i64, path: const u8[:], data: const u8[:], entries: i64,
                      out: u8[:], meta: i64[:]) -> i64 = "gf_call";
extern fn native_list(path: const u8[:], bytes: i64, out: u8[:], entries: i64, meta: i64[:]) -> i64 = "gf_list";
const LIST_STAGING_BYTES = 65536;

fn valid_components(path: const u8[:], beginning: i64) -> bool {
    var start = beginning;
    for c, i in path {
        if c == 0 { return false; }
        if i >= beginning && c == '/' {
            let n = i - start;
            if n == 0 || (n == 1 && path[start] == '.') ||
                (n == 2 && path[start] == '.' && path[start + 1] == '.') { return false; }
            start = i + 1;
        }
    }
    let n = path.len - start;
    return n > 0 && !(n == 1 && path[start] == '.') &&
        !(n == 2 && path[start] == '.' && path[start + 1] == '.');
}
fn valid_path(path: const u8[:]) -> bool {
    if path.len < 1 || path.len > MAX_PATH_BYTES || path[0] != '/' { return false; }
    return path.len == 1 || valid_components(path, 1);
}
fn valid_relative(path: const u8[:]) -> bool {
    if path.len < 1 || path.len > MAX_PATH_BYTES || path[0] == '/' { return false; }
    return path == "." || valid_components(path, 0);
}

fn status(code: i64, os_error: i64) -> Status {
    let error = if code == 0 { Error.None } else if code == 1 { Error.InvalidInput }
                else if code == 2 { Error.LimitExceeded } else if code == 3 { Error.NotRegular }
                else { Error.SystemError };
    return Status { error: error, os_error: os_error };
}
fn read(path: const u8[:], limit: i64, out: u8[>..]&) -> Status {
    if !valid_path(path) || limit < 0 || limit > MAX_BYTES {
        out.clear();
        return Status { error: Error.InvalidInput };
    }
    // Existing bytes are initialized already. Only growth needs initialization.
    out.resize(limit, 0);
    var meta: i64[3] = [0, 0, 0];
    let code = native_call(0, path, "", 0, out[..], meta[..]);
    if code == 0 { out.resize(meta[1]); } else { out.clear(); }
    return status(code, meta[0]);
}
fn list(path: const u8[:], byte_limit: i64, entry_limit: i64, out: Entry[>..]&) -> Status {
    return list(path, ListOptions { byte_limit: byte_limit, entry_limit: entry_limit }, out);
}
fn list(path: const u8[:], options: ListOptions, out: Entry[>..]&) -> Status {
    let byte_limit = options.byte_limit; let entry_limit = options.entry_limit;
    out.clear();
    if !valid_path(path) || byte_limit < 0 || byte_limit > MAX_BYTES ||
       entry_limit < 0 || entry_limit > MAX_ENTRIES { return Status { error: Error.InvalidInput }; }
    var capacity = if !options.adaptive || byte_limit < LIST_STAGING_BYTES { byte_limit } else { LIST_STAGING_BYTES };
    var packed: u8[>..] = []; packed.resize(capacity, 0);
    var meta:   i64[4]  = [0; 4];
    var code = native_list(path, byte_limit, packed[..], entry_limit, meta[..]);
    while code == 5 && capacity < byte_limit {
        let growth = if capacity * 2 > meta[3] { capacity * 2 } else { meta[3] };
        capacity = if growth < byte_limit { growth } else { byte_limit };
        packed.resize(capacity, 0);
        code = native_list(path, byte_limit, packed[..], entry_limit, meta[..]);
    }
    if code != 0 { return status(if code == 5 { 2 } else { code }, meta[0]); }
    unpack_entries(packed[..meta[1]], meta[2], out);
    return Status { .. };
}
fn unpack_entries(packed: const u8[:], count: i64, out: Entry[>..]&) {
    var pos: i64 = 0;
    for _ in count {
        let tag = packed[pos]; pos++;
        let kind = if tag == 1 { Kind.File } else if tag == 2 { Kind.Directory }
                   else if tag == 3 { Kind.Symlink } else if tag == 4 { Kind.Other } else { Kind.Unknown };
        let start = pos;
        while pos < packed.len && packed[pos] != 0 { pos++; }
        out.push(Entry { kind: kind, name: owned_name(packed[start..pos]) });
        pos++;
    }
}
fn mutate(op: i64, path: const u8[:], data: const u8[:]) -> Status {
    if !valid_path(path) || path.len == 1 || data.len > MAX_BYTES { return Status { error: Error.InvalidInput }; }
    var meta:   i64[3] = [0, 0, 0];
    var unused: u8[0]  = [];
    let code = native_call(op, path, data, 0, unused[..], meta[..]);
    return status(code, meta[0]);
}
fn create_file(path: const u8[:], data: const u8[:]) -> Status { return mutate(2, path, data); }
fn create_dir(path: const u8[:]) -> Status { return mutate(3, path, ""); }
fn remove_file(path: const u8[:]) -> Status { return mutate(4, path, ""); }
fn remove_empty_dir(path: const u8[:]) -> Status { return mutate(5, path, ""); }

fn owned_name(source: const u8[:]) -> u8[] {
    var result: u8[>..] = [];
    result.append(source);
    return result;
}

struct Timestamp { seconds: i64 = 0, nanoseconds: i64 = 0 }
struct Metadata {
    kind:              Kind      = Kind.Unknown,
    size:              u64       = 0,
    permissions:       u32       = 0,
    uid:               u32       = 0,
    gid:               u32       = 0,
    device:            u64       = 0,
    inode:             u64       = 0,
    links:             u64       = 0,
    accessed:          Timestamp = Timestamp { .. },
    modified:          Timestamp = Timestamp { .. },
    changed:           Timestamp = Timestamp { .. },
    created:           Timestamp = Timestamp { .. },
    created_available: bool      = false,
}
extern fn native_metadata(path: const u8[:], fields: i64[:]) -> i64 = "gf_metadata";
extern fn native_missing(os_error: i64) -> bool = "gf_missing";

// Inspect the final entry itself; never follow a final or ancestor symlink.
fn metadata(path: const u8[:], out: Metadata&) -> Status {
    out = Metadata { .. };
    if !valid_path(path) { return Status { error: Error.InvalidInput }; }
    var fields: i64[18] = [0; 18];
    let code = native_metadata(path, fields[..]);
    if code != 0 { return status(code, fields[0]); }
    out = decode_metadata(fields[..]);
    return Status { .. };
}
fn decode_metadata(fields: const i64[:]) -> Metadata {
    let kind = if fields[1] == 1 { Kind.File } else if fields[1] == 2 { Kind.Directory }
               else if fields[1] == 3 { Kind.Symlink } else if fields[1] == 5 { Kind.Fifo }
               else if fields[1] == 6 { Kind.Socket } else if fields[1] == 7 { Kind.CharacterDevice }
               else if fields[1] == 8 { Kind.BlockDevice } else { Kind.Other };
    return Metadata { kind: kind, size: fields[2] as! u64, permissions: fields[3] as! u32,
        uid:      fields[4] as! u32, gid: fields[5] as! u32, device: fields[6] as! u64,
        inode:    fields[7] as! u64, links: fields[8] as! u64,
        accessed: Timestamp { fields[9], fields[10] }, modified: Timestamp { fields[11], fields[12] },
        changed:  Timestamp { fields[13], fields[14] }, created: Timestamp { fields[15], fields[16] },
        created_available: fields[17] != 0 };
}
fn exists(path: const u8[:]) -> bool, Status {
    var info = Metadata { .. };
    let result = metadata(path, info);
    if result.error == Error.SystemError && native_missing(result.os_error) { return false, Status { .. }; }
    return result.error == Error.None, result;
}
fn is_dir(path: const u8[:]) -> bool, Status {
    var info = Metadata { .. };
    let result = metadata(path, info);
    if result.error == Error.SystemError && native_missing(result.os_error) { return false, Status { .. }; }
    return result.error == Error.None && info.kind == Kind.Directory, result;
}
fn name_before(a: const u8[:], b: const u8[:]) -> bool {
    var i: i64 = 0;
    while i < a.len && i < b.len {
        if a[i] != b[i] { return a[i] < b[i]; }
        i++;
    }
    return a.len < b.len;
}
fn list_sorted(path: const u8[:], byte_limit: i64, entry_limit: i64, out: Entry[>..]&) -> Status {
    return list_sorted(path, ListOptions { byte_limit: byte_limit, entry_limit: entry_limit }, out);
}
fn list_sorted(path: const u8[:], options: ListOptions, out: Entry[>..]&) -> Status {
    out.clear();
    var entries: Entry[>..] = [];
    let result = list(path, options, entries);
    if result.error != Error.None { return result; }
    var order: (const Entry&)[>..] = [];
    for entry in entries { order.push(entry); }
    sort_entries(order);
    for entry in order { out.push(Entry { kind: entry.kind, name: owned_name(entry.name) }); }
    return Status { .. };
}

fn swap_entries(order: (const Entry&)[:], a: i64, b: i64) {
    let saved: const Entry& = order[a];
    order[a] .= order[b];
    order[b] .= saved;
}
fn sift_entries(order: (const Entry&)[:], start: i64, end: i64) {
    var root = start;
    while root * 2 + 1 < end {
        var child = root * 2 + 1;
        if child + 1 < end && name_before(order[child].name, order[child + 1].name) { child++; }
        if !name_before(order[root].name, order[child].name) { break; }
        swap_entries(order, root, child); root = child;
    }
}
fn sort_entries(order: (const Entry&)[:]) {
    var root = order.len / 2;
    while root > 0 { root--; sift_entries(order, root, order.len); }
    var end = order.len;
    while end > 1 { end--; swap_entries(order, 0, end); sift_entries(order, 0, end); }
}

// Tokens own no Goose storage. Copies alias lifetime and the shared file cursor.
struct Context { id: i64 = 0 }
struct File { context: Context = Context { .. }, id: i64 = 0 }
const MAX_CONTEXTS = 64;
const MAX_RESOURCES = 4096;
const MAX_FILES = MAX_RESOURCES;
enum Access { Read, Write, ReadWrite }
enum Creation { Existing, CreateNew, OpenOrCreate }
enum SeekOrigin { Start, Current, End }
struct OpenOptions {
    access:      Access   = Access.Read,
    creation:    Creation = Creation.Existing,
    append:      bool     = false,
    truncate:    bool     = false,
    permissions: u32      = 384,
}
struct IOResult { status: Status = Status { .. }, bytes: i64 = 0, eof: bool = false }
extern fn native_context_create(meta: i64[:]) -> i64 = "gf_context_create";
extern fn native_context_close(context: i64, meta: i64[:]) -> i64 = "gf_context_close";
extern fn native_file_open(context: i64, path: const u8[:], options: i64, permissions: i64, meta: i64[:]) -> i64 = "gf_file_open";
extern fn native_file_close(context: i64, file: i64, meta: i64[:]) -> i64 = "gf_file_close";
extern fn native_file_read(context: i64, file: i64, out: u8[:], offset: i64, positioned: bool, meta: i64[:]) -> i64 = "gf_file_read";
extern fn native_file_write(context: i64, file: i64, data: const u8[:], offset: i64, positioned: bool, all: bool, meta: i64[:]) -> i64 = "gf_file_write";
extern fn native_file_seek(context: i64, file: i64, offset: i64, origin: i64, meta: i64[:]) -> i64 = "gf_file_seek";
extern fn native_file_truncate(context: i64, file: i64, size: i64, meta: i64[:]) -> i64 = "gf_file_truncate";
extern fn native_file_sync(context: i64, file: i64, data_only: bool, meta: i64[:]) -> i64 = "gf_file_sync";
extern fn native_file_metadata(context: i64, file: i64, fields: i64[:]) -> i64 = "gf_file_metadata";
extern fn native_file_duplicate(context: i64, file: i64, meta: i64[:]) -> i64 = "gf_file_duplicate";
fn create_context() -> Context, Status {
    var meta: i64[3] = [0; 3];
    let code = native_context_create(meta[..]);
    return Context { id: meta[1] }, status(code, meta[0]);
}
fn close_context(context: Context) -> Status {
    var meta: i64[3] = [0; 3];
    let code = native_context_close(context.id, meta[..]);
    return status(code, meta[0]);
}
fn option_bits(options: OpenOptions) -> i64 {
    if options.permissions > 511 ||
        (options.access != Access.Read && options.access != Access.Write && options.access != Access.ReadWrite) ||
        (options.creation != Creation.Existing && options.creation != Creation.CreateNew && options.creation != Creation.OpenOrCreate) ||
        (options.access == Access.Read && (options.append || options.truncate)) {
        return -1;
    }
    let access:   i64 = if options.access == Access.Read { 0 } else if options.access == Access.Write { 1 } else { 2 };
    let creation: i64 = if options.creation == Creation.Existing { 0 } else if options.creation == Creation.CreateNew { 4 } else { 8 };
    return access + creation + (if options.append { 16 } else { 0 }) + (if options.truncate { 32 } else { 0 });
}
fn open_file(context: Context, path: const u8[:], options: OpenOptions) -> File, Status {
    let flags = option_bits(options);
    if !valid_path(path) || flags < 0 { return File { .. }, Status { error: Error.InvalidInput }; }
    var meta: i64[3] = [0; 3];
    let code = native_file_open(context.id, path, flags, options.permissions, meta[..]);
    let file = if code == 0 { File { context: context, id: meta[1] } } else { File { .. } };
    return file, status(code, meta[0]);
}

fn close_file(file: File) -> Status {
    var meta: i64[3] = [0; 3];
    let code = native_file_close(file.context.id, file.id, meta[..]);
    return status(code, meta[0]);
}
fn duplicate_file(file: File) -> File, Status {
    var meta: i64[3] = [0; 3];
    let code = native_file_duplicate(file.context.id, file.id, meta[..]);
    let copy = if code == 0 { File { context: file.context, id: meta[1] } } else { File { .. } };
    return copy, status(code, meta[0]);
}
fn file_read(file: File, offset: i64, limit: i64, positioned: bool, out: u8[>..]&) -> IOResult {
    if limit < 0 || limit > MAX_BYTES || (positioned && (offset < 0 || offset > 9223372036854775807 - limit)) {
        out.clear();
        return IOResult { status: Status { error: Error.InvalidInput } };
    }
    out.resize(limit, 0);
    var meta: i64[3] = [0; 3];
    let code = native_file_read(file.context.id, file.id, out[..], offset, positioned, meta[..]);
    if code == 0 { out.resize(meta[1]); } else { out.clear(); }
    return IOResult { status: status(code, meta[0]), bytes: meta[1], eof: code == 0 && meta[2] != 0 };
}
fn read_some(file: File, limit: i64, out: u8[>..]&) -> IOResult { return file_read(file, 0, limit, false, out); }
fn read_at(file: File, offset: i64, limit: i64, out: u8[>..]&) -> IOResult { return file_read(file, offset, limit, true, out); }
fn file_write(file: File, data: const u8[:], offset: i64, positioned: bool, all: bool) -> IOResult {
    if data.len > MAX_BYTES || (positioned && (offset < 0 || offset > 9223372036854775807 - data.len)) {
        return IOResult { status: Status { error: Error.InvalidInput } };
    }
    var meta: i64[3] = [0; 3];
    let code = native_file_write(file.context.id, file.id, data, offset, positioned, all, meta[..]);
    return IOResult { status: status(code, meta[0]), bytes: meta[1] };
}
fn write_some(file: File, data: const u8[:]) -> IOResult { return file_write(file, data, 0, false, false); }
fn write_all(file: File, data: const u8[:]) -> IOResult { return file_write(file, data, 0, false, true); }
fn write_at(file: File, offset: i64, data: const u8[:]) -> IOResult { return file_write(file, data, offset, true, false); }
fn seek(file: File, offset: i64, origin: SeekOrigin) -> i64, Status {
    if origin != SeekOrigin.Start && origin != SeekOrigin.Current && origin != SeekOrigin.End {
        return 0, Status { error: Error.InvalidInput };
    }
    let whence: i64 = if origin == SeekOrigin.Start { 0 } else if origin == SeekOrigin.Current { 1 } else { 2 };
    var meta: i64[3] = [0; 3];
    let code = native_file_seek(file.context.id, file.id, offset, whence, meta[..]);
    return meta[1], status(code, meta[0]);
}
fn truncate_file(file: File, size: i64) -> Status {
    var meta: i64[3] = [0; 3];
    let code = native_file_truncate(file.context.id, file.id, size, meta[..]);
    return status(code, meta[0]);
}
fn sync_file(file: File, data_only: bool) -> Status {
    var meta: i64[3] = [0; 3];
    let code = native_file_sync(file.context.id, file.id, data_only, meta[..]);
    return status(code, meta[0]);
}
fn file_metadata(file: File, out: Metadata&) -> Status {
    out = Metadata { .. };
    var fields: i64[18] = [0; 18];
    let code = native_file_metadata(file.context.id, file.id, fields[..]);
    if code != 0 { return status(code, fields[0]); }
    out = decode_metadata(fields[..]);
    return Status { .. };
}

enum LockMode { Shared, Exclusive }
extern fn native_file_try_lock(context: i64, file: i64, mode: i64, meta: i64[:]) -> i64 = "gf_file_try_lock";
extern fn native_lock_contended(os_error: i64) -> bool = "gf_lock_contended";
extern fn native_lock_pause() -> i64 = "gf_lock_pause";
fn try_lock_file(file: File, mode: LockMode) -> bool, Status {
    if mode != LockMode.Shared && mode != LockMode.Exclusive {
        return false, Status { error: Error.InvalidInput };
    }
    let operation: i64 = if mode == LockMode.Shared { 1 } else { 2 };
    var meta: i64[3] = [0; 3];
    let code = native_file_try_lock(file.context.id, file.id, operation, meta[..]);
    if code == 4 && native_lock_contended(meta[0]) { return false, Status { .. }; }
    return code == 0, status(code, meta[0]);
}
fn lock_file(file: File, mode: LockMode) -> Status {
    let first, initial = try_lock_file(file, mode);
    var acquired = first;
    var result = initial;
    while !acquired && result.error == Error.None {
        let pause_error = native_lock_pause();
        if pause_error != 0 { return Status { error: Error.SystemError, os_error: pause_error }; }
        let next, attempt = try_lock_file(file, mode);
        acquired = next; result = attempt;
    }
    return result;
}
fn unlock_file(file: File) -> Status {
    var meta: i64[3] = [0; 3];
    let code = native_file_try_lock(file.context.id, file.id, 0, meta[..]);
    return status(code, meta[0]);
}

struct Root { context: Context = Context { .. }, id: i64 = 0 }
extern fn native_root_open(context: i64, path: const u8[:], meta: i64[:]) -> i64 = "gf_root_open";
extern fn native_root_open_at(context: i64, root: i64, path: const u8[:], meta: i64[:]) -> i64 = "gf_root_open_at";
extern fn native_file_open_at(context: i64, root: i64, path: const u8[:], options: i64, permissions: i64, meta: i64[:]) -> i64 = "gf_file_open_at";
extern fn native_root_close(context: i64, root: i64, meta: i64[:]) -> i64 = "gf_root_close";
extern fn native_root_metadata(context: i64, root: i64, fields: i64[:]) -> i64 = "gf_root_metadata";
extern fn native_root_metadata_at(context: i64, root: i64, path: const u8[:], fields: i64[:]) -> i64 = "gf_root_metadata_at";
extern fn native_root_read(context: i64, root: i64, path: const u8[:], out: u8[:], meta: i64[:]) -> i64 = "gf_root_read";
extern fn native_root_list(context: i64, root: i64, path: const u8[:], bytes: i64, out: u8[:], entries: i64, meta: i64[:]) -> i64 = "gf_root_list_sized";
extern fn native_root_create(context: i64, root: i64, path: const u8[:], data: const u8[:], meta: i64[:]) -> i64 = "gf_root_create";
extern fn native_root_mkdir(context: i64, root: i64, path: const u8[:], meta: i64[:]) -> i64 = "gf_root_mkdir";
extern fn native_root_unlink(context: i64, root: i64, path: const u8[:], directory: bool, meta: i64[:]) -> i64 = "gf_root_unlink";
fn open_root(context: Context, path: const u8[:]) -> Root, Status {
    if !valid_path(path) { return Root { .. }, Status { error: Error.InvalidInput }; }
    var meta: i64[3] = [0; 3];
    let code = native_root_open(context.id, path, meta[..]);
    let root = if code == 0 { Root { context: context, id: meta[1] } } else { Root { .. } };
    return root, status(code, meta[0]);
}
fn open_root_at(root: Root, path: const u8[:]) -> Root, Status {
    if !valid_relative(path) { return Root { .. }, Status { error: Error.InvalidInput }; }
    var meta: i64[3] = [0; 3];
    let code = native_root_open_at(root.context.id, root.id, path, meta[..]);
    let child = if code == 0 { Root { context: root.context, id: meta[1] } } else { Root { .. } };
    return child, status(code, meta[0]);
}
fn open_file_at(root: Root, path: const u8[:], options: OpenOptions) -> File, Status {
    let flags = option_bits(options);
    if !valid_relative(path) || flags < 0 || (path == "." && flags != 0) {
        return File { .. }, Status { error: Error.InvalidInput };
    }
    var meta: i64[3] = [0; 3];
    let code = native_file_open_at(root.context.id, root.id, path, flags, options.permissions, meta[..]);
    let file = if code == 0 { File { context: root.context, id: meta[1] } } else { File { .. } };
    return file, status(code, meta[0]);
}
fn close_root(root: Root) -> Status {
    var meta: i64[3] = [0; 3];
    let code = native_root_close(root.context.id, root.id, meta[..]);
    return status(code, meta[0]);
}
fn root_metadata(root: Root, out: Metadata&) -> Status {
    out = Metadata { .. };
    var fields: i64[18] = [0; 18];
    let code = native_root_metadata(root.context.id, root.id, fields[..]);
    if code != 0 { return status(code, fields[0]); }
    out = decode_metadata(fields[..]);
    return Status { .. };
}
fn metadata_at(root: Root, path: const u8[:], out: Metadata&) -> Status {
    out = Metadata { .. };
    if !valid_relative(path) { return Status { error: Error.InvalidInput }; }
    var fields: i64[18] = [0; 18];
    let code = native_root_metadata_at(root.context.id, root.id, path, fields[..]);
    if code != 0 { return status(code, fields[0]); }
    out = decode_metadata(fields[..]);
    return Status { .. };
}
fn read_file_at(root: Root, path: const u8[:], limit: i64, out: u8[>..]&) -> Status {
    if !valid_relative(path) || limit < 0 || limit > MAX_BYTES {
        out.clear(); return Status { error: Error.InvalidInput };
    }
    out.resize(limit, 0);
    var meta: i64[3] = [0; 3];
    let code = native_root_read(root.context.id, root.id, path, out[..], meta[..]);
    if code == 0 { out.resize(meta[1]); } else { out.clear(); }
    return status(code, meta[0]);
}
fn list_at(root: Root, path: const u8[:], byte_limit: i64, entry_limit: i64, out: Entry[>..]&) -> Status {
    return list_at(root, path, ListOptions { byte_limit: byte_limit, entry_limit: entry_limit }, out);
}
fn list_at(root: Root, path: const u8[:], options: ListOptions, out: Entry[>..]&) -> Status {
    let byte_limit = options.byte_limit; let entry_limit = options.entry_limit;
    out.clear();
    if !valid_relative(path) || byte_limit < 0 || byte_limit > MAX_BYTES ||
        entry_limit < 0 || entry_limit > MAX_ENTRIES { return Status { error: Error.InvalidInput }; }
    var capacity = if !options.adaptive || byte_limit < LIST_STAGING_BYTES { byte_limit } else { LIST_STAGING_BYTES };
    var packed: u8[>..] = []; packed.resize(capacity, 0);
    var meta:   i64[4]  = [0; 4];
    var code = native_root_list(root.context.id, root.id, path, byte_limit, packed[..], entry_limit, meta[..]);
    while code == 5 && capacity < byte_limit {
        let growth = if capacity * 2 > meta[3] { capacity * 2 } else { meta[3] };
        capacity = if growth < byte_limit { growth } else { byte_limit };
        packed.resize(capacity, 0);
        code = native_root_list(root.context.id, root.id, path, byte_limit, packed[..], entry_limit, meta[..]);
    }
    if code != 0 { return status(if code == 5 { 2 } else { code }, meta[0]); }
    unpack_entries(packed[..meta[1]], meta[2], out);
    return Status { .. };
}
fn list_sorted_at(root: Root, path: const u8[:], byte_limit: i64, entry_limit: i64, out: Entry[>..]&) -> Status {
    return list_sorted_at(root, path, ListOptions { byte_limit: byte_limit, entry_limit: entry_limit }, out);
}
fn list_sorted_at(root: Root, path: const u8[:], options: ListOptions, out: Entry[>..]&) -> Status {
    out.clear();
    var entries: Entry[>..] = [];
    let result = list_at(root, path, options, entries);
    if result.error != Error.None { return result; }
    var order: (const Entry&)[>..] = [];
    for entry in entries { order.push(entry); }
    sort_entries(order);
    for entry in order { out.push(Entry { kind: entry.kind, name: owned_name(entry.name) }); }
    return Status { .. };
}
fn create_file_at(root: Root, path: const u8[:], data: const u8[:]) -> Status {
    if !valid_relative(path) || path == "." || data.len > MAX_BYTES { return Status { error: Error.InvalidInput }; }
    var meta: i64[3] = [0; 3];
    let code = native_root_create(root.context.id, root.id, path, data, meta[..]);
    return status(code, meta[0]);
}
fn create_dir_at(root: Root, path: const u8[:]) -> Status {
    if !valid_relative(path) || path == "." { return Status { error: Error.InvalidInput }; }
    var meta: i64[3] = [0; 3];
    let code = native_root_mkdir(root.context.id, root.id, path, meta[..]);
    return status(code, meta[0]);
}
fn remove_at(root: Root, path: const u8[:], directory: bool) -> Status {
    if !valid_relative(path) || path == "." { return Status { error: Error.InvalidInput }; }
    var meta: i64[3] = [0; 3];
    let code = native_root_unlink(root.context.id, root.id, path, directory, meta[..]);
    return status(code, meta[0]);
}
fn remove_file_at(root: Root, path: const u8[:]) -> Status { return remove_at(root, path, false); }
fn remove_empty_dir_at(root: Root, path: const u8[:]) -> Status { return remove_at(root, path, true); }
