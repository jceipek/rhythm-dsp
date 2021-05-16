const std = @import("std");

pub fn main () !void {
    
    const currDir = std.fs.cwd();
    const file = try currDir.openFile("../Heystack/symphony_7_1_(c)cvikl_s16PCM.wav", .{ .read = true, .write = false });
    defer file.close();

    var reader = file.reader();
    // const magic = try reader.readIntBig(u32);
    
    // ! [4]u8
    // []const u8 -- slice
    // *const [4]u8
    const magic = try reader.readBytesNoEof(4); // ![4]u8 -- error or array of 4 u8s
    std.debug.assert(@TypeOf(magic) == [4]u8);
    // std.debug.assert(@TypeOf("RIFF") == []const u8);
    // @TypeOf(&magic);

    //           pointer to array of 4 u8s -> slice of u8 -> const slice of u8  
    // comparing {*[4]u8, which coerces to []u8, which coerces to []const u8} to {[]const u8}
    std.debug.assert(std.mem.eql(u8, &magic, "RIFF"));

    // const magicnum: u32 = @bitCast(u32, "RIFF".*);

    // std.debug.assert(magic == @intCast(u32, "RIFF"));
    // std.debug.assert(std.mem.eql(u8, @bitCast([]const u8, magic), "RIFF"));

    // "RIFF" is of type '*const [4:0]u8'
    // std.debug.assert(magic == @bitCast(u32, "RIFF"));
    const stdout = std.io.getStdOut().writer();
    // stdout.print("Test wav reading!\n", .{}) catch return;
    stdout.print("type of magic: {} \n", .{@typeName(@TypeOf(magic))}) catch return;
    stdout.print("type of &magic: {} \n", .{@typeName(@TypeOf(&magic))}) catch return;
    stdout.print("type of \"RIFF\": {} \n", .{@typeName(@TypeOf("RIFF"[0..4]))}) catch return;
}