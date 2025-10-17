const std = @import("std");
const builtin = @import("builtin");
const hashlist = @import("proto/safebrowsing/v5.pb.zig").HashList;
const sha256 = std.crypto.hash.sha2.Sha256;
const HashDecoder = @import("hashes.zig");
const expressions = @import("expressions.zig");
const clap = @import("clap");


var debug_allocator: std.heap.DebugAllocator(.{}) = .init;


fn get_hashes_index(bytes_size: type, allocator: std.mem.Allocator, filename: [] const u8) !HashDecoder.Hashes(bytes_size) {
    const file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer file.close();

    var buf: [2048]u8 = undefined;
    var file_reader = file.readerStreaming(&buf);

    var index = try HashDecoder.Hashes(bytes_size).init(allocator, &file_reader.interface);
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

    const params = comptime clap.parseParamsComptime(
           \\-h, --help               Display this help and exit.
           \\-g, --globalcache <str>  Global cache database file.
           \\-t, --threatslist <str>  Threats list database file.
           \\-u, --urls <str>         A URLs list file.
           \\-o, --output <str>       Output results into file
    );
    var diag = clap.Diagnostic{};

    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
           .diagnostic = &diag,
           .allocator = gpa,
       }) catch |err| {
           try diag.reportToFile(.stderr(), err);
           return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return clap.helpToFile(.stderr(), clap.Help, &params, .{});
    }
    if (res.args.globalcache == null) {
        return try diag.reportToFile(.stderr(), error.GlobalCacheMissing);
    }
    if (res.args.threatslist == null) {
        return try diag.reportToFile(.stderr(), error.ThreatsListMissing);
    }


    var arena : std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();

    var globalCache = try get_hashes_index(u256, gpa, res.args.globalcache.?);
    defer globalCache.deinit();

    var threatsIndex = try get_hashes_index(u32, gpa, res.args.threatslist.?);
    defer threatsIndex.deinit();

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
                if (threatsIndex.indexedHashes.contains(expressions.getURLPrefix(variation))) {
                    break :blk variation;
                }
            }
            break :blk null;
        };

        if (false) {
            if (unsafe) |unsafe_url| {
                var out : [16] u8 = undefined;
                var out2 : [64] u8 = undefined;
                const b64 = expressions.getURLPrefixBase64(unsafe_url, &out, 4);
                const b64_full = expressions.getURLPrefixBase64(unsafe_url, &out2, 32);

                std.debug.print("{s}\t{s}\t{s}\n", .{b64, b64_full, unsafe_url});
                // Prefix was found in the threat list. Needs to be checked against the online endpoint
            }
        }

    } else |err| switch (err) {
        error.EndOfStream => {},
        else => |e| return e,
    }

}
