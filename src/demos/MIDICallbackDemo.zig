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
by_note: AK.AkMidiNoteNo = 0,
by_velocity: u8 = 0,
by_cc: u8 = 0,
by_value: u8 = 0,

const Self = @This();

const DemoGameObjectID: AK.AkGameObjectID = 100;

const NoteArray = [_][]const u8{ "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" };
const NotesPerOctave = NoteArray.len;

pub fn init(self: *Self, allocator: std.mem.Allocator, demo_state: *root.DemoState) !void {
    _ = demo_state;
    self.* = .{
        .allocator = allocator,
    };

    self.bank_id = try AK.SoundEngine.loadBankString(allocator, "MusicCallbacks.bnk", .{});
    try AK.SoundEngine.registerGameObjWithName(allocator, DemoGameObjectID, "Music");

    self.playing_id = try AK.SoundEngine.postEventID(
        ID.EVENTS.PLAYMUSICDEMO3,
        DemoGameObjectID,
        .{
            .flags = .{
                .midi_event = true,
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
        .w = 200,
        .h = 85,
        .cond = .always,
    });

    if (zgui.begin("MIDI Callback Demo", .{ .popen = &self.is_visible, .flags = .{ .always_auto_resize = true } })) {
        if (self.is_playing) {
            var note_buffer: [10]u8 = undefined;
            const str_note = try midiNoteToString(self.by_note, &note_buffer);

            zgui.text("Last Note ON: {s}", .{str_note});
            zgui.text("Velocity: {}", .{self.by_velocity});
            zgui.text("Last CC #{}: {}", .{ self.by_cc, self.by_value });
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
        .initFn = @ptrCast(DemoInterface.InitFn, &init),
        .deinitFn = @ptrCast(DemoInterface.DeinitFn, &deinit),
        .onUIFn = @ptrCast(DemoInterface.OnUIFn, &onUI),
        .isVisibleFn = @ptrCast(DemoInterface.IsVisibleFn, &isVisible),
        .showFn = @ptrCast(DemoInterface.ShowFn, &show),
    };
}

fn MusicCallback(in_type: AK.AkCallbackType, in_callback_info: *AK.AkCallbackInfo) callconv(.C) void {
    var self = @ptrCast(*Self, @alignCast(@alignOf(*Self), in_callback_info.cookie));

    if (in_type.midi_event) {
        const midi_info = @ptrCast(*AK.AkMIDIEventCallbackInfo, in_callback_info);

        if (midi_info.midi_event.by_type == AK.AK_MIDI_EVENT_TYPE_CONTROLLER) {
            self.by_cc = midi_info.midi_event.message.cc.by_cc;
            self.by_value = midi_info.midi_event.message.cc.by_value;
        } else if (midi_info.midi_event.by_type == AK.AK_MIDI_EVENT_TYPE_NOTE_ON) {
            self.by_note = midi_info.midi_event.message.note_on_off.by_note;
            self.by_velocity = midi_info.midi_event.message.note_on_off.by_velocity;
        }
    } else if (in_type.end_of_event) {
        self.is_playing = false;
    }
}

fn midiNoteToString(in_note_num: i32, buffer: []u8) ![]u8 {
    var octave = @divTrunc(in_note_num, @as(i32, NotesPerOctave));
    const my_note = NoteArray[@intCast(usize, @rem(in_note_num, @as(i32, NotesPerOctave)))];

    octave -= 1;
    return try std.fmt.bufPrint(buffer, "{s}{}", .{ my_note, octave });
}
