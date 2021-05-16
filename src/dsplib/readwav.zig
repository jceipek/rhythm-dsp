const std = @import("std");
const Allocator = std.mem.Allocator;
const Gpa = std.heap.GeneralPurposeAllocator(.{});
var gpa = Gpa{};


const WaveAudioData = struct {
    allocator : *Allocator,
    num_channels : u16,
    sample_rate : u32,
    byte_rate : u32,
    block_align : u16,
    bits_per_sample : u16,
    data : []u8,

    fn readWav(filepath: []const u8, allocator: *Allocator) !WaveAudioData {
        const currDir = std.fs.cwd();
        // "../Heystack/symphony_7_1_(c)cvikl_s16PCM.wav"
        const file = try currDir.openFile(filepath, .{ .read = true, .write = false });
        defer file.close();

        var reader = file.reader();
        // ! [4]u8
        // []const u8 -- slice
        // *const [4]u8
        const magic = try reader.readBytesNoEof(4); // ![4]u8 -- error or array of 4 u8s
        if (!std.mem.eql(u8, &magic, "RIFF")){
            return error.ParseError;
        }
        const chunk_size = try reader.readIntLittle(u32);
        const fmt = try reader.readBytesNoEof(4);
        if (!std.mem.eql(u8, &fmt, "WAVE")){
            return error.ParseError;
        }
        const subchunk1_id = try reader.readBytesNoEof(4);
        if (!std.mem.eql(u8, &subchunk1_id, "fmt ")){
            return error.ParseError;
        }
        const subchunk1_size = try reader.readIntLittle(u32);
        const audio_format = try reader.readIntLittle(u16);
        if ( audio_format != 1) {
            return error.NotPCM;
        }
        const num_channels = try reader.readIntLittle(u16);
        const sample_rate = try reader.readIntLittle(u32);
        const byte_rate = try reader.readIntLittle(u32);
        const block_align = try reader.readIntLittle(u16);
        const bits_per_sample = try reader.readIntLittle(u16);
        const subchunk2_id = try reader.readBytesNoEof(4);
        if (!std.mem.eql(u8, &subchunk2_id, "data")) {
            return error.ParseError;
        }
        const subchunk2_size = try reader.readIntLittle(u32);
        var data = try allocator.alloc(u8, subchunk2_size);
        const data_length = try reader.read(data);
        if (data_length != subchunk2_size) {
            return error.ParseError;
        }
        return WaveAudioData{
            .allocator = allocator,
            .num_channels= num_channels,
            .sample_rate = sample_rate,
            .byte_rate = byte_rate,
            .block_align = block_align,
            .bits_per_sample = bits_per_sample,
            .data = data,
        };

    }
    fn deInit(self: *WaveAudioData) void {
        self.allocator.free(self.data);
    }

};


pub fn main () !void {

    var beethoven = try WaveAudioData.readWav("../Heystack/symphony_7_1_(c)cvikl_s16PCM.wav", &gpa.allocator);
    defer beethoven.deInit();
    const stdout = std.io.getStdOut().writer();
    try stdout.print(" Beethoven:{}\n{}\n{}\n{}\n{}\n", .{beethoven.num_channels, beethoven.sample_rate, 
    beethoven.byte_rate, beethoven.block_align, beethoven.bits_per_sample});
// .num_channels= num_channels,
            // .sample_rate = sample_rate,
            // .byte_rate = byte_rate,
            // .block_align = bloack_align,
            // .bits_per_sample = bits_per_sample,
            // .data = data,

}

// Graveyard
// std.debug.assert(@TypeOf(magic) == [4]u8);
    // std.debug.assert(@TypeOf("RIFF") == []const u8);
    // @TypeOf(&magic);

    //           pointer to array of 4 u8s -> slice of u8 -> const slice of u8  
    // comparing {*[4]u8, which coerces to []u8, which coerces to []const u8} to {[]const u8}
    

    // const magicnum: u32 = @bitCast(u32, "RIFF".*);

    // std.debug.assert(magic == @intCast(u32, "RIFF"));
    // std.debug.assert(std.mem.eql(u8, @bitCast([]const u8, magic), "RIFF"));

        // "RIFF" is of type '*const [4:0]u8'
    // std.debug.assert(magic == @bitCast(u32, "RIFF"));
    // const stdout = std.io.getStdOut().writer();
    // // stdout.print("Test wav reading!\n", .{}) catch return;
    // // stdout.print("type of magic: {} \n", .{@typeName(@TypeOf(magic))}) catch return;
    // // stdout.print("type of &magic: {} \n", .{@typeName(@TypeOf(&magic))}) catch return;
    // stdout.print("type of \"RIFF\": {} \n", .{@typeName(@TypeOf("RIFF"[0..4]))}) catch return;
    // try stdout.print("Chunk size is: {} \n", .{chunk_size});
    // try stdout.print("Sub chunk 1 size is:  {} \n", .{subchunk1_size});
