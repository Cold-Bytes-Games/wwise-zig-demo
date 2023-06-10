const std = @import("std");
const DemoInterface = @import("../DemoInterface.zig");
const zgui = @import("zgui");
const root = @import("root");
const AK = @import("wwise-zig");

allocator: std.mem.Allocator = undefined,
is_playing: bool = false,
is_visible: bool = false,
current_area: u32 = 0,
last_area_hovered: u32 = 0,
playing_id: AK.AkPlayingID = AK.AK_INVALID_PLAYING_ID,

const Self = @This();

const DemoGameObjectID: AK.AkGameObjectID = 100;

pub fn init(self: *Self, allocator: std.mem.Allocator, demo_state: *root.DemoState) !void {
    _ = demo_state;
    self.* = .{
        .allocator = allocator,
    };

    try AK.SoundEngine.prepareBankString(allocator, .load, "PrepareDemo.bnk", .{ .flags = .structure_only });
    try AK.SoundEngine.registerGameObjWithName(allocator, DemoGameObjectID, "Human");

    try self.enterArea(1);
}

pub fn deinit(self: *Self, demo_state: *root.DemoState) void {
    _ = demo_state;

    AK.SoundEngine.prepareBankString(self.allocator, .unload, "PrepareDemo.bnk", .{ .flags = .structure_only }) catch {};

    AK.SoundEngine.unregisterGameObj(DemoGameObjectID) catch {};

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self, demo_state: *root.DemoState) !void {
    _ = demo_state;

    zgui.setNextWindowSize(.{
        .w = 220,
        .h = 80,
        .cond = .always,
    });

    if (zgui.begin("Prepare Event & Bank Demo", .{ .popen = &self.is_visible, .flags = .{ .always_auto_resize = true } })) {
        if (zgui.button("Enter Area 1", .{})) {
            try self.onAreaPressed();
        } else {
            if (zgui.isItemHovered(.{})) {
                if (self.last_area_hovered != 1) {
                    try self.enterArea(1);
                    self.last_area_hovered = 1;
                }
            }
        }

        if (zgui.button("Enter Area 2", .{})) {
            try self.onAreaPressed();
        } else {
            if (zgui.isItemHovered(.{})) {
                if (self.last_area_hovered != 2) {
                    try self.enterArea(2);
                    self.last_area_hovered = 2;
                }
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
    return DemoInterface{
        .instance = self,
        .initFn = @ptrCast(DemoInterface.InitFn, &init),
        .deinitFn = @ptrCast(DemoInterface.DeinitFn, &deinit),
        .onUIFn = @ptrCast(DemoInterface.OnUIFn, &onUI),
        .isVisibleFn = @ptrCast(DemoInterface.IsVisibleFn, &isVisible),
        .showFn = @ptrCast(DemoInterface.ShowFn, &show),
    };
}

fn eventForArea(area: u32) []const u8 {
    return if (area == 1) "Enter_Area_1" else "Enter_Area_2";
}

fn enterArea(self: *Self, area: u32) !void {
    self.leaveArea() catch {};

    try AK.SoundEngine.prepareEventString(self.allocator, .load, &.{eventForArea(area)});

    self.current_area = area;
}

fn leaveArea(self: *Self) !void {
    if (self.playing_id != AK.AK_INVALID_PLAYING_ID) {
        AK.SoundEngine.stopPlayingID(self.playing_id, .{});
        self.playing_id = AK.AK_INVALID_PLAYING_ID;
    }

    if (self.current_area > 0) {
        try AK.SoundEngine.prepareEventString(self.allocator, .unload, &.{eventForArea(self.current_area)});
    }
}

fn onAreaPressed(self: *Self) !void {
    if (self.playing_id == AK.AK_INVALID_PLAYING_ID) {
        self.playing_id = try AK.SoundEngine.postEventString(self.allocator, eventForArea(self.current_area), DemoGameObjectID, .{});
    }
}
