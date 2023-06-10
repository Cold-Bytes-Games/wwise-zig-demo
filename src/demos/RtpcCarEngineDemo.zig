const std = @import("std");
const DemoInterface = @import("../DemoInterface.zig");
const zgui = @import("zgui");
const root = @import("root");
const AK = @import("wwise-zig");

allocator: std.mem.Allocator = undefined,
is_visible: bool = false,
bank_id: AK.AkBankID = AK.AK_INVALID_BANK_ID,
is_playing: bool = false,
rpm_value: i32 = MinRPMValue,

const Self = @This();

const MinRPMValue = 1000;
const MaxRPMValue = 10000;
const DemoGameObjectID: AK.AkGameObjectID = 4;

pub fn init(self: *Self, allocator: std.mem.Allocator, demo_state: *root.DemoState) !void {
    _ = demo_state;
    self.* = .{
        .allocator = allocator,
    };

    self.bank_id = try AK.SoundEngine.loadBankString(allocator, "Car.bnk", .{});
    try AK.SoundEngine.registerGameObjWithName(allocator, DemoGameObjectID, "Car");

    try AK.SoundEngine.setRTPCValueString(allocator, "RPM", @intToFloat(f32, self.rpm_value), .{ .game_object_id = DemoGameObjectID });
}

pub fn deinit(self: *Self, demo_state: *root.DemoState) void {
    _ = demo_state;
    AK.SoundEngine.unloadBankID(self.bank_id, null, .{}) catch {};
    AK.SoundEngine.unregisterGameObj(DemoGameObjectID) catch {};

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self, demo_state: *root.DemoState) !void {
    _ = demo_state;
    if (zgui.begin("RTPC Demo (Car Engine)", .{ .popen = &self.is_visible, .flags = .{ .always_auto_resize = true } })) {
        const button_text = if (self.is_playing) "Stop Engine" else "Start Engine";

        if (zgui.button(button_text, .{})) {
            if (self.is_playing) {
                _ = try AK.SoundEngine.postEventString(self.allocator, "Stop_Engine", DemoGameObjectID, .{});
                self.is_playing = false;
            } else {
                _ = try AK.SoundEngine.postEventString(self.allocator, "Play_Engine", DemoGameObjectID, .{});
                self.is_playing = true;
            }
        }

        if (zgui.sliderInt("RPM", .{ .v = &self.rpm_value, .min = MinRPMValue, .max = MaxRPMValue })) {
            try AK.SoundEngine.setRTPCValueString(self.allocator, "RPM", @intToFloat(f32, self.rpm_value), .{ .game_object_id = DemoGameObjectID });
        }

        zgui.end();
    }

    if (!self.is_visible) {
        AK.SoundEngine.stopAll(.{ .game_object_id = DemoGameObjectID });
    }
}

pub fn isVisible(self: *Self) bool {
    return self.is_visible;
}

pub fn show(self: *Self) void {
    self.is_visible = true;
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
