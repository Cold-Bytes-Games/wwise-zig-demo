const std = @import("std");
const root = @import("root");
const DemoInterface = @import("../DemoInterface.zig");

allocator: std.mem.Allocator,

const Self = @This();

pub fn init(self: *Self, allocator: std.mem.Allocator, demo_state: *root.DemoState) anyerror!void {
    _ = demo_state;
    self.allocator = allocator;
}

pub fn deinit(self: *Self, demo_state: *root.DemoState) void {
    _ = demo_state;
    self.allocator.destroy(self);
}

pub fn onUI(self: *Self, demo_state: *root.DemoState) !void {
    _ = demo_state;
    _ = self;
}

pub fn isVisible(self: *Self) bool {
    _ = self;
    return false;
}

pub fn show(self: *Self) void {
    _ = self;
}

pub fn demoInterface(self: *Self) DemoInterface {
    return DemoInterface{
        .instance = self,
        .initFn = @as(DemoInterface.InitFn, @ptrCast(&init)),
        .deinitFn = @as(DemoInterface.DeinitFn, @ptrCast(&deinit)),
        .onUIFn = @as(DemoInterface.OnUIFn, @ptrCast(&onUI)),
        .isVisibleFn = @as(DemoInterface.IsVisibleFn, @ptrCast(&isVisible)),
        .showFn = @as(DemoInterface.ShowFn, @ptrCast(&show)),
    };
}
