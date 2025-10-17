const std = @import("std");
const protobuf = @import("protobuf");


pub fn build(b: *std.Build) void {

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "safebrowsing_zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{

            },
        }),
    });

    exe.root_module.addAnonymousImport("public_suffix_list.txt", .{
        .root_source_file = b.path("data/public_suffix_list.txt")
    });

    const clap = b.dependency("clap", .{});
    exe.root_module.addImport("clap", clap.module("clap"));

    const protobuf_dep = b.dependency("protobuf", .{
           .target = target,
           .optimize = optimize,
       });

    exe.root_module.addImport("protobuf", protobuf_dep.module("protobuf"));

    b.installArtifact(exe);

    const gen_proto = b.step("gen-proto", "generates zig files from protocol buffer definitions");
    const protoc_step = protobuf.RunProtocStep.create(b, protobuf_dep.builder, target, .{
           // out directory for the generated zig files
           .destination_directory = b.path("src/proto"),
           .source_files = &.{
               "protocol/safebrowsing.proto",
           },
           .include_directories = &.{},
       });

    gen_proto.dependOn(&protoc_step.step);

    const module = createPublicSuffixHash(b) catch @panic("Error");
    exe.root_module.addImport("generated_data", module);

}

fn createPublicSuffixHash(b: *std.Build) !*std.Build.Module {
    const write_files = b.addWriteFiles();

    var transform : std.ArrayList(u8) = .empty;
    defer transform.deinit(b.allocator);

    var cwd = std.fs.cwd();
    const content = try cwd.readFileAlloc(b.allocator, "data/public_suffix_list.txt", 1024*1024);

    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "//") or line.len == 0) {
            continue;
        }

        try transform.appendSlice(b.allocator, b.fmt(".{{ \"{s}\" }},\n", .{line}));
    }

    const genfile =
        \\const std = @import("std");
        \\
        \\pub const psh = std.StaticStringMap(void).initComptime(.{{ {s} }});
    ;

    const p = write_files.add("gen.zig", b.fmt(genfile, .{transform.items}));

    return b.addModule("generated_data", .{
        .root_source_file = p,
    });
}
