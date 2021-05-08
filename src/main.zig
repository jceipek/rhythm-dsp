//------------------------------------------------------------------------------
//  triangle.zig
//
//  Vertex buffer, shader, pipeline state object.
//------------------------------------------------------------------------------
const std = @import("std");
const builtin = @import("builtin");
const sg    = @import("sokol").gfx;
const sapp  = @import("sokol").app;
const sgapp = @import("sokol").app_gfx_glue;

const libname = switch (builtin.os.tag) {
    .linux, .freebsd, .openbsd => "invalid_so.so",
    .windows => "invalid_dll.dll",
    .macos, .tvos, .watchos, .ios => "./zig-cache/lib/libdsp.dylib",
    else => return error.NotFound,
};

const Dsplib = struct {
    lib: ?*std.DynLib = null,
    add: ?fn (i32, i32) callconv(.C) i32 = null,
    last_modified: i128 = 0,

    fn _load(self: *Dsplib, path: []const u8) !void {
        var lib = try std.DynLib.open(path);
        var add = lib.lookup(fn (i32, i32) callconv(.C) i32, "add") orelse return error.SymbolNotFound;
        self.lib = &lib;
        self.add = add;
    }

    pub fn load() !Dsplib {
        var res: Dsplib = .{};
        try res._load(libname);
        res.last_modified = dsplibModTime() catch 0;
        return res;
    }
    pub fn reloadIfNeeded(self: *Dsplib) void {
        var new_time = dsplibModTime() catch 0;
        if (new_time > self.last_modified) {
            const stdout = std.io.getStdOut().writer();

            self.close();

            // XXX: close and load don't guarantee that the library is a new library
            // This is super annoying, so we duplicate to a new file with a name that is the
            // new timestamp.
            // TODO: delete the old file.
            const currDir = std.fs.cwd();
            var buf: [100]u8 = undefined;
            const newName = std.fmt.bufPrint(&buf, "{d}", .{ new_time }) catch return;
            currDir.copyFile(libname, currDir, newName, .{}) catch return;
            self._load(newName) catch return;

            const addition = self.add.?(1,2);
            stdout.print("Reloaded! {d} {d}\n", .{new_time, addition}) catch return;

            self.last_modified = new_time;
        }
    }
    pub fn close(self: *Dsplib) void {
        self.lib.?.close();

        const stdout = std.io.getStdOut().writer();
        stdout.print("Unloaded!\n", .{}) catch return;
    }
};

var loaded_lib: Dsplib = .{};

const state = struct {
    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};
};

fn dsplibModTime() !i128 {
    // Open the lib and see what the last modification time was!
    const currDir = std.fs.cwd();
    const file = try currDir.openFile(libname, .{ .read = false, .write = false });
    defer file.close();
    const stat = try file.stat();
    const mod_time = stat.mtime;
    return mod_time;
}

export fn init() void {
    loaded_lib = Dsplib.load() catch return;

    sg.setup(.{
        .context = sgapp.context()
    });

    // create vertex buffer with triangle vertices
    const vertices = [_]f32 {
        // positions         colors
         0.0,  0.5, 0.5,     1.0, 0.0, 0.0, 1.0,
         0.5, -0.5, 0.5,     0.0, 1.0, 0.0, 1.0,
        -0.5, -0.5, 0.5,     0.0, 0.0, 1.0, 1.0
    };
    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(vertices)
    });

    // create a shader and pipeline object
    const shd = sg.makeShader(shaderDesc());
    var pip_desc: sg.PipelineDesc = .{
        .shader = shd
    };
    pip_desc.layout.attrs[0].format = .FLOAT3;
    pip_desc.layout.attrs[1].format = .FLOAT4;
    state.pip = sg.makePipeline(pip_desc);
}

var lastRes: i32 = 0;
export fn frame() void {
    loaded_lib.reloadIfNeeded();

    const v = loaded_lib.add.?(1,2);
    if (lastRes != v) {
        const stdout = std.io.getStdOut().writer();
        stdout.print("Hello, {d}!\n", .{v}) catch return;
        lastRes = v;
    }

    // default pass-action clears to grey
    sg.beginDefaultPass(.{}, sapp.width(), sapp.height());
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.draw(0, 3, 1);
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    loaded_lib.close();
    sg.shutdown();
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .width = 640,
        .height = 480,
        .window_title = "DSP Experiments"
    });
}

// build a backend-specific ShaderDesc struct
// NOTE: the other samples are using shader-cross-compilation via the
// sokol-shdc tool, but this sample uses a manual shader setup to
// demonstrate how it works without a shader-cross-compilation tool
//
fn shaderDesc() sg.ShaderDesc {
    var desc: sg.ShaderDesc = .{};
    switch (sg.queryBackend()) {
        .D3D11 => {
            desc.attrs[0].sem_name = "POS";
            desc.attrs[1].sem_name = "COLOR";
            desc.vs.source =
                \\struct vs_in {
                \\  float4 pos: POS;
                \\  float4 color: COLOR;
                \\};
                \\struct vs_out {
                \\  float4 color: COLOR0;
                \\  float4 pos: SV_Position;
                \\};
                \\vs_out main(vs_in inp) {
                \\  vs_out outp;
                \\  outp.pos = inp.pos;
                \\  outp.color = inp.color;
                \\  return outp;
                \\}
                ;
            desc.fs.source =
                \\float4 main(float4 color: COLOR0): SV_Target0 {
                \\  return color;
                \\}
                ;
        },
        .GLCORE33 => {
            desc.attrs[0].name = "position";
            desc.attrs[1].name = "color0";
            desc.vs.source =
                \\ #version 330
                \\ in vec4 position;
                \\ in vec4 color0;
                \\ out vec4 color;
                \\ void main() {
                \\   gl_Position = position;
                \\   color = color0;
                \\ }
                ;
            desc.fs.source =
                \\ #version 330
                \\ in vec4 color;
                \\ out vec4 frag_color;
                \\ void main() {
                \\   frag_color = color;
                \\ }
                ;
        },
        .METAL_MACOS => {
            desc.vs.source =
                \\ #include <metal_stdlib>
                \\ using namespace metal;
                \\ struct vs_in {
                \\   float4 position [[attribute(0)]];
                \\   float4 color [[attribute(1)]];
                \\ };
                \\ struct vs_out {
                \\   float4 position [[position]];
                \\   float4 color;
                \\ };
                \\ vertex vs_out _main(vs_in inp [[stage_in]]) {
                \\   vs_out outp;
                \\   outp.position = inp.position;
                \\   outp.color = inp.color;
                \\   return outp;
                \\ }
                ;
            desc.fs.source =
                \\ #include <metal_stdlib>
                \\ using namespace metal;
                \\ fragment float4 _main(float4 color [[stage_in]]) {
                \\   return color;
                \\ };
                ;
        },
        else => {}
    }
    return desc;
}

