const std = @import("std");
const DemoInterface = @import("../DemoInterface.zig");
const zgui = @import("zgui");
const root = @import("root");
const AK = @import("wwise-zig");
const ID = @import("../ID.zig");

allocator: std.mem.Allocator = undefined,
is_visible: bool = false,
is_playing: bool = false,
bank_id: AK.AkBankID = AK.AK_INVALID_BANK_ID,
playing_id: AK.AkPlayingID = AK.AK_INVALID_PLAYING_ID,
beat_count: u32 = 0,
bar_count: u32 = 0,

const Self = @This();

const DemoGameObjectID: AK.AkGameObjectID = 100;

pub fn init(self: *Self, allocator: std.mem.Allocator, demo_state: *root.DemoState) !void {
    _ = demo_state;
    self.* = .{
        .allocator = allocator,
    };

    self.bank_id = try AK.SoundEngine.loadBankString(allocator, "MusicCallbacks.bnk", .{});
    try AK.SoundEngine.registerGameObjWithName(allocator, DemoGameObjectID, "Music");

    self.playing_id = try AK.SoundEngine.postEventID(
        ID.EVENTS.PLAYMUSICDEMO1,
        DemoGameObjectID,
        .{
            .flags = .{
                .enable_get_source_play_position = true,
                .music_sync_beat = true,
                .music_sync_bar = true,
                .music_sync_entry = true,
                .music_sync_exit = true,
                .end_of_event = true,
            },
            .callback = MusicCallback,
            .cookie = self,
        },
    );

    self.is_playing = true;
}

pub fn deinit(self: *Self, demo_state: *root.DemoState) void {
    _ = demo_state;
    AK.SoundEngine.cancelEventCallback(self.playing_id);

    AK.SoundEngine.stopPlayingID(self.playing_id, .{});

    AK.SoundEngine.unloadBankID(self.bank_id, null, .{}) catch {};

    AK.SoundEngine.unregisterGameObj(DemoGameObjectID) catch {};

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self, demo_state: *root.DemoState) !void {
    _ = demo_state;
    zgui.setNextWindowSize(.{
        .w = 215,
        .h = 80,
        .cond = .always,
    });

    if (zgui.begin("Music Sync Callback Demo", .{ .popen = &self.is_visible, .flags = .{ .always_auto_resize = true } })) {
        if (self.is_playing) {
            const position = AK.SoundEngine.getSourcePlayPosition(self.playing_id, true) catch 0;

            zgui.text("Bar: {}\nBeat: {}\nPosition={}", .{ self.bar_count, self.beat_count, position });
        } else {
            zgui.text("Test Finished", .{});
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

fn MusicCallback(in_type: AK.AkCallbackType, in_callback_info: *AK.AkCallbackInfo) callconv(.C) void {
    var self: *Self = @ptrCast(@alignCast(in_callback_info.cookie));

    if (in_type.music_sync_bar) {
        self.beat_count = 0;
        self.bar_count += 1;
    } else if (in_type.music_sync_beat) {
        self.beat_count += 1;
    } else if (in_type.end_of_event) {
        self.is_playing = false;
        self.beat_count = 0;
        self.bar_count = 0;
    }
}
