const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "main",
        .root_module = std.Build.Module.create(b, .{
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.addCSourceFiles(.{
        .root = b.path("."),
        .files = &[_][]const u8{"src/main.c"},
        .flags = &[_][]const u8 {"-std=c23","-Wall","-Wextra","-gen-cdb-fragment-path","cdb-frags"},
    });
    exe.linkLibC();

    b.installArtifact(exe);

    const cdb_step = b.step("cbd", "Compile CDB fragments into compile_commands.json");
    cdb_step.makeFn = collect_cdb_fragments;
    cdb_step.dependOn(&exe.step);
    b.getInstallStep().dependOn(cdb_step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run","Run program");
    run_step.dependOn(&run_cmd.step);
}

fn collect_cdb_fragments(_: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
    const outf = try std.fs.cwd().createFile("compile_commands.json", .{});
    defer outf.close();

    var dir = std.fs.cwd().openDir("cdb-frags", .{.iterate = true}) catch {
        std.debug.print("Failed to open ./cdb-frags/", .{});
        return;
    };
    defer dir.close();

    try outf.writeAll("[");
    var iter = dir.iterate();
    while(try iter.next()) |entry| {
        const fpath = try std.fmt.allocPrint(
            std.heap.page_allocator, "cdb-frags/{s}", .{entry.name}
        );
        const contents = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, fpath, 1024*1024);
        try outf.seekFromEnd(0);
        try outf.writeAll(contents);
    }
    try outf.writeAll("]");

}
