const std = @import("std");
const builtin = @import("builtin");
const hashlist = @import("proto/safebrowsing/v5.pb.zig").HashList;
const sha256 = std.crypto.hash.sha2.Sha256;
const HashDecoder = @import("hashes.zig");
const expressions = @import("expressions.zig");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

fn get_global_cache_index(allocator: std.mem.Allocator) !HashDecoder.Hashes(u256) {
    var r: std.Io.Reader = .fixed(@embedFile("./lists/gc-32b.bin"));
    var index = try HashDecoder.Hashes(u256).init(allocator, &r);
    try index.read();

    return index;
}

fn get_threats_index(allocator: std.mem.Allocator) !HashDecoder.Hashes(u32) {
    var r: std.Io.Reader = .fixed(@embedFile("./lists/se-4b.bin"));
    var index = try HashDecoder.Hashes(u32).init(allocator, &r);
    try index.read();

    return index;
}

pub fn main() !void {
    const gpa, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        std.debug.print("[allocator cleanup]\n", .{});
        _ = debug_allocator.deinit();
    };

    var arena : std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();

    try expressions.index_public_suffix(arena.allocator());

    var globalCache = try get_global_cache_index(gpa);
    defer globalCache.deinit();

    var socialIndex = try get_threats_index(gpa);
    defer socialIndex.deinit();

    const cwd = std.fs.cwd();
    const file = try cwd.openFile("./output051025_uniq.txt", .{ .mode = .read_only });
    defer file.close();
    var buf: [2048]u8 = undefined;

    var file_reader = file.readerStreaming(&buf);

    var tmp : std.heap.ArenaAllocator = .init(gpa);
    defer tmp.deinit();

    while (file_reader.interface.takeDelimiterExclusive('\n')) |line| {

        defer _ = tmp.reset(.retain_capacity);

        const variations = expressions.gen_variations(tmp.allocator(), line) catch {
            std.debug.print("Failed {s}\n", .{line});
            continue;
        };

        const safe = blk: {
            for (variations.items) |variation| {
                if (globalCache.indexedHashes.contains(expressions.getURLHash(variation))) {
                    break :blk true;
                }
            }
            break :blk false;
        };

        // One of the expression was found in the global cache (safe)
        if (safe) {
            continue;
        }

        const unsafe : ?[] const u8 = blk: {
            for (variations.items) |variation| {
                if (socialIndex.indexedHashes.contains(expressions.getURLPrefix(variation))) {
                    break :blk variation;
                }
            }
            break :blk null;
        };

        if (unsafe) |unsafe_url| {
            std.debug.print("Unsafe {s}\n", .{unsafe_url});
            // Prefix was found in the threat list. Needs to be checked against the online endpoint
        }

    } else |err| switch (err) {
        error.EndOfStream => {},
        else => |e| return e,
    }

}
