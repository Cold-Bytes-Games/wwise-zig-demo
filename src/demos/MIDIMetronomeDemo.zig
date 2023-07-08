const std = @import("std");
const DemoInterface = @import("../DemoInterface.zig");
const zgui = @import("zgui");
const root = @import("root");
const AK = @import("wwise-zig");
const ID = @import("../ID.zig");

allocator: std.mem.Allocator = undefined,
is_visible: bool = false,
bank_id: AK.AkBankID = AK.AK_INVALID_BANK_ID,
post_counter: u32 = 0,
post_len_samples: u32 = 512,
samples_per_callback: u32 = 512,
callback_counter: u32 = 0,
ms_per_callback: f64 = 10.0,
inter_post_time_ms: f64 = 1000.0,
next_post_time_ms: f64 = 0.0,
playing_metronome: bool = false,
bpm: f32 = 60.0,
mutex: std.Thread.Mutex = .{},

const Self = @This();

const DemoGameObjectID: AK.AkGameObjectID = 100;

pub fn init(self: *Self, allocator: std.mem.Allocator, demo_state: *root.DemoState) !void {
    _ = demo_state;
    self.* = .{
        .allocator = allocator,
    };

    self.bank_id = try AK.SoundEngine.loadBankString(allocator, "Metronome.bnk", .{});
    try AK.SoundEngine.registerGameObjWithName(allocator, DemoGameObjectID, "Metronome");

    try self.prepareCallback();
}

pub fn deinit(self: *Self, demo_state: *root.DemoState) void {
    _ = demo_state;
    self.playing_metronome = false;

    releaseCallback() catch {};

    stopMIDIPosts() catch {};

    AK.SoundEngine.unregisterGameObj(DemoGameObjectID) catch {};

    AK.SoundEngine.unloadBankID(self.bank_id, null, .{}) catch {};

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self, demo_state: *root.DemoState) !void {
    _ = demo_state;
    zgui.setNextWindowSize(.{
        .w = 210,
        .h = 310,
        .cond = .always,
    });

    if (zgui.begin("MIDI API Demo (Metronome)", .{ .popen = &self.is_visible, .flags = .{ .always_auto_resize = true } })) {
        if (self.playing_metronome) {
            if (zgui.button("Stop Metronome", .{})) {
                self.playing_metronome = false;
            }
        } else {
            if (zgui.button("Start Metronome", .{})) {
                self.playing_metronome = true;
            }
        }

        if (zgui.sliderFloat("BPM:", .{
            .v = &self.bpm,
            .min = 1.0,
            .max = 960.0,
        })) {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.inter_post_time_ms = 60000.0 / @as(f64, @floatCast(self.bpm));

            const this_time_ms = @as(f64, @floatFromInt(self.callback_counter)) * self.ms_per_callback;
            const maybe_next_ms = this_time_ms + self.inter_post_time_ms;
            if (maybe_next_ms < self.next_post_time_ms) {
                self.next_post_time_ms = maybe_next_ms;
            }

            const post_length_ms = @min(self.ms_per_callback, self.inter_post_time_ms);
            self.post_len_samples = @as(u32, @intFromFloat((post_length_ms / self.ms_per_callback) * @as(f64, @floatFromInt(self.samples_per_callback))));
            self.post_len_samples = @min(self.post_len_samples, self.samples_per_callback);
        }

        zgui.end();
    }

    if (!self.is_visible) {
        try releaseCallback();

        try stopMIDIPosts();
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

fn prepareCallback(self: *Self) !void {
    var audio_settigns = AK.AkAudioSettings{};
    try AK.SoundEngine.getAudioSettings(&audio_settigns);

    self.samples_per_callback = audio_settigns.num_samples_per_frame;
    self.post_len_samples = @max(self.post_len_samples, self.samples_per_callback);
    self.callback_counter = 0;
    self.ms_per_callback = @as(f64, @floatFromInt(audio_settigns.num_samples_per_frame)) / @as(f64, @floatFromInt(audio_settigns.num_samples_per_second)) * 1000.0;
    self.next_post_time_ms = 0.0;

    try AK.SoundEngine.registerGlobalCallback(staticCallback, .{
        .location = .{ .pre_process_message_queue_for_render = true },
        .cookie = self,
    });
}

fn releaseCallback() !void {
    try AK.SoundEngine.unregisterGlobalCallback(staticCallback, .{ .location = .{ .pre_process_message_queue_for_render = true } });
}

fn objectCallback(self: *Self) !void {
    if (!self.playing_metronome) {
        return;
    }

    const this_time_ms = @as(f64, @floatFromInt(self.callback_counter)) * self.ms_per_callback;
    const next_time_ms = this_time_ms + self.ms_per_callback;

    if (this_time_ms > self.next_post_time_ms) {
        self.next_post_time_ms = this_time_ms;
    }

    if (self.next_post_time_ms >= this_time_ms and self.next_post_time_ms <= next_time_ms) {
        const percent_offset = (self.next_post_time_ms - this_time_ms) / self.ms_per_callback;
        const sample_offset = @as(u32, @intFromFloat(percent_offset * @as(f64, @floatFromInt(self.samples_per_callback))));

        try self.postMIDIEvents(sample_offset);

        self.next_post_time_ms += self.inter_post_time_ms;
    }

    self.callback_counter += 1;
}

fn staticCallback(in_context: ?*AK.IAkGlobalPluginContext, in_location: AK.AkGlobalCallbackLocation, in_cookie: ?*anyopaque) callconv(.C) void {
    _ = in_location;
    _ = in_context;

    var self: *Self = @ptrCast(@alignCast(in_cookie));

    self.mutex.lock();
    defer self.mutex.unlock();

    self.objectCallback() catch {};
}

fn postMIDIEvents(self: *Self, in_sample_offset: u32) !void {
    const by_note: u8 = if ((self.post_counter % 4) == 0) 70 else 60;

    const posts = [_]AK.AkMIDIPost{
        .{
            .base = .{
                .by_type = AK.AK_MIDI_EVENT_TYPE_NOTE_ON,
                .by_chan = 0,
                .message = .{
                    .note_on_off = .{
                        .by_note = by_note,
                        .by_velocity = 72,
                    },
                },
            },
            .offset = in_sample_offset,
        },
        .{
            .base = .{
                .by_type = AK.AK_MIDI_EVENT_TYPE_NOTE_OFF,
                .by_chan = 0,
                .message = .{
                    .note_on_off = .{
                        .by_note = by_note,
                        .by_velocity = 0,
                    },
                },
            },
            .offset = in_sample_offset + self.post_len_samples,
        },
    };

    _ = AK.SoundEngine.postMIDIOnEvent(ID.EVENTS.METRONOME_POSTMIDI, DemoGameObjectID, posts[0..], .{});

    try AK.SoundEngine.renderAudio(false);

    self.post_counter += 1;
}

fn stopMIDIPosts() !void {
    try AK.SoundEngine.stopMIDIOnEvent(.{
        .event_id = ID.EVENTS.METRONOME_POSTMIDI,
        .game_object_id = DemoGameObjectID,
    });
}
