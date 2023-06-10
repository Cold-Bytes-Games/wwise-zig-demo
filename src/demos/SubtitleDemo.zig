const std = @import("std");
const DemoInterface = @import("../DemoInterface.zig");
const zgui = @import("zgui");
const root = @import("root");
const AK = @import("wwise-zig");

allocator: std.mem.Allocator = undefined,
subtitle_text: [:0]const u8 = undefined,
subtitle_index: u32 = 0,
subtitle_position: u32 = 0,
playing_id: AK.AkPlayingID = 0,
is_playing: bool = false,
is_visible: bool = false,
bank_id: AK.AkBankID = AK.AK_INVALID_BANK_ID,

const Self = @This();

const DemoGameObjectID: AK.AkGameObjectID = 2;

pub fn init(self: *Self, allocator: std.mem.Allocator, demo_state: *root.DemoState) !void {
    _ = demo_state;
    self.* = .{
        .allocator = allocator,
        .subtitle_text = try allocator.dupeZ(u8, ""),
    };

    self.bank_id = try AK.SoundEngine.loadBankString(allocator, "MarkerTest.bnk", .{});
    try AK.SoundEngine.registerGameObjWithName(allocator, DemoGameObjectID, "SubtitleDemo");
}

pub fn deinit(self: *Self, demo_state: *root.DemoState) void {
    _ = demo_state;
    AK.SoundEngine.unloadBankID(self.bank_id, null, .{}) catch {};

    AK.SoundEngine.unregisterGameObj(DemoGameObjectID) catch {};

    self.allocator.free(self.subtitle_text);

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self, demo_state: *root.DemoState) !void {
    _ = demo_state;
    if (zgui.begin("Subtitle Demo", .{ .popen = &self.is_visible, .flags = .{ .always_auto_resize = true } })) {
        if (self.is_playing) {
            zgui.text("--Playing--", .{});
        } else {
            if (zgui.button("Play Markers", .{ .w = 120 })) {
                self.playing_id = try AK.SoundEngine.postEventString(self.allocator, "Play_Markers_Test", DemoGameObjectID, .{
                    .flags = .{
                        .marker = true,
                        .end_of_event = true,
                        .enable_get_source_play_position = true,
                    },
                    .callback = WwiseSubtitleCallback,
                    .cookie = self,
                });
                self.is_playing = true;
            }
        }

        if (!std.mem.eql(u8, self.subtitle_text, "")) {
            const play_position = AK.SoundEngine.getSourcePlayPosition(self.playing_id, true) catch 0;

            zgui.text("Cue #{}, Sample #{}", .{ self.subtitle_index, self.subtitle_position });
            zgui.text("Time: {} ms", .{play_position});
            zgui.text("{s}", .{self.subtitle_text});
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

pub fn setSubtitleText(self: *Self, text: [*:0]const u8) void {
    self.allocator.free(self.subtitle_text);
    self.subtitle_text = self.allocator.dupeZ(u8, text[0..std.mem.len(text)]) catch unreachable;
}

fn WwiseSubtitleCallback(in_type: AK.AkCallbackType, in_callback_info: *AK.AkCallbackInfo) callconv(.C) void {
    if (in_type.marker) {
        if (in_callback_info.cookie) |cookie| {
            var self = @ptrCast(*Self, @alignCast(@alignOf(*Self), cookie));
            var marker_callback = @ptrCast(*AK.AkMarkerCallbackInfo, in_callback_info);

            if (marker_callback.str_label) |label| {
                self.setSubtitleText(label);
            }

            self.subtitle_index = marker_callback.identifier;
            self.subtitle_position = marker_callback.position;
        }
    } else if (in_type.end_of_event) {
        if (in_callback_info.cookie) |cookie| {
            var self = @ptrCast(*Self, @alignCast(@alignOf(*Self), cookie));

            self.setSubtitleText("");
            self.subtitle_index = 0;
            self.subtitle_position = 0;
            self.playing_id = AK.AK_INVALID_PLAYING_ID;
            self.is_playing = false;
        }
    }
}
