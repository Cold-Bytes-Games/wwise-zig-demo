const std = @import("std");
const DemoInterface = @import("../DemoInterface.zig");

allocator: std.mem.Allocator,

const Self = @This();

pub fn init(self: *Self, allocator: std.mem.Allocator) anyerror!void {
    self.allocator = allocator;
}

pub fn deinit(self: *Self) void {
    self.allocator.destroy(self);
}

pub fn onUI(self: *Self) !void {
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
        .initFn = @ptrCast(DemoInterface.InitFn, &init),
        .deinitFn = @ptrCast(DemoInterface.DeinitFn, &deinit),
        .onUIFn = @ptrCast(DemoInterface.OnUIFn, &onUI),
        .isVisibleFn = @ptrCast(DemoInterface.IsVisibleFn, &isVisible),
        .showFn = @ptrCast(DemoInterface.ShowFn, &show),
    };
}
