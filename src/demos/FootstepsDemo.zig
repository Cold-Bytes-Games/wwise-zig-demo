const std = @import("std");
const DemoInterface = @import("../DemoInterface.zig");
const zgui = @import("zgui");
const root = @import("root");
const AK = @import("wwise-zig");
const Cursor = @import("Cursor.zig");

allocator: std.mem.Allocator = undefined,
is_visible: bool = false,
cursor: Cursor = .{},
last_x: f32 = 0,
last_y: f32 = 0,
weight: f32 = 25.0,
surface: usize = std.math.maxInt(usize),
current_banks: u32 = 0,
tick_count: isize = 0,
last_tick_count: isize = 0,

const Self = @This();

const DemoGameObjectID: AK.AkGameObjectID = 5;
const HangarTransitionZone: f32 = 25.0;
const HangarSize: i32 = 70;
const CursorSpeed = 5.0;
const BufferZone: f32 = 20.0;
const DistanceToSpeed = 10 / CursorSpeed;
const WalkPeriod = 30;

var SurfaceGroup: u32 = undefined;

const SurfaceInfo = struct {
    bank_name: []const u8,
    switch_id: u32,

    pub fn init(allocator: std.mem.Allocator, bank_name: []const u8) !SurfaceInfo {
        const dot_position = std.mem.lastIndexOfScalar(u8, bank_name, '.');
        const bank_name_without_ext = if (dot_position) |pos| bank_name[0..pos] else bank_name;

        return SurfaceInfo{
            .bank_name = bank_name,
            .switch_id = try AK.SoundEngine.getIDFromString(allocator, bank_name_without_ext),
        };
    }
};

var Surfaces: [4]SurfaceInfo = undefined;

pub fn init(self: *Self, allocator: std.mem.Allocator, demo_state: *root.DemoState) !void {
    _ = demo_state;
    self.* = .{
        .allocator = allocator,
        .cursor = .{
            .max_speed = CursorSpeed,
            .color = [4]f32{ 1.0, 0.0, 0.0, 1.0 },
        },
    };

    try AK.SoundEngine.registerGameObjWithName(allocator, DemoGameObjectID, "Human");

    Surfaces = [_]SurfaceInfo{
        try SurfaceInfo.init(allocator, "Dirt.bnk"),
        try SurfaceInfo.init(allocator, "Wood.bnk"),
        try SurfaceInfo.init(allocator, "Metal.bnk"),
        try SurfaceInfo.init(allocator, "Gravel.bnk"),
    };

    SurfaceGroup = try AK.SoundEngine.getIDFromString(allocator, "Surface");
}

