const std = @import("std");
const DemoInterface = @import("../DemoInterface.zig");
const zgui = @import("zgui");
const AK = @import("wwise-zig");
const ID = @import("../ID.zig");

allocator: std.mem.Allocator = undefined,
is_visible: bool = false,
bank_id: AK.AkBankID = AK.AK_INVALID_BANK_ID,
is_paused: bool = false,
test_in_progress: bool = false,
set_index: u8 = 0,
playing_id: AK.AkPlayingID = AK.AK_INVALID_PLAYING_ID,
ticks_to_wait: u32 = 0,
next_function: NextFunctionFn = null,
set14_param_index: i32 = 0,
set14_custom_params: [3]?*anyopaque = [_]?*anyopaque{ @intToPtr(?*anyopaque, 123), @intToPtr(?*anyopaque, 456), @intToPtr(?*anyopaque, 789) },
set15_items_played: i32 = 0,
set16_seq1_playing_id: AK.AkPlayingID = AK.AK_INVALID_PLAYING_ID,
set16_seq2_playing_id: AK.AkPlayingID = AK.AK_INVALID_PLAYING_ID,
set17_done_playing: bool = false,
set17_custom_params: [6]?*anyopaque = [_]?*anyopaque{ @intToPtr(?*anyopaque, 123), @intToPtr(?*anyopaque, 456), @intToPtr(?*anyopaque, 789), @intToPtr(?*anyopaque, 321), @intToPtr(?*anyopaque, 654), @intToPtr(?*anyopaque, 987) },

const Self = @This();

const DemoGameObjectID: AK.AkGameObjectID = 100;

const NextFunctionFn = ?*const fn (self: *Self) anyerror!void;

const Captions = [_][:0]const u8{
    "",
    "Test 1 - Playing a simple dynamic sequence (using IDs).",
    "Test 2 - Playing a simple dynamic sequence (using strings).",
    "Test 3 - Add an item during playback.",
    "Test 4 - Insert an item into the list during playback.",
    "Test 5 - Add an item to an empty list during playback.",
    "Test 6 - Using the Stop call.",
    "Test 7 - Using the Break call.",
    "Test 8 - Using the Pause and Resume calls.",
    "Test 9 - Using a Delay when queueing to a playlist.",
    "Test 10 - Clearing the playlist during playback.",
    "Test 11 - Stopping the playlist and clearing it.",
    "Test 12 - Breaking the playlist and clearing it.",
    "Test 13 - Pausing the playlist and clearing it.",
    "Test 14 - Using a callback with custom parameters.",
    "Test 15 - Using a callback to cancel after 3 items play.",
    "Test 16 - Using a callback to play 2 items in sequence.",
    "Test 17 - Checking playlist content during playback.",
    "Test 18 - Using events with Dynamic Dialogue.",
};

pub fn init(self: *Self, allocator: std.mem.Allocator) !void {
    self.* = .{
        .allocator = allocator,
    };

    self.bank_id = try AK.SoundEngine.loadBankString(allocator, "DynamicDialogue.bnk", .{});

    try AK.SoundEngine.registerGameObjWithName(allocator, DemoGameObjectID, "Radio");
}

