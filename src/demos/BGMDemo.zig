const std = @import("std");
const builtin = @import("builtin");
const DemoInterface = @import("../DemoInterface.zig");
const zgui = @import("zgui");
const root = @import("root");
const AK = @import("wwise-zig");
const ID = @import("wwise-ids");

allocator: std.mem.Allocator = undefined,
is_visible: bool = false,
bank_id: AK.AkBankID = AK.AK_INVALID_BANK_ID,
id_bgm_output: AK.AkOutputDeviceID = AK.AK_INVALID_OUTPUT_DEVICE_ID,
play_licensed: bool = false,
play_copyright: bool = false,

const Self = @This();

const DemoGameObjectID: AK.AkGameObjectID = 10;

// Supported only on PS4 and XB1
// TODO: Add support for this when PS4, XB1, PS5 and GDKX is supported
const SupportDVR = switch (builtin.os.tag) {
    else => false,
};

pub fn init(self: *Self, allocator: std.mem.Allocator, demo_state: *root.DemoState) !void {
    _ = demo_state;
    self.* = .{
        .allocator = allocator,
    };

    self.bank_id = try AK.SoundEngine.loadBankString(allocator, "BGM.bnk", .{});

    if (SupportDVR) {
        const output_settings = try AK.AkOutputSettings.init(allocator, "DVR_Bypass", .{});
        self.id_bgm_output = try AK.SoundEngine.addOutput(&output_settings, &.{});
    }

    try AK.SoundEngine.registerGameObjWithName(allocator, DemoGameObjectID, "Recordable Music");
}

pub fn deinit(self: *Self, demo_state: *root.DemoState) void {
    _ = demo_state;

    AK.SoundEngine.unregisterGameObj(DemoGameObjectID) catch {};

    if (SupportDVR) {
        AK.SoundEngine.removeOutput(self.id_bgm_output) catch {};
    }

    AK.SoundEngine.unloadBankID(self.bank_id, null, .{}) catch {};

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self, demo_state: *root.DemoState) !void {
    _ = demo_state;
    zgui.setNextWindowSize(.{
        .w = 215,
        .h = 80,
        .cond = .always,
    });

    if (zgui.begin("Background Music Demo", .{ .popen = &self.is_visible, .flags = .{ .always_auto_resize = true } })) {
        if (self.play_licensed) {
            if (zgui.button("Stop", .{})) {
                AK.SoundEngine.stopAll(.{ .game_object_id = DemoGameObjectID });
                self.play_licensed = false;
            }
        } else {
            if (zgui.button("Play recordable music", .{})) {
                _ = try AK.SoundEngine.postEventID(ID.EVENTS.PLAY_RECORDABLEMUSIC, DemoGameObjectID, .{});
                self.play_licensed = true;
            }
        }

        if (self.play_copyright) {
            if (zgui.button("Stop", .{})) {
                AK.SoundEngine.stopAll(.{ .game_object_id = DemoGameObjectID });
                self.play_copyright = false;
            }
        } else {
            if (zgui.button("Play non-recordable music", .{})) {
                _ = try AK.SoundEngine.postEventID(ID.EVENTS.PLAY_NONRECORDABLEMUSIC, DemoGameObjectID, .{});
                self.play_copyright = true;
            }
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
    return DemoInterface.toDemoInteface(self);
}
