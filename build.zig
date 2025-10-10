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

}