pub fn deinit(self: *Self) void {
    self.stopAndReleaseTests() catch {};

    AK.SoundEngine.unregisterGameObj(DemoGameObjectID) catch {};

    AK.SoundEngine.unloadBankID(self.bank_id, null, .{}) catch {};

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self) !void {
    try self.update();

    zgui.setNextWindowSize(.{
        .w = 570,
        .h = 120,
        .cond = .always,
    });

    if (zgui.begin("Dynamic Dialogue Demo", .{ .popen = &self.is_visible, .flags = .{ .always_auto_resize = true } })) {
        if (self.next_function == null and !self.test_in_progress) {
            if (zgui.button("Start Tests", .{})) {
                self.set_index = 0;
                self.next_function = set1_1_SimpleSequenceUsingID;
                self.is_paused = false;
            }
        } else {
            if (self.is_paused) {
                if (zgui.button("Resume Tests", .{})) {
                    self.is_paused = !self.is_paused;
                }
            } else {
                if (zgui.button("Pause After Current Test", .{})) {
                    self.is_paused = !self.is_paused;
                }
            }
        }

        if (zgui.button("Reset", .{})) {
            try self.stopAndReleaseTests();
        }

        if (self.set_index > 0) {
            zgui.text("Now Playing:", .{});
            zgui.text("{s}", .{Captions[self.set_index]});
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

fn update(self: *Self) !void {
    if (self.ticks_to_wait > 0) {
        self.ticks_to_wait -= 1;
    } else {
        if (!self.is_paused or self.test_in_progress) {
            if (self.next_function) |next_function| {
                try next_function(self);
            }
        }
    }
}

fn wait(self: *Self, time_ms: u32) void {
    self.ticks_to_wait = time_ms * 60 / 1000;
}

fn stopAndReleaseTests(self: *Self) !void {
    if (self.set_index == 15) {
        var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.set16_seq1_playing_id);
        if (playlist_opt) |playlist| {
            try AK.SoundEngine.DynamicSequence.stop(self.set16_seq1_playing_id, .{});
            playlist.removeAll();
            try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.set16_seq1_playing_id);
            try AK.SoundEngine.DynamicSequence.close(self.set16_seq1_playing_id);
        }

        playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.set16_seq2_playing_id);
        if (playlist_opt) |playlist| {
            try AK.SoundEngine.DynamicSequence.stop(self.set16_seq2_playing_id, .{});
            playlist.removeAll();
            try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.set16_seq2_playing_id);
            try AK.SoundEngine.DynamicSequence.close(self.set16_seq2_playing_id);
        }
    } else if (self.playing_id != 0) {
        var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
        if (playlist_opt) |playlist| {
            try AK.SoundEngine.DynamicSequence.stop(self.playing_id, .{});
            playlist.removeAll();
            try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
            try AK.SoundEngine.DynamicSequence.close(self.playing_id);
        }
    }

    self.set_index = 0;
    self.next_function = null;
    self.is_paused = false;
    self.test_in_progress = false;
    self.ticks_to_wait = 0;
}

fn set1_1_SimpleSequenceUsingID(self: *Self) !void {
    self.test_in_progress = true;
    self.next_function = null;
    self.set_index += 1;

    self.playing_id = AK.SoundEngine.DynamicSequence.open(DemoGameObjectID, .{});

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(
            ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS,
            &.{
                ID.STATES.UNIT.STATE.UNIT_B,
                AK.AK_FALLBACK_ARGUMENTVALUE_ID,
                ID.STATES.OBJECTIVESTATUS.STATE.COMPLETED,
            },
            .{},
        );
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});
        try playlist.enqueue(audio_node_id, .{});

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});

    try AK.SoundEngine.DynamicSequence.close(self.playing_id);
    self.playing_id = 0;

    self.test_in_progress = false;
    self.next_function = set2_1_simpleSequenceUsingString;
    self.wait(5000);
}

fn set2_1_simpleSequenceUsingString(self: *Self) !void {
    self.test_in_progress = true;
    self.next_function = null;
    self.set_index += 1;

    self.playing_id = AK.SoundEngine.DynamicSequence.open(DemoGameObjectID, .{});

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = try AK.SoundEngine.DynamicDialogue.resolveDialogueEventString(self.allocator, "WalkieTalkie", &[_][]const u8{"Comm_In"}, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = try AK.SoundEngine.DynamicDialogue.resolveDialogueEventString(
            self.allocator,
            "Unit_Under_Attack",
            &[_][]const u8{
                "Unit_A",
                "Gang",
                "Hangar",
            },
            .{},
        );
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = try AK.SoundEngine.DynamicDialogue.resolveDialogueEventString(self.allocator, "WalkieTalkie", &[_][]const u8{"Comm_Out"}, .{});
        try playlist.enqueue(audio_node_id, .{});

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});
    try AK.SoundEngine.DynamicSequence.close(self.playing_id);
    self.playing_id = 0;

    self.test_in_progress = false;
    self.next_function = set3_1_startPlayback;
    self.wait(5000);
}

fn set3_1_startPlayback(self: *Self) !void {
    self.test_in_progress = true;
    self.next_function = null;
    self.set_index += 1;

    self.playing_id = AK.SoundEngine.DynamicSequence.open(DemoGameObjectID, .{});

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(
            ID.DIALOGUE_EVENTS.UNIT_UNDER_ATTACK,
            &.{
                ID.STATES.UNIT.STATE.UNIT_A,
                ID.STATES.HOSTILE.STATE.BUM,
                ID.STATES.LOCATION.STATE.STREET,
            },
            .{},
        );
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});
        try playlist.enqueue(audio_node_id, .{});

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});

    self.wait(500);
    self.next_function = set3_2_AddItemToPlaylist;
}

