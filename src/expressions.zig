const std = @import("std");
var public_suffix : std.StringHashMapUnmanaged(void) = .empty;
const sha256 = std.crypto.hash.sha2.Sha256;

pub fn getURLPrefix(url: []const u8) u32 {
    var outhash : [sha256.digest_length]u8 = undefined;

    sha256.hash(url, &outhash, .{});
    return std.mem.readInt(u32, outhash[0..4], .big);
}

pub fn getURLPrefixBase64(url: []const u8, dest: []u8, truncate: u8) [] const u8 {
    var outhash : [sha256.digest_length]u8 = undefined;

    sha256.hash(url, &outhash, .{});

    return std.base64.url_safe_no_pad.Encoder.encode(dest, outhash[0..truncate]);
}

pub fn getURLHash(url: []const u8) u256 {
    var outhash : [sha256.digest_length]u8 = undefined;

    sha256.hash(url, &outhash, .{});
    return std.mem.readInt(u256, outhash[0..32], .big);
}

pub fn index_public_suffix(alloc: std.mem.Allocator) !void {
    const public_suffix_file = try std.fs.cwd().openFile("./data/public_suffix_list.txt", .{ .mode = .read_only });
    defer public_suffix_file.close();

    var buf: [256]u8 = undefined;
    var file_reader = public_suffix_file.readerStreaming(&buf);

    while (file_reader.interface.takeDelimiterExclusive('\n')) |line| {
        if (std.mem.startsWith(u8, line, "//") or line.len == 0) {
            continue;
        }
        try public_suffix.put(alloc, try alloc.dupe(u8, line), {});

    } else |err| switch (err) {
        error.EndOfStream => {},
        else => |e| return e,
    }
}


fn path_prefix(alloc: std.mem.Allocator, path: []const u8, out: *std.ArrayList([]const u8)) !void {
    var current = path;

    try out.append(alloc, path);

    while (true) {
        if (std.fs.path.dirnamePosix(current)) |subdir| {
            try out.append(alloc, subdir);
            current = subdir;
        } else {
            break;
        }
    }
}

fn host_suffix(alloc: std.mem.Allocator, host: []const u8, out: *std.ArrayList([]const u8)) !void {
    var parts = std.mem.splitScalar(u8, host, '.');
    var tld : [] const u8 = host;

    while (true) : (_ = parts.next()) {

        const rest = parts.rest();
        if (rest.len == 0) {
            break;
        }

        if (public_suffix.get(rest) != null) {
            tld = rest;
            break;
        }
    }

    parts.reset();

    while (true) : (_ = parts.next()) {
        const rest = parts.rest();

        if (rest.ptr == tld.ptr) {
            break;
        }

        try out.append(alloc, rest);
    }
}

fn get_path_and_query(uri: *const std.Uri, buf: []u8) !?[] const u8 {
    if (uri.query == null) {
        return null;
    }

    var fwriter : std.io.Writer = .fixed(buf);
    const t = uri.fmt(.{ .authority = false, .port = false, .path = true, .query = true });
    try t.format(&fwriter);
    try fwriter.flush();

    return buf[0..fwriter.end];
}

pub fn gen_variations(alloc: std.mem.Allocator, fullurl: [] const u8) !std.ArrayList([] const u8) {
    var all_variations : std.ArrayList([] const u8) = .empty;

    var hosts : std.ArrayList([] const u8) = .empty;
    var paths : std.ArrayList([] const u8) = .empty;

    const uri = try std.Uri.parse(fullurl);
    var buf : [std.Uri.host_name_max]u8 = undefined;

    const origin = try uri.getHost(&buf);

    try host_suffix(alloc, origin, &hosts);
    try path_prefix(alloc, uri.path.percent_encoded, &paths);

    var fullpath : [2048]u8 = undefined;
    const path_and_query = try get_path_and_query(&uri, &fullpath);

    for (hosts.items) |host| {
        if (path_and_query) |pq| {
            try all_variations.append(alloc, try std.fmt.allocPrint(alloc, "{s}{s}", .{host, pq}));
        }

        for (paths.items) |path| {
            try all_variations.append(alloc, try std.fmt.allocPrint(alloc, "{s}{s}", .{host, path}));
        }
    }

    return all_variations;
}
