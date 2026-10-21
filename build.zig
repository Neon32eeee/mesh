const std = @import("std");

const EXAMPLES = &.{
    .{ .name = "no_db_version", .path = "examples/DB/no_db_version.zig" },
    .{ .name = "db_version", .path = "examples/DB/db_version.zig" },
    .{ .name = "json", .path = "examples/json.zig" },
    .{ .name = "params", .path = "examples/params.zig" },
    .{ .name = "response", .path = "examples/response.zig" },
    .{ .name = "middleware", .path = "examples/middleware.zig" },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- Основной модуль библиотеки ---
    const mod = b.addModule("Mesh", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "Mesh",
        .linkage = .static,
        .root_module = mod,
    });

    const default_step = b.step("default", "Build library");
    default_step.dependOn(&lib.step);

    const zap_dep = b.dependency("zap", .{
        .target = target,
        .optimize = optimize,
    });
    const zap_mod = zap_dep.module("zap");

    mod.addImport("zap", zap_mod);

    const ddb_dep = b.dependency("ddb", .{
        .target = target,
        .optimize = optimize,
    });
    const ddb_mod = ddb_dep.module("DDB");

    mod.addImport("ddb", ddb_mod);

    const exe = b.addExecutable(.{
        .name = "Mesh",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "Mesh", .module = mod },
                .{ .name = "zap", .module = zap_mod },
                .{ .name = "ddb", .module = ddb_mod },
            },
        }),
    });

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);

    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.addPassthruArgs();

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    const examples_step = b.step("example", "Run all examples");

    inline for (EXAMPLES) |ex| {
        const example_exe = b.addExecutable(.{
            .name = ex.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(ex.path),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "Mesh", .module = mod },
                    .{ .name = "zap", .module = zap_mod },
                    .{ .name = "ddb", .module = ddb_mod },
                },
            }),
        });

        const run_example = b.addRunArtifact(example_exe);

        run_cmd.addPassthruArgs();

        examples_step.dependOn(&run_example.step);

        const single_step_name = "run-" ++ ex.name;
        const single_step = b.step(single_step_name, "Run example: " ++ ex.name);
        single_step.dependOn(&run_example.step);
    }

    b.installArtifact(lib);
}