fn set3_2_AddItemToPlaylist(self: *Self) !void {
    self.next_function = null;

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(
            ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS,
            &.{
                ID.STATES.UNIT.STATE.UNIT_B,
                ID.STATES.OBJECTIVE.STATE.NEUTRALIZEHOSTILE,
                ID.STATES.OBJECTIVESTATUS.STATE.FAILED,
            },
            .{},
        );
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});
        try playlist.enqueue(audio_node_id, .{});

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.close(self.playing_id);
    self.playing_id = 0;

    self.test_in_progress = false;
    self.next_function = set41_startPlayback;
    self.wait(5000);
}

fn set41_startPlayback(self: *Self) !void {
    self.test_in_progress = true;
    self.next_function = null;
    self.set_index += 1;

    self.playing_id = AK.SoundEngine.DynamicSequence.open(DemoGameObjectID, .{});

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(
            ID.DIALOGUE_EVENTS.UNIT_UNDER_ATTACK,
            &.{
                ID.STATES.UNIT.STATE.UNIT_B,
                AK.AK_FALLBACK_ARGUMENTVALUE_ID,
                AK.AK_FALLBACK_ARGUMENTVALUE_ID,
            },
            .{},
        );
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(
            ID.DIALOGUE_EVENTS.UNIT_UNDER_ATTACK,
            &.{
                ID.STATES.UNIT.STATE.UNIT_A,
                AK.AK_FALLBACK_ARGUMENTVALUE_ID,
                ID.STATES.LOCATION.STATE.HANGAR,
            },
            .{},
        );
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});
        try playlist.enqueue(audio_node_id, .{});

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});

    self.wait(500);
    self.next_function = set4_2_InsertItemsToPlaylist;
}

fn set4_2_InsertItemsToPlaylist(self: *Self) !void {
    self.next_function = null;

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
        try playlist.enqueue(audio_node_id, .{});

        var playlist_item_opt = playlist.insert(0);
        if (playlist_item_opt) |playlist_item| {
            playlist_item.audio_node_id = audio_node_id;
            playlist_item.ms_delay = 0;
            playlist_item.custom_info = null;
        }

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(
            ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS,
            &.{
                ID.STATES.UNIT.STATE.UNIT_B,
                ID.STATES.OBJECTIVE.STATE.NEUTRALIZEHOSTILE,
                ID.STATES.OBJECTIVESTATUS.STATE.FAILED,
            },
            .{},
        );

        playlist_item_opt = playlist.insert(1);
        if (playlist_item_opt) |playlist_item| {
            playlist_item.audio_node_id = audio_node_id;
            playlist_item.ms_delay = 0;
            playlist_item.custom_info = null;
        }

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});

        playlist_item_opt = playlist.insert(2);
        if (playlist_item_opt) |playlist_item| {
            playlist_item.audio_node_id = audio_node_id;
            playlist_item.ms_delay = 0;
            playlist_item.custom_info = null;
        }

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.close(self.playing_id);
    self.playing_id = 0;

    self.test_in_progress = false;
    self.next_function = set5_1_StartEmptyPlaylist;
    self.wait(10000);
}

fn set5_1_StartEmptyPlaylist(self: *Self) !void {
    self.test_in_progress = true;
    self.next_function = null;
    self.set_index += 1;

    self.playing_id = AK.SoundEngine.DynamicSequence.open(DemoGameObjectID, .{});

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});

    self.wait(500);
    self.next_function = set5_2_AddItemsToPlaylist;
}

fn set5_2_AddItemsToPlaylist(self: *Self) !void {
    self.next_function = null;

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.UNIT_UNDER_ATTACK, &.{
            ID.STATES.UNIT.STATE.UNIT_B,
            ID.STATES.HOSTILE.STATE.GANG,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});
        try playlist.enqueue(audio_node_id, .{});

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    self.next_function = set5_3_WaitForEmptyListThenAdd;
}

fn set5_3_WaitForEmptyListThenAdd(self: *Self) !void {
    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        if (playlist.isEmpty()) {
            var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
            try playlist.enqueue(audio_node_id, .{});

            audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
                ID.STATES.UNIT.STATE.UNIT_A,
                ID.STATES.OBJECTIVE.STATE.DEFUSEBOMB,
                ID.STATES.OBJECTIVESTATUS.STATE.FAILED,
            }, .{});
            try playlist.enqueue(audio_node_id, .{});

            audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});
            try playlist.enqueue(audio_node_id, .{});

            try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);

            try AK.SoundEngine.DynamicSequence.close(self.playing_id);
            self.playing_id = 0;

            self.test_in_progress = false;
            self.next_function = set6_1_StartPlayback;
            self.wait(5000);
        } else {
            try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);

            self.wait(200);
        }
    } else {
        self.wait(200);
    }
}

