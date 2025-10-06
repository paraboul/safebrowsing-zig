const std = @import("std");
const HashList = @import("proto/safebrowsing/v5.pb.zig").HashList;
const sha256 = std.crypto.hash.sha2.Sha256;
const BitReader = @import("bitreader.zig");

pub fn Hashes(T: type) type {
    return struct {
        const Self = @This();

        indexedHashes: std.AutoHashMap(T, void),

        hlist : HashList,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, source: *std.Io.Reader) !Self {
            return .{
                .hlist = try HashList.decode(source, allocator),
                .indexedHashes = .init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.hlist.deinit(self.allocator);
            self.indexedHashes.deinit();
        }

        pub fn read(self: *Self) !void {
            try switch(self.hlist.compressed_additions.?) {
                .additions_four_bytes  => |val| {
                    if (T != u32) return error.InvalidHashSize;
                    try self.decompress(val.encoded_data, @intCast(val.entries_count), val.first_value, @intCast(val.rice_parameter));
                },
                .additions_thirty_two_bytes => |val| {
                    if (T != u256) return error.InvalidHashSize;

                    const first_value : u256 = @as(u256, val.first_value_fourth_part) |
                                            @as(u256, val.first_value_third_part) << 64 |
                                            @as(u256, val.first_value_second_part) << 128 |
                                            @as(u256, val.first_value_first_part) << 192;

                    try self.decompress(val.encoded_data, @intCast(val.entries_count), first_value, @intCast(val.rice_parameter));
                },
                else => error.UnsupportedHashSize
            };

            // std.debug.print("size {d}\n", .{res.entries_count});
        }

        fn decompress(self: *Self, data: []const u8, num_entries: u32, initial_value: T, rice: u32) !void {

            var br = BitReader.init(data);

            var prev_value = initial_value;

            try self.indexedHashes.put(initial_value, {});

            for (0..num_entries) |_| {
                const q = br.readUnary();
                const reminder = br.readNBits(T, rice);
                const gap : T = (@as(T, q) << @intCast(rice)) | reminder;

                const new_val = prev_value + gap;
                prev_value = new_val;

                try self.indexedHashes.put(new_val, {});
            }
            std.debug.print("Done indexing {d} entries\n", .{num_entries});
        }
    };
}
