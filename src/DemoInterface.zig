const std = @import("std");
const root = @import("root");

instance: InstanceType,
initFn: InitFn,
deinitFn: DeinitFn,
onUIFn: OnUIFn,
isVisibleFn: IsVisibleFn,
showFn: ShowFn,

pub const InstanceType = *anyopaque;
pub const InitFn = *const fn (instance: InstanceType, allocator: std.mem.Allocator, demo_state: *root.DemoState) anyerror!void;
pub const DeinitFn = *const fn (instance: InstanceType, demo_state: *root.DemoState) void;
pub const OnUIFn = *const fn (instance: InstanceType, demo_state: *root.DemoState) anyerror!void;
pub const IsVisibleFn = *const fn (instance: InstanceType) bool;
pub const ShowFn = *const fn (instance: InstanceType) void;

const Self = @This();

pub fn toDemoInteface(instance: anytype) Self {
    const T = std.meta.Child(@TypeOf(instance));
    return Self{
        .instance = @ptrCast(instance),
        .initFn = @ptrCast(&@field(T, "init")),
        .deinitFn = @ptrCast(&@field(T, "deinit")),
        .onUIFn = @ptrCast(&@field(T, "onUI")),
        .isVisibleFn = @ptrCast(&@field(T, "isVisible")),
        .showFn = @ptrCast(&@field(T, "show")),
    };
}

pub fn init(self: *Self, allocator: std.mem.Allocator, demo_state: *root.DemoState) anyerror!void {
    return self.initFn(self.instance, allocator, demo_state);
}

pub fn deinit(self: *Self, demo_state: *root.DemoState) void {
    self.deinitFn(self.instance, demo_state);
}

pub fn onUI(self: *Self, demo_state: *root.DemoState) anyerror!void {
    return self.onUIFn(self.instance, demo_state);
}

pub fn isVisible(self: *Self) bool {
    return self.isVisibleFn(self.instance);
}

pub fn show(self: *Self) void {
    self.showFn(self.instance);
}