fn set6_1_StartPlayback(self: *Self) !void {
    self.test_in_progress = true;
    self.next_function = null;
    self.set_index += 1;

    self.playing_id = AK.SoundEngine.DynamicSequence.open(DemoGameObjectID, .{});

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.UNIT_UNDER_ATTACK, &.{
            ID.STATES.UNIT.STATE.UNIT_A,
            ID.STATES.HOSTILE.STATE.BUM,
            ID.STATES.LOCATION.STATE.STREET,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.UNIT_UNDER_ATTACK, &.{
            ID.STATES.UNIT.STATE.UNIT_B,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
            ID.STATES.LOCATION.STATE.HANGAR,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_A,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
            ID.STATES.OBJECTIVESTATUS.STATE.FAILED,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});
        try playlist.enqueue(audio_node_id, .{});

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});

    self.wait(1000);
    self.next_function = set6_2_CallingStop;
}

fn set6_2_CallingStop(self: *Self) !void {
    self.next_function = null;

    try AK.SoundEngine.DynamicSequence.stop(self.playing_id, .{});

    self.wait(2000);
    self.next_function = set6_3_ResumePlayingAfterStop;
}

fn set6_3_ResumePlayingAfterStop(self: *Self) !void {
    self.next_function = null;

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});

    try AK.SoundEngine.DynamicSequence.close(self.playing_id);
    self.playing_id = 0;

    self.test_in_progress = false;
    self.next_function = set7_1_StartPlayback;
    self.wait(4000);
}

fn set7_1_StartPlayback(self: *Self) !void {
    self.test_in_progress = true;
    self.next_function = null;
    self.set_index += 1;

    self.playing_id = AK.SoundEngine.DynamicSequence.open(DemoGameObjectID, .{});

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.UNIT_UNDER_ATTACK, &.{
            ID.STATES.UNIT.STATE.UNIT_A,
            ID.STATES.HOSTILE.STATE.BUM,
            ID.STATES.LOCATION.STATE.STREET,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.UNIT_UNDER_ATTACK, &.{
            ID.STATES.UNIT.STATE.UNIT_B,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
            ID.STATES.LOCATION.STATE.HANGAR,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_A,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
            ID.STATES.OBJECTIVESTATUS.STATE.FAILED,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});
        try playlist.enqueue(audio_node_id, .{});

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});

    self.wait(1000);
    self.next_function = set7_2_CallingBreak;
}

fn set7_2_CallingBreak(self: *Self) !void {
    self.next_function = null;

    try AK.SoundEngine.DynamicSequence.@"break"(self.playing_id);

    self.wait(4000);
    self.next_function = set7_3_ResumePlayingAfterBreak;
}

fn set7_3_ResumePlayingAfterBreak(self: *Self) !void {
    self.next_function = null;

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});

    try AK.SoundEngine.DynamicSequence.close(self.playing_id);
    self.playing_id = 0;

    self.test_in_progress = false;
    self.next_function = set8_1_StartPlayback;
    self.wait(5000);
}

fn set8_1_StartPlayback(self: *Self) !void {
    self.test_in_progress = true;
    self.next_function = null;
    self.set_index += 1;

    self.playing_id = AK.SoundEngine.DynamicSequence.open(DemoGameObjectID, .{});

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.UNIT_UNDER_ATTACK, &.{
            ID.STATES.UNIT.STATE.UNIT_A,
            ID.STATES.HOSTILE.STATE.BUM,
            ID.STATES.LOCATION.STATE.STREET,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.UNIT_UNDER_ATTACK, &.{
            ID.STATES.UNIT.STATE.UNIT_B,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
            ID.STATES.LOCATION.STATE.HANGAR,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_A,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
            ID.STATES.OBJECTIVESTATUS.STATE.FAILED,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});
        try playlist.enqueue(audio_node_id, .{});

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});

    self.wait(1000);
    self.next_function = set8_2_CallingPause;
}

fn set8_2_CallingPause(self: *Self) !void {
    self.next_function = null;

    try AK.SoundEngine.DynamicSequence.pause(self.playing_id, .{});

    self.wait(2000);
    self.next_function = set8_3_CallingResumeAfterPause;
}

fn set8_3_CallingResumeAfterPause(self: *Self) !void {
    self.next_function = null;

    try AK.SoundEngine.DynamicSequence.@"resume"(self.playing_id, .{});

    try AK.SoundEngine.DynamicSequence.close(self.playing_id);
    self.playing_id = 0;

    self.test_in_progress = false;
    self.next_function = set9_1_UsingDelay;
    self.wait(8000);
}

