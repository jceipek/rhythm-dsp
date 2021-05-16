const std = @import("std");
pub const Allocator = std.mem.Allocator;

const testing = std.testing;

pub const API = packed struct {
    init: fn init(allocator: *Allocator) ?*State,
    add: fn add(a: i32, b: i32) i32,
};

pub const State = struct {
    allocator: *Allocator,
    a: u64,
};

fn init(allocator: *Allocator) ?*State {
    return if (allocator.create(State)) |mem| {
        mem.* = State{
            .allocator = allocator,
            .a = 5,
        };
        return mem;
    } else |_| null;
}

fn add(a: i32, b: i32) i32 {
    return a + b+2;
}

export var DSP = API {
    .init = init,
    .add = add,
};

test "basic add functionality" {
    testing.expect(add(3, 7) == 10);
}
