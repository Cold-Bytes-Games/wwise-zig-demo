const std = @import("std");

instance: InstanceType,
initFn: InitFn,
deinitFn: DeinitFn,
onUIFn: OnUIFn,
isVisibleFn: IsVisibleFn,
showFn: ShowFn,

pub const InstanceType = *anyopaque;
pub const InitFn = *const fn (instance: InstanceType, allocator: std.mem.Allocator) anyerror!void;
pub const DeinitFn = *const fn (instance: InstanceType) void;
pub const OnUIFn = *const fn (instance: InstanceType) anyerror!void;
pub const IsVisibleFn = *const fn (instance: InstanceType) bool;
pub const ShowFn = *const fn (instance: InstanceType) void;

const Self = @This();

pub fn init(self: *Self, allocator: std.mem.Allocator) anyerror!void {
    return self.initFn(self.instance, allocator);
}

pub fn deinit(self: *Self) void {
    self.deinitFn(self.instance);
}

pub fn onUI(self: *Self) anyerror!void {
    return self.onUIFn(self.instance);
}

pub fn isVisible(self: *Self) bool {
    return self.isVisibleFn(self.instance);
}

pub fn show(self: *Self) void {
    self.showFn(self.instance);
}
