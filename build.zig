const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "main",
        .root_module = std.Build.Module.create(b, .{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
        .linkage = .dynamic,
    });

    exe.root_module.addIncludePath(std.Build.path(b,"include/"));
    exe.root_module.addCSourceFiles(.{
        .root = b.path("."),
        .files = &[_][]const u8{"src/main.c"},
        .flags = &[_][]const u8 {"-std=c23","-Wall","-Wextra","-gen-cdb-fragment-path","cdb-frags"},
    });
    exe.root_module.addLibraryPath(std.Build.path(b,"lib/"));
    //exe.root_module.linkSystemLibrary("",.{});

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
    var threaded : std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    defer threaded.deinit();

    var outf = try std.Io.Dir.cwd().createFile(io, "compile_commands.json", .{});
    defer outf.close(io);
    var dir = std.Io.Dir.cwd().openDir(io, "cdb-frags", .{.iterate = true}) catch {
        std.debug.print("Failed to open ./cdb-frags/", .{});
        return;
    };
    defer dir.close(io);

    try outf.writeStreamingAll(io,"[");
    var iter = dir.iterate();
    while(try iter.next(io)) |entry| {
        const fpath = try std.fmt.allocPrint(
            std.heap.page_allocator, "cdb-frags/{s}", .{entry.name}
        );
        const contents = try std.Io.Dir.cwd().readFileAlloc(io, fpath, std.heap.page_allocator, .limited(1024*1024));
        var outf_w = outf.writer(io, contents);
        try outf_w.seekTo(0);
        try outf.writeStreamingAll(io, contents);
    }
    try outf.writeStreamingAll(io, "]");

}
