const std = @import("std");
const DemoInterface = @import("../DemoInterface.zig");
const zgui = @import("zgui");
const AK = @import("wwise-zig");
const ID = @import("../ID.zig");

allocator: std.mem.Allocator = undefined,
is_visible: bool = false,
bank_id: AK.AkBankID = AK.AK_INVALID_BANK_ID,
playing_id: AK.AkPlayingID = AK.AK_INVALID_PLAYING_ID,

const Self = @This();

const DemoGameObjectID: AK.AkGameObjectID = 100;

pub fn init(self: *Self, allocator: std.mem.Allocator) !void {
    self.* = .{
        .allocator = allocator,
    };

    self.bank_id = try AK.SoundEngine.loadBankString(allocator, "InteractiveMusic.bnk", .{});
    try AK.SoundEngine.registerGameObjWithName(allocator, DemoGameObjectID, "Music");

    self.playing_id = try AK.SoundEngine.postEventID(ID.EVENTS.IM_START, DemoGameObjectID, .{ .flags = .{ .enable_get_music_play_position = true } });
}

pub fn deinit(self: *Self) void {
    AK.SoundEngine.stopPlayingID(self.playing_id, .{});

    AK.SoundEngine.unregisterGameObj(DemoGameObjectID) catch {};

    AK.SoundEngine.unloadBankID(self.bank_id, null, .{}) catch {};

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self) !void {
    zgui.setNextWindowSize(.{
        .w = 210,
        .h = 310,
        .cond = .always,
    });

    if (zgui.begin("Interactive Music Demo", .{ .popen = &self.is_visible, .flags = .{ .always_auto_resize = true } })) {
        if (zgui.button("Explore", .{})) {
            _ = try AK.SoundEngine.postEventID(ID.EVENTS.IM_EXPLORE, DemoGameObjectID, .{});
        }

        if (zgui.button("Begin communication", .{})) {
            _ = try AK.SoundEngine.postEventID(ID.EVENTS.IM_COMMUNICATION_BEGIN, DemoGameObjectID, .{});
        }

        if (zgui.button("They are hostile", .{})) {
            _ = try AK.SoundEngine.postEventID(ID.EVENTS.IM_THEYAREHOSTILE, DemoGameObjectID, .{});
        }

        if (zgui.button("Fight one enemy", .{})) {
            _ = try AK.SoundEngine.postEventID(ID.EVENTS.IM_1_ONE_ENEMY_WANTS_TO_FIGHT, DemoGameObjectID, .{});
        }

        if (zgui.button("Fight two enemies", .{})) {
            _ = try AK.SoundEngine.postEventID(ID.EVENTS.IM_2_TWO_ENEMIES_WANT_TO_FIGHT, DemoGameObjectID, .{});
        }

        if (zgui.button("Surrounded by enemies", .{})) {
            _ = try AK.SoundEngine.postEventID(ID.EVENTS.IM_3_SURRONDED_BY_ENEMIES, DemoGameObjectID, .{});
        }

        if (zgui.button("Death is coming", .{})) {
            _ = try AK.SoundEngine.postEventID(ID.EVENTS.IM_4_DEATH_IS_COMING, DemoGameObjectID, .{});
        }

        if (zgui.button("Game Over", .{})) {
            _ = try AK.SoundEngine.postEventID(ID.EVENTS.IM_GAMEOVER, DemoGameObjectID, .{});
        }

        if (zgui.button("Win the fight", .{})) {
            _ = try AK.SoundEngine.postEventID(ID.EVENTS.IM_WINTHEFIGHT, DemoGameObjectID, .{});
        }

        var segment_info = AK.AkSegmentInfo{};
        AK.MusicEngine.getPlayingSegmentInfo(self.playing_id, &segment_info, true) catch {};

        zgui.text("Position: {}", .{segment_info.current_position});
        zgui.text("Segment duration: {}", .{segment_info.active_duration});
        zgui.text("Pre-Entry duration: {}", .{segment_info.pre_entry_duration});
        zgui.text("Post-Exit duration: {}", .{segment_info.post_exit_duration});

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
