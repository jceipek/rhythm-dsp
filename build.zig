const Builder = @import("std").build.Builder;


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
pub fn buildSokol(b: *bld.Builder, comptime prefix_path: []const u8) *bld.LibExeObjStep {
    const lib = b.addStaticLibrary("sokol", null);
    lib.linkLibC();
    lib.setBuildMode(b.standardReleaseOptions());
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
        macosAddSdkDirs(b, lib) catch unreachable;
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

pub fn build(b: *Builder) void {
    const sokol = buildSokol(b, "");
    buildDsplib(b, "dsp");
    buildDsplib(b, "dsp2");
    buildExample(b, sokol, "run");
}