fn set9_1_UsingDelay(self: *Self) !void {
    self.test_in_progress = true;
    self.next_function = null;
    self.set_index += 1;

    self.playing_id = AK.SoundEngine.DynamicSequence.open(DemoGameObjectID, .{});

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_A,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
        }, .{});
        try playlist.enqueue(audio_node_id, .{ .ms_delay = 300 });

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.UNIT_UNDER_ATTACK, &.{
            ID.STATES.UNIT.STATE.UNIT_A,
            ID.STATES.HOSTILE.STATE.GANG,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
        }, .{});
        try playlist.enqueue(audio_node_id, .{ .ms_delay = 1500 });

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});
        try playlist.enqueue(audio_node_id, .{ .ms_delay = 400 });

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});

    try AK.SoundEngine.DynamicSequence.close(self.playing_id);
    self.playing_id = 0;

    self.test_in_progress = false;
    self.next_function = set10_1_StartPlayback;
    self.wait(7000);
}

fn set10_1_StartPlayback(self: *Self) !void {
    self.test_in_progress = true;
    self.next_function = null;
    self.set_index += 1;

    self.playing_id = AK.SoundEngine.DynamicSequence.open(DemoGameObjectID, .{});

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_A,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
        }, .{});
        try playlist.enqueue(audio_node_id, .{ .ms_delay = 300 });

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.UNIT_UNDER_ATTACK, &.{
            ID.STATES.UNIT.STATE.UNIT_A,
            ID.STATES.HOSTILE.STATE.GANG,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
        }, .{});
        try playlist.enqueue(audio_node_id, .{ .ms_delay = 1500 });

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});
        try playlist.enqueue(audio_node_id, .{ .ms_delay = 400 });

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});

    try AK.SoundEngine.DynamicSequence.close(self.playing_id);
    self.playing_id = 0;

    self.test_in_progress = false;
    self.next_function = set11_1_StartPlayback;
    self.wait(7000);
}

fn set11_1_StartPlayback(self: *Self) !void {
    self.test_in_progress = true;
    self.next_function = null;
    self.set_index += 1;

    self.playing_id = AK.SoundEngine.DynamicSequence.open(DemoGameObjectID, .{});

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.UNIT_UNDER_ATTACK, &.{
            ID.STATES.UNIT.STATE.UNIT_B,
            ID.STATES.HOSTILE.STATE.GANG,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.UNIT_UNDER_ATTACK, &.{
            ID.STATES.UNIT.STATE.UNIT_A,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
            ID.STATES.LOCATION.STATE.ALLEY,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_B,
            ID.STATES.OBJECTIVE.STATE.NEUTRALIZEHOSTILE,
            ID.STATES.OBJECTIVESTATUS.STATE.COMPLETED,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});
        try playlist.enqueue(audio_node_id, .{});

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});

    self.wait(1000);
    self.next_function = set11_2_StopAndClearPlaylist;
}

fn set11_2_StopAndClearPlaylist(self: *Self) !void {
    self.next_function = null;

    try AK.SoundEngine.DynamicSequence.stop(self.playing_id, .{});

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        playlist.removeAll();
        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});

    try AK.SoundEngine.DynamicSequence.close(self.playing_id);
    self.playing_id = 0;

    self.test_in_progress = false;
    self.next_function = set12_1_StartPlayback;
    self.wait(3500);
}

fn set12_1_StartPlayback(self: *Self) !void {
    self.test_in_progress = true;
    self.next_function = null;
    self.set_index += 1;

    self.playing_id = AK.SoundEngine.DynamicSequence.open(DemoGameObjectID, .{});

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.UNIT_UNDER_ATTACK, &.{
            ID.STATES.UNIT.STATE.UNIT_B,
            ID.STATES.HOSTILE.STATE.GANG,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.UNIT_UNDER_ATTACK, &.{
            ID.STATES.UNIT.STATE.UNIT_A,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
            ID.STATES.LOCATION.STATE.ALLEY,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_B,
            ID.STATES.OBJECTIVE.STATE.NEUTRALIZEHOSTILE,
            ID.STATES.OBJECTIVESTATUS.STATE.COMPLETED,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});
        try playlist.enqueue(audio_node_id, .{});

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});

    self.wait(500);
    self.next_function = set12_2_BreakAndClearPlaylist;
}

fn set12_2_BreakAndClearPlaylist(self: *Self) !void {
    self.next_function = null;

    try AK.SoundEngine.DynamicSequence.@"break"(self.playing_id);

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        playlist.removeAll();

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});

    try AK.SoundEngine.DynamicSequence.close(self.playing_id);
    self.playing_id = 0;

    self.test_in_progress = false;
    self.next_function = set13_1_StartPlayback;
    self.wait(5500);
}

