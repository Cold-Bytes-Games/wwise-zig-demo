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
playlist_item: u32 = 0,
stop_playlist: bool = false,

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
        ID.EVENTS.PLAYMUSICDEMO2,
        DemoGameObjectID,
        .{
            .flags = .{
                .music_playlist_select = true,
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
        .w = 275,
        .h = 70,
        .cond = .always,
    });

    if (zgui.begin("Music Playlist Callback Demo", .{ .popen = &self.is_visible, .flags = .{ .always_auto_resize = true } })) {
        if (self.is_playing) {
            zgui.text("Random playlist forced to sequential\nNext Index: {}", .{self.playlist_item});
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
    return DemoInterface{
        .instance = self,
        .initFn = @as(DemoInterface.InitFn, @ptrCast(&init)),
        .deinitFn = @as(DemoInterface.DeinitFn, @ptrCast(&deinit)),
        .onUIFn = @as(DemoInterface.OnUIFn, @ptrCast(&onUI)),
        .isVisibleFn = @as(DemoInterface.IsVisibleFn, @ptrCast(&isVisible)),
        .showFn = @as(DemoInterface.ShowFn, @ptrCast(&show)),
    };
}

fn MusicCallback(in_type: AK.AkCallbackType, in_callback_info: *AK.AkCallbackInfo) callconv(.C) void {
    var self = @as(*Self, @ptrCast(@alignCast(@alignOf(*Self), in_callback_info.cookie)));

    if (in_type.music_playlist_select) {
        const playlist_info = @as(*AK.AkMusicPlaylistCallbackInfo, @ptrCast(in_callback_info));
        playlist_info.playlist_item_done = @intFromBool(self.stop_playlist);
        playlist_info.playlist_selection = self.playlist_item;
        self.playlist_item += 1;

        if (self.playlist_item == playlist_info.num_playlist_items) {
            self.playlist_item = 0;
        }
    } else if (in_type.end_of_event) {
        self.is_playing = false;
        self.playlist_item = 0;
    }
}
