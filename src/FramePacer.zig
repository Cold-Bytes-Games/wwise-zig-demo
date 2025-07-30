const std = @import("std");

target_frame_rate: f32 = 1.0 / 60.0,
accumulator: f32 = 0.0,
total_frames: u64 = 0,

last_instant: std.time.Instant = undefined,
current_instant: std.time.Instant = undefined,

is_paused: bool = false,

const FramePacer = @This();

pub fn init(target_frame_rate: u32) !FramePacer {
    return .{
        .target_frame_rate = 1.0 / @as(f32, @floatFromInt(target_frame_rate)),
        .last_instant = try std.time.Instant.now(),
        .current_instant = try std.time.Instant.now(),
    };
}

pub fn updateTarget(self: *FramePacer, new_target_frame_rate: u32) !void {
    self.target_frame_rate = 1.0 / @as(f32, @floatFromInt(new_target_frame_rate));
    self.last_instant = try std.time.Instant.now();
    self.current_instant = try std.time.Instant.now();
    self.accumulator = 0.0;
}

pub fn fixedDeltaTime(self: FramePacer) f32 {
    return self.target_frame_rate;
}

pub fn variableDeltaTime(self: FramePacer) f32 {
    const delta_nanoseconds = self.current_instant.since(self.last_instant);
    return @as(f32, @floatFromInt(delta_nanoseconds)) / @as(f32, std.time.ns_per_s);
}

pub fn tick(self: *FramePacer) !void {
    self.last_instant = self.current_instant;
    self.current_instant = try std.time.Instant.now();

    if (!self.is_paused) {
        const new_delta_time: f32 = self.variableDeltaTime();
        self.accumulator = @min(self.accumulator + new_delta_time, self.target_frame_rate * 2.0);
    }
}

pub fn pause(self: *FramePacer) void {
    self.is_paused = true;
    self.accumulator = 0.0;
}

pub fn unpause(self: *FramePacer) void {
    self.is_paused = false;
    self.accumulator = self.target_frame_rate;
}

pub fn step(self: *FramePacer) void {
    self.accumulator = self.target_frame_rate;
}

pub fn shouldUpdate(self: FramePacer) bool {
    return self.accumulator >= self.target_frame_rate;
}

pub fn consume(self: *FramePacer) void {
    self.accumulator -= self.target_frame_rate;
    self.total_frames += 1;
}