fn set13_1_StartPlayback(self: *Self) !void {
    self.test_in_progress = true;
    self.next_function = null;
    self.set_index += 1;

    self.playing_id = AK.SoundEngine.DynamicSequence.open(DemoGameObjectID, .{ .dynamic_sequence_type = .normal_transition });

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.UNIT_UNDER_ATTACK, &.{
            ID.STATES.UNIT.STATE.UNIT_B,
            ID.STATES.HOSTILE.STATE.GANG,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.UNIT_UNDER_ATTACK, &.{
            ID.STATES.UNIT.STATE.UNIT_A,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
            ID.STATES.LOCATION.STATE.ALLEY,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_B,
            ID.STATES.OBJECTIVE.STATE.NEUTRALIZEHOSTILE,
            ID.STATES.OBJECTIVESTATUS.STATE.COMPLETED,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});
        try playlist.enqueue(audio_node_id, .{});

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});

    self.wait(1000);
    self.next_function = set13_2_PausePlaylist;
}

fn set13_2_PausePlaylist(self: *Self) !void {
    self.next_function = null;

    try AK.SoundEngine.DynamicSequence.pause(self.playing_id, .{});

    self.wait(2000);
    self.next_function = set13_3_ClearAndResumePlaylist;
}

fn set13_3_ClearAndResumePlaylist(self: *Self) !void {
    self.next_function = null;

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        playlist.removeAll();

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.@"resume"(self.playing_id, .{});

    try AK.SoundEngine.DynamicSequence.close(self.playing_id);
    self.playing_id = 0;

    self.test_in_progress = false;
    self.next_function = set14_1_StartPlaybackWithCallback;
    self.wait(4000);
}

fn set14_1_StartPlaybackWithCallback(self: *Self) !void {
    self.test_in_progress = true;
    self.next_function = null;
    self.set_index += 1;

    self.set14_param_index = 0;

    self.playing_id = AK.SoundEngine.DynamicSequence.open(DemoGameObjectID, .{
        .flags = .{
            .end_of_event = true,
            .end_of_dynamic_sequence_item = true,
        },
        .callback = set14_Callback,
        .cookie = self,
    });

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
        try playlist.enqueue(audio_node_id, .{
            .custom_info = self.set14_custom_params[0],
        });

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_B,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
        }, .{});
        try playlist.enqueue(audio_node_id, .{
            .custom_info = self.set14_custom_params[1],
        });

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});
        try playlist.enqueue(audio_node_id, .{
            .custom_info = self.set14_custom_params[2],
        });

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});

    try AK.SoundEngine.DynamicSequence.close(self.playing_id);
    self.playing_id = 0;
}

fn set14_Callback(in_type: AK.AkCallbackType, in_callback_info: *AK.AkCallbackInfo) callconv(.C) void {
    var self = @ptrCast(*Self, @alignCast(@alignOf(*Self), in_callback_info.cookie));

    if (in_type.end_of_dynamic_sequence_item) {
        self.set14_param_index += 1;
    } else if (in_type.end_of_event) {
        self.test_in_progress = false;
        self.next_function = set15_1_StartPlaybackWithCallback;
        self.wait(2000);
    }
}

fn set15_1_StartPlaybackWithCallback(self: *Self) !void {
    self.test_in_progress = true;
    self.next_function = null;
    self.set_index += 1;
    self.set15_items_played = 0;

    self.playing_id = AK.SoundEngine.DynamicSequence.open(DemoGameObjectID, .{
        .flags = .{
            .end_of_event = true,
            .end_of_dynamic_sequence_item = true,
        },
        .callback = set15_Callback,
        .cookie = self,
    });

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_B,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
            ID.STATES.OBJECTIVESTATUS.STATE.COMPLETED,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_B,
            ID.STATES.OBJECTIVE.STATE.NEUTRALIZEHOSTILE,
            ID.STATES.OBJECTIVESTATUS.STATE.FAILED,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_A,
            ID.STATES.OBJECTIVE.STATE.RESCUEHOSTAGE,
            ID.STATES.OBJECTIVESTATUS.STATE.FAILED,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_A,
            ID.STATES.OBJECTIVE.STATE.DEFUSEBOMB,
            ID.STATES.OBJECTIVESTATUS.STATE.FAILED,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});
        try playlist.enqueue(audio_node_id, .{});

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});
}

