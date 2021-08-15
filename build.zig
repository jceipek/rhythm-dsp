const std = @import("std");
const Builder = std.build.Builder;
const CrossTarget = @import("std").zig.CrossTarget;
const Mode = std.builtin.Mode;
const LibExeObjStep = std.build.LibExeObjStep;


const bld = @import("std").build;
const mem = @import("std").mem;
const zig = @import("std").zig;

// macOS helper function to add SDK search paths
fn macosAddSdkDirs(b: *bld.Builder, step: *bld.LibExeObjStep) !void {
    const sdk_dir = try zig.system.getSDKPath(b.allocator);
    const framework_dir = try mem.concat(b.allocator, u8, &[_][]const u8 { sdk_dir, "/System/Library/Frameworks" });
    const usrinclude_dir = try mem.concat(b.allocator, u8, &[_][]const u8 { sdk_dir, "/usr/include"});
    step.addFrameworkDir(framework_dir);
    step.addIncludeDir(usrinclude_dir);
}

// build sokol into a static library
pub fn buildSokol(b: *Builder, target: CrossTarget, mode: Mode, comptime prefix_path: []const u8) *LibExeObjStep {
    const lib = b.addStaticLibrary("sokol", null);
    lib.setBuildMode(mode);
    lib.setTarget(target);
    lib.linkLibC();
    const sokol_path = prefix_path ++ "src/sokol/c/";
    const csources = [_][]const u8 {
        "sokol_app.c",
        "sokol_gfx.c",
        "sokol_time.c",
        "sokol_audio.c",
        "sokol_gl.c",
        "sokol_debugtext.c",
        "sokol_shape.c",
    };
    if (lib.target.isDarwin()) {
        b.env_map.put("ZIG_SYSTEM_LINKER_HACK", "1") catch unreachable;
        inline for (csources) |csrc| {
            lib.addCSourceFile(sokol_path ++ csrc, &[_][]const u8{"-ObjC", "-DIMPL"});
        }
        lib.linkFramework("MetalKit");
        lib.linkFramework("Metal");
        lib.linkFramework("Cocoa");
        lib.linkFramework("QuartzCore");
        lib.linkFramework("AudioToolbox");
    } else {
        inline for (csources) |csrc| {
            lib.addCSourceFile(sokol_path ++ csrc, &[_][]const u8{"-DIMPL"});
        }
        if (lib.target.isLinux()) {
            lib.linkSystemLibrary("X11");
            lib.linkSystemLibrary("Xi");
            lib.linkSystemLibrary("Xcursor");
            lib.linkSystemLibrary("GL");
            lib.linkSystemLibrary("asound");
        }
        else if (lib.target.isWindows()) {
            lib.linkSystemLibrary("kernel32");
            lib.linkSystemLibrary("user32");
            lib.linkSystemLibrary("gdi32");
            lib.linkSystemLibrary("ole32");
            lib.linkSystemLibrary("d3d11");
            lib.linkSystemLibrary("dxgi");
        }
    }
    return lib;
}

fn buildDsplib(b: *bld.Builder, comptime name: []const u8) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addSharedLibrary(name, "src/dsplib/dsplib.zig", .unversioned);
    lib.setBuildMode(mode);
    lib.install();
    lib.setOutputDir("./zig-cache/lib");

    const lib_step = b.step(name, "Build dsplib");
    lib_step.dependOn(&lib.step);
}

fn buildExample(b: *bld.Builder, sokol: *bld.LibExeObjStep, comptime name: []const u8) void {
    const mode = b.standardReleaseOptions();
    const e = b.addExecutable("rhythm-dsp", "src/main.zig");
    e.linkLibrary(sokol);
    e.setBuildMode(mode);
    e.addPackagePath("sokol", "src/sokol/sokol.zig");
    e.install();
    b.step(name, "Run the app").dependOn(&e.run().step);
}

fn buildWavRead(b: *bld.Builder, comptime name: []const u8) void {
    const mode = b.standardReleaseOptions();
    const e = b.addExecutable("wavreader", "src/dsplib/readwav.zig");
    e.setBuildMode(mode);
    e.install();
    b.step(name, "Read a wave file").dependOn(&e.run().step);
}

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    const sokol = buildSokol(b, target, mode, "");
    buildDsplib(b, "dsp");
    buildDsplib(b, "dsp2");
    buildExample(b, sokol, "run");
    buildWavRead(b, "readwav");
}
