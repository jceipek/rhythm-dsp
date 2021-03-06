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
const dsplib = @import("dsplib/dsplib.zig");

const libname = switch (builtin.os.tag) {
    .linux, .freebsd, .openbsd => "invalid_so.so",
    .windows => "invalid_dll.dll",
    .macos, .tvos, .watchos, .ios => "./zig-cache/lib/libdsp.dylib",
    else => return error.NotFound,
};

const Dsplib = struct {
    lib: ?*std.DynLib = null,
    api: ?dsplib.API = null,
    last_modified: i128 = 0,

    fn _load(self: *Dsplib, path: []const u8) !void {
        var lib = try std.DynLib.open(path);
        var api = lib.lookup(*dsplib.API, "DSP") orelse return error.SymbolNotFound;
        self.lib = &lib;
        self.api = api.*;
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
            const curr_dir = std.fs.cwd();
            var buf: [100]u8 = undefined;
            const new_name = std.fmt.bufPrint(&buf, "{d}", .{ new_time }) catch return;
            curr_dir.copyFile(libname, curr_dir, new_name, .{}) catch return;
            self._load(new_name) catch return;

            stdout.print("Reloaded! {s}\n", .{new_name}) catch return;
            self.last_modified = new_time;
        }
    }
    pub fn close(self: *Dsplib) void {
        const stdout = std.io.getStdOut().writer();
        if (self.lib) |lib| {
            lib.close();
            const curr_dir = std.fs.cwd();
            if (self.last_modified != 0) {
                var buf: [100]u8 = undefined;
                const old_name = std.fmt.bufPrint(&buf, "{d}", .{ self.last_modified }) catch return;
                stdout.print("Deleting! {s}\n", .{old_name}) catch return;
                curr_dir.deleteFile(old_name) catch return;
                self.last_modified = 0;
            }
        }

        stdout.print("Unloaded!\n", .{}) catch return;
    }
};

var loaded_lib: Dsplib = .{};

const FsParams = extern struct {
    frameCount: u64 = 0,
};

const state = struct {
    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};
    var fs_params: FsParams = .{};
};

fn dsplibModTime() !i128 {
    // Open the lib and see what the last modification time was!
    const curr_dir = std.fs.cwd();
    const file = try curr_dir.openFile(libname, .{ .read = false, .write = false });
    defer file.close();
    const stat = try file.stat();
    const mod_time = stat.mtime;
    return mod_time;
}

export fn init() void {
    sg.setup(.{
        .context = sgapp.context()
    });

    var img_data = [_]u16{0} ** 128;

    img_data[20] = 65000/2;
    img_data[50] = 65000;

    var img_desc = sg.ImageDesc {
        .width = 128,
        .height=1,
        .pixel_format = .R16
    };
    img_desc.data.subimage[0][0] = sg.asRange(img_data);

    const img = sg.makeImage(img_desc);

    // create vertex buffer with triangle vertices
    const vertices = [_]f32 {
        // positions         colors
          1.0,  1.0, 0.0,     1.0, 1.0,
         -1.0,  1.0, 0.0,     0.0, 1.0,
         -1.0, -1.0, 0.0,     0.0, 0.0,

          1.0,  1.0, 0.0,     1.0, 1.0,
         -1.0, -1.0, 0.0,     0.0, 0.0,
          1.0, -1.0, 0.0,     1.0, 0.0,
    };
    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(vertices)
    });
    state.bind.fs_images[0] = img;

    // create a shader and pipeline object
    const shd = sg.makeShader(shaderDesc());
    var pip_desc: sg.PipelineDesc = .{
        .shader = shd
    };
    pip_desc.layout.attrs[0].format = .FLOAT3;
    pip_desc.layout.attrs[1].format = .FLOAT2;
    state.pip = sg.makePipeline(pip_desc);
}

var lastRes: i32 = 0;

export fn frame() void {
    loaded_lib.reloadIfNeeded();
    // Add with overflow
    state.fs_params.frameCount +%= 1;

    if (loaded_lib.api) |api| {
        const v = api.add(1,2);
        if (lastRes != v) {
            const stdout = std.io.getStdOut().writer();
            stdout.print("Hello, {d}!\n", .{v}) catch return;
            lastRes = v;
        }
    } 

    // default pass-action clears to grey
    sg.beginDefaultPass(.{}, sapp.width(), sapp.height());
    sg.applyPipeline(state.pip);
    // sg.applyUniforms(.FS, 0, .{.ptr = &FsParams, .size = @sizeOf(@TypeOf(FsParams))});
    sg.applyUniforms(.FS, 0, sg.asRange(state.fs_params));
    
    // sg.applyUniforms(.FS, 0, );
    sg.applyBindings(state.bind);
    sg.draw(0, 6, 1);
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    loaded_lib.close();
    sg.shutdown();
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    loaded_lib = Dsplib.load() catch |err| {
        try stdout.print("Unable to load Dsplib ({s}). Did you zig build dsp?\n", .{err});
        return;
    };
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
                \\   float2 uv [[attribute(1)]];
                \\ };
                \\ struct vs_out {
                \\   float4 position [[position]];
                \\   float2 uv;
                \\ };
                \\ vertex vs_out _main(vs_in inp [[stage_in]]) {
                \\   vs_out outp;
                \\   outp.position = inp.position;
                \\   outp.uv = inp.uv;
                \\   return outp;
                \\ }
                ;
            desc.fs.source =
                \\ #include <metal_stdlib>
                \\ using namespace metal;
                \\ struct params {
                \\   uint64_t frameCount;
                \\ };
                \\
                \\ fragment float4 _main(float2 uv [[stage_in]], texture2d<float> tex [[texture(0)]], sampler texSmplr [[sampler(0)]], constant params& params [[buffer(0)]]) {
                \\   float move = (sin(float(params.frameCount) * 0.1)+1.0)*0.5;
                \\   float val = tex.sample(texSmplr, float2(uv.x, 0.5)).r * move > uv.y? 1.0 : 0.0;
                \\   float4 color = float4(val, val, val, 1.0);
                \\   return color;
                \\ };
                ;
            desc.fs.images[0].name = "tex";
            desc.fs.images[0].image_type = ._2D;
            desc.fs.images[0].sampler_type = .FLOAT;
            desc.fs.uniform_blocks[0].size = @sizeOf(FsParams);
            desc.fs.uniform_blocks[0].uniforms[0].name = "frameCount";
        },
        else => {}
    }
    return desc;
}