fn set15_Callback(in_type: AK.AkCallbackType, in_callback_info: *AK.AkCallbackInfo) callconv(.C) void {
    var self = @ptrCast(*Self, @alignCast(@alignOf(*Self), in_callback_info.cookie));

    if (in_type.end_of_dynamic_sequence_item) {
        self.set15_items_played += 1;

        if (self.set15_items_played == 2) {
            var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
            if (playlist_opt) |playlist| {
                const last_audio_node = playlist.last().audio_node_id;

                playlist.removeAll();

                playlist.enqueue(last_audio_node, .{}) catch unreachable;

                AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id) catch unreachable;
            }

            AK.SoundEngine.DynamicSequence.close(self.playing_id) catch unreachable;

            self.test_in_progress = false;
            self.next_function = set16_1_StartPlaybackWithCallback;
            self.wait(2000);
        }
    }
}

fn set16_1_StartPlaybackWithCallback(self: *Self) !void {
    self.test_in_progress = true;
    self.next_function = null;
    self.set_index += 1;

    self.set16_seq1_playing_id = AK.SoundEngine.DynamicSequence.open(DemoGameObjectID, .{
        .flags = .{
            .end_of_event = true,
        },
        .callback = set16_Callback,
        .cookie = self,
    });

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.set16_seq1_playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_B,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
            ID.STATES.OBJECTIVESTATUS.STATE.COMPLETED,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});
        try playlist.enqueue(audio_node_id, .{});

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.set16_seq1_playing_id);
    }

    self.set16_seq2_playing_id = AK.SoundEngine.DynamicSequence.open(DemoGameObjectID, .{
        .flags = .{
            .end_of_event = true,
        },
        .callback = set16_Callback,
        .cookie = self,
    });

    playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.set16_seq2_playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.UNIT_UNDER_ATTACK, &.{
            ID.STATES.UNIT.STATE.UNIT_A,
            ID.STATES.HOSTILE.STATE.BUM,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});
        try playlist.enqueue(audio_node_id, .{});

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.set16_seq2_playing_id);
    }

    try AK.SoundEngine.DynamicSequence.play(self.set16_seq1_playing_id, .{});
    try AK.SoundEngine.DynamicSequence.close(self.set16_seq1_playing_id);
}

fn set16_Callback(in_type: AK.AkCallbackType, in_callback_info: *AK.AkCallbackInfo) callconv(.C) void {
    var self = @ptrCast(*Self, @alignCast(@alignOf(*Self), in_callback_info.cookie));
    const event_info = @ptrCast(*AK.AkEventCallbackInfo, in_callback_info);

    if (in_type.end_of_event and event_info.playing_id == self.set16_seq1_playing_id) {
        AK.SoundEngine.DynamicSequence.play(self.set16_seq2_playing_id, .{}) catch unreachable;
        AK.SoundEngine.DynamicSequence.close(self.set16_seq2_playing_id) catch unreachable;

        self.test_in_progress = false;
        self.next_function = set17_1_StartPlaybackWithCallback;
        self.wait(5000);
    }
}

fn set17_1_StartPlaybackWithCallback(self: *Self) !void {
    self.test_in_progress = true;
    self.next_function = null;
    self.set_index += 1;
    self.set17_done_playing = false;

    self.playing_id = AK.SoundEngine.DynamicSequence.open(DemoGameObjectID, .{
        .flags = .{
            .end_of_dynamic_sequence_item = true,
        },
        .callback = set17_Callback,
        .cookie = self,
    });

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
        try playlist.enqueue(audio_node_id, .{ .custom_info = self.set17_custom_params[0] });

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_B,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
            ID.STATES.OBJECTIVESTATUS.STATE.COMPLETED,
        }, .{});
        try playlist.enqueue(audio_node_id, .{ .custom_info = self.set17_custom_params[1] });

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_B,
            ID.STATES.OBJECTIVE.STATE.NEUTRALIZEHOSTILE,
            ID.STATES.OBJECTIVESTATUS.STATE.FAILED,
        }, .{});
        try playlist.enqueue(audio_node_id, .{ .custom_info = self.set17_custom_params[2] });

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_A,
            ID.STATES.OBJECTIVE.STATE.RESCUEHOSTAGE,
            ID.STATES.OBJECTIVESTATUS.STATE.FAILED,
        }, .{});
        try playlist.enqueue(audio_node_id, .{ .custom_info = self.set17_custom_params[3] });

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_A,
            ID.STATES.OBJECTIVE.STATE.DEFUSEBOMB,
            ID.STATES.OBJECTIVESTATUS.STATE.FAILED,
        }, .{});
        try playlist.enqueue(audio_node_id, .{ .custom_info = self.set17_custom_params[4] });

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});
        try playlist.enqueue(audio_node_id, .{ .custom_info = self.set17_custom_params[5] });

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});
}