pub fn deinit(self: *Self, demo_state: *root.DemoState) void {
    _ = demo_state;
    AK.SoundEngine.unregisterGameObj(DemoGameObjectID) catch {};

    for (0..Surfaces.len) |index| {
        const bit = @as(u32, 1) << @as(u5, @intCast(index));

        if ((self.current_banks & bit) == bit) {
            AK.SoundEngine.unloadBankString(self.allocator, Surfaces[index].bank_name, null, .{}) catch {};
        }
    }

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self, demo_state: *root.DemoState) !void {
    _ = demo_state;
    self.tick_count += 1;

    zgui.setNextWindowSize(.{
        .w = 640,
        .h = 480,
        .cond = .first_use_ever,
    });

    if (zgui.begin("Footsteps Demo", .{ .popen = &self.is_visible, .flags = .{} })) {
        self.cursor.update();

        var draw_list = zgui.getWindowDrawList();

        if (zgui.sliderFloat("Weight", .{ .v = &self.weight, .min = 0.0, .max = 100.0 })) {
            try AK.SoundEngine.setRTPCValueString(self.allocator, "Footstep_Weight", self.weight, .{ .game_object_id = DemoGameObjectID });
        }

        const white_color = zgui.colorConvertFloat4ToU32([4]f32{ 1.0, 1.0, 1.0, 1.0 });

        const window_pos = zgui.getCursorScreenPos();
        const window_size = zgui.getContentRegionAvail();

        draw_list.addRect(.{
            .pmin = window_pos,
            .pmax = [2]f32{ window_pos[0] + window_size[0], window_pos[1] + window_size[1] },
            .col = white_color,
        });

        const half_width: f32 = window_size[0] / 2.0;
        const half_height: f32 = window_size[1] / 2.0;

        const text_width: f32 = 40.0;
        const text_height: f32 = 36.0;

        draw_list.addText([2]f32{ window_pos[0] + (half_width - BufferZone - text_width), window_pos[1] + (half_height - BufferZone - text_height) }, white_color, "Dirt", .{});

        draw_list.addText([2]f32{ window_pos[0] + (half_width + BufferZone), window_pos[1] + (half_height - BufferZone - text_height) }, white_color, "Wood", .{});

        draw_list.addText([2]f32{ window_pos[0] + (half_width - BufferZone - text_width), window_pos[1] + (half_height + BufferZone) }, white_color, "Metal", .{});

        draw_list.addText([2]f32{ window_pos[0] + (half_width + BufferZone), window_pos[1] + (half_height + BufferZone) }, white_color, "Gravel", .{});

        self.cursor.draw(draw_list);

        zgui.end();

        try self.manageSurfaces(window_size);
        try self.manageEnvironment(window_size);
        try self.playFootstep();
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

fn manageSurfaces(self: *Self, window_size: [2]f32) !void {
    var bank_masks: u32 = self.computeUsedBankMask(window_size);

    for (0..Surfaces.len) |index| {
        const bit = @as(u32, 1) << @as(u5, @intCast(index));

        if ((bank_masks & bit) == bit and (self.current_banks & bit) != bit) {
            _ = AK.SoundEngine.loadBankString(self.allocator, Surfaces[index].bank_name, .{}) catch {
                bank_masks &= ~bit;
            };
        }

        if ((bank_masks & bit) != bit and ((self.current_banks & bit) == bit)) {
            AK.SoundEngine.unloadBankString(self.allocator, Surfaces[index].bank_name, null, .{}) catch {
                bank_masks |= bit;
            };
        }
    }

    self.current_banks = bank_masks;

    const half_width = @as(usize, @intFromFloat(window_size[0] / 2.0));
    const half_height = @as(usize, @intFromFloat(window_size[1] / 2.0));
    const index_surface = @intFromBool(@as(usize, @intFromFloat(self.cursor.x)) > half_width) | (@as(usize, @intFromBool(@as(usize, @intFromFloat(self.cursor.y)) > half_height)) << @as(u6, 1));
    if (self.surface != index_surface) {
        try AK.SoundEngine.setSwitchID(SurfaceGroup, Surfaces[index_surface].switch_id, DemoGameObjectID);
        self.surface = index_surface;
    }
}

fn manageEnvironment(self: *Self, window_size: [2]f32) !void {
    const ListenerID = @import("root").ListenerGameObjectID;

    var hangar_env = AK.AkAuxSendValue{
        .aux_bus_id = try AK.SoundEngine.getIDFromString(self.allocator, "Hangar_Env"),
    };

    const half_width = @as(i32, @intFromFloat(window_size[0] / 2.0));
    const half_height = @as(i32, @intFromFloat(window_size[1] / 2.0));
    const diff_x: i32 = try std.math.absInt(@as(i32, @intFromFloat(self.cursor.x)) - half_width);
    const diff_y: i32 = try std.math.absInt(@as(i32, @intFromFloat(self.cursor.y)) - half_height);

    const percent_outside_x = @max(@as(f32, @floatFromInt(diff_x - HangarSize)) / HangarTransitionZone, 0.0);
    const percent_outside_y = @max(@as(f32, @floatFromInt(diff_y - HangarSize)) / HangarTransitionZone, 0.0);

    hangar_env.control_value = @max(0.0, 1.0 - @max(percent_outside_x, percent_outside_y));
    hangar_env.listener_id = ListenerID;

    try AK.SoundEngine.setGameObjectOutputBusVolume(DemoGameObjectID, ListenerID, 1.0 - hangar_env.control_value / 2.0);
    try AK.SoundEngine.setGameObjectAuxSendValues(DemoGameObjectID, &.{hangar_env});
}

fn computeUsedBankMask(self: Self, window_size: [2]f32) u32 {
    const half_width = @as(i32, @intFromFloat(window_size[0] / 2));
    const half_height = @as(i32, @intFromFloat(window_size[1] / 2));
    const buffer_zone = @as(i32, @intFromFloat(BufferZone * 2));

    const left_div = @as(i32, @intFromBool(@as(i32, @intFromFloat(self.cursor.x)) > (half_width - buffer_zone)));
    const right_div = @as(i32, @intFromBool(@as(i32, @intFromFloat(self.cursor.x)) < (half_width + buffer_zone)));
    const top_div = @as(i32, @intFromBool(@as(i32, @intFromFloat(self.cursor.y)) > (half_height - buffer_zone)));
    const bottom_div = @as(i32, @intFromBool(@as(i32, @intFromFloat(self.cursor.y)) < (half_height + buffer_zone)));

    return @as(u32, @bitCast(((right_div & bottom_div) << 0) | ((left_div & bottom_div) << 1) | ((right_div & top_div) << 2) | ((left_div & top_div) << 3))) & 0x0F;
}

fn playFootstep(self: *Self) !void {
    const dx = self.cursor.x - self.last_x;
    const dy = self.cursor.y - self.last_y;
    const distance = std.math.sqrt(dx * dx + dy * dy);

    const speed = distance * DistanceToSpeed;

    try AK.SoundEngine.setRTPCValueString(self.allocator, "Footstep_Speed", speed, .{ .game_object_id = DemoGameObjectID });

    const period = @as(isize, @intFromFloat(WalkPeriod - speed));

    if (distance < 0.1 and self.last_tick_count != -1) {
        try AK.SoundEngine.setRTPCValueString(self.allocator, "Footstep_Weight", self.weight / 2.0, .{ .game_object_id = DemoGameObjectID });
        _ = try AK.SoundEngine.postEventString(self.allocator, "Play_Footsteps", DemoGameObjectID, .{});

        self.last_tick_count = -1;
    } else if (distance > 0.1 and (self.tick_count - self.last_tick_count) > period) {
        try AK.SoundEngine.setRTPCValueString(self.allocator, "Footstep_Weight", self.weight, .{ .game_object_id = DemoGameObjectID });
        _ = try AK.SoundEngine.postEventString(self.allocator, "Play_Footsteps", DemoGameObjectID, .{});

        self.last_tick_count = self.tick_count;
    }

    self.last_x = self.cursor.x;
    self.last_y = self.cursor.y;
}