fn set17_Callback(in_type: AK.AkCallbackType, in_callback_info: *AK.AkCallbackInfo) callconv(.C) void {
    var self = @ptrCast(*Self, @alignCast(@alignOf(*Self), in_callback_info.cookie));

    if (in_type.end_of_dynamic_sequence_item and !self.set17_done_playing) {
        var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
        if (playlist_opt) |playlist| {
            if (playlist.isEmpty()) {
                self.set17_done_playing = true;

                self.test_in_progress = false;

                AK.SoundEngine.DynamicSequence.close(self.playing_id) catch unreachable;
                self.next_function = set18_1_StartPlayback;
                self.wait(200);
            } else {
                const playlist_length = playlist.length();
                var custom_param_index = 6 - playlist_length;

                for (0..playlist_length) |i| {
                    if (self.set17_custom_params[custom_param_index] != playlist.at(@truncate(u32, i)).custom_info) {
                        std.log.err("Error: Params didn't match up!", .{});
                    }
                    custom_param_index += 1;
                }
            }

            AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id) catch unreachable;
        }
    }
}

fn set18_1_StartPlayback(self: *Self) !void {
    self.test_in_progress = true;
    self.next_function = null;
    self.set_index += 1;

    self.playing_id = AK.SoundEngine.DynamicSequence.open(DemoGameObjectID, .{ .dynamic_sequence_type = .normal_transition });

    var playlist_opt = AK.SoundEngine.DynamicSequence.lockPlaylist(self.playing_id);
    if (playlist_opt) |playlist| {
        var audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_IN}, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_B,
            AK.AK_FALLBACK_ARGUMENTVALUE_ID,
            ID.STATES.OBJECTIVESTATUS.STATE.COMPLETED,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_B,
            ID.STATES.OBJECTIVE.STATE.NEUTRALIZEHOSTILE,
            ID.STATES.OBJECTIVESTATUS.STATE.FAILED,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_A,
            ID.STATES.OBJECTIVE.STATE.RESCUEHOSTAGE,
            ID.STATES.OBJECTIVESTATUS.STATE.FAILED,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_A,
            ID.STATES.OBJECTIVE.STATE.DEFUSEBOMB,
            ID.STATES.OBJECTIVESTATUS.STATE.FAILED,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.OBJECTIVE_STATUS, &.{
            ID.STATES.UNIT.STATE.UNIT_B,
            ID.STATES.OBJECTIVE.STATE.DEFUSEBOMB,
            ID.STATES.OBJECTIVESTATUS.STATE.FAILED,
        }, .{});
        try playlist.enqueue(audio_node_id, .{});

        audio_node_id = AK.SoundEngine.DynamicDialogue.resolveDialogueEventID(ID.DIALOGUE_EVENTS.WALKIETALKIE, &.{ID.STATES.WALKIETALKIE.STATE.COMM_OUT}, .{});
        try playlist.enqueue(audio_node_id, .{});

        try AK.SoundEngine.DynamicSequence.unlockPlaylist(self.playing_id);
    }

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});

    self.wait(1000);
    self.next_function = set18_2_PostPauseEvent;
}

fn set18_2_PostPauseEvent(self: *Self) !void {
    self.next_function = null;

    _ = try AK.SoundEngine.postEventID(ID.EVENTS.PAUSE_ALL, DemoGameObjectID, .{});

    self.wait(3000);
    self.next_function = set18_3_PostResumeEvent;
}

fn set18_3_PostResumeEvent(self: *Self) !void {
    self.next_function = null;

    _ = try AK.SoundEngine.postEventID(ID.EVENTS.RESUME_ALL, DemoGameObjectID, .{});

    self.wait(2000);
    self.next_function = set18_4_PostStopEvent;
}

fn set18_4_PostStopEvent(self: *Self) !void {
    self.next_function = null;

    _ = try AK.SoundEngine.postEventID(ID.EVENTS.STOP_ALL, DemoGameObjectID, .{});

    self.wait(2000);
    self.next_function = set18_5_PlayRestOfSequence;
}

fn set18_5_PlayRestOfSequence(self: *Self) !void {
    self.next_function = null;

    try AK.SoundEngine.DynamicSequence.play(self.playing_id, .{});
    try AK.SoundEngine.DynamicSequence.close(self.playing_id);
    self.playing_id = 0;

    self.test_in_progress = false;
    self.next_function = stopAndReleaseTests;
    self.wait(6500);
}
