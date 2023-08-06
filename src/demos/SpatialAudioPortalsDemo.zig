const std = @import("std");
const AK = @import("wwise-zig");
const Box = @import("Box.zig");
const Cursor = @import("Cursor.zig");
const DemoInterface = @import("../DemoInterface.zig");
const ID = @import("wwise-ids");
const Line = @import("Line.zig");
const root = @import("root");
const zgui = @import("zgui");

allocator: std.mem.Allocator = undefined,
is_visible: bool = false,
bank_id: AK.AkBankID = AK.AK_INVALID_BANK_ID,
emitter_cursor: Cursor = .{},
listener_cursor: Cursor = .{},
room: Box = .{},
portal0: Box = .{},
portal1: Box = .{},
lines: std.ArrayListUnmanaged(Line) = .{},
game_object_x: f32 = 0.0,
game_object_z: f32 = 0.0,
dry_diffraction: f32 = 0.0,
wet_diffraction: f32 = 0.0,
emitter_elevation_deg: f32 = 0.0,
emitter_elevation: f32 = 0.0,
emitter_azimut_deg: f32 = 0.0,
emitter_azimut: f32 = 0.0,
room_corner_x: f32 = 0.0,
room_corner_y: f32 = 0.0,
portal0_open: bool = true,
portal1_open: bool = true,
width: f32 = 0.0,
height: f32 = 0.0,
is_first_update: bool = true,

const Self = @This();

const EmitterObj: AK.AkGameObjectID = 100;
const ListenerObj: AK.AkGameObjectID = 103;
const DistanceProbe: AK.AkGameObjectID = 104;
const Room: AK.SpatialAudio.AkRoomID = .{ .id = 200 };
const Portal0: AK.SpatialAudio.AkPortalID = .{ .id = 300 };
const Portal1: AK.SpatialAudio.AkPortalID = .{ .id = 301 };
const GeometryRoom: AK.SpatialAudio.AkGeometrySetID = .{ .id = 0 };
const PositionRange: f32 = 200.0;
const RepeatTime = 20;

pub fn init(self: *Self, allocator: std.mem.Allocator, demo_state: *root.DemoState) !void {
    _ = demo_state;
    self.* = .{
        .allocator = allocator,
        .emitter_cursor = .{
            .label = "<E>",
        },
        .listener_cursor = .{
            .label = "<L>",
        },
    };

    try AK.SoundEngine.registerGameObjWithName(allocator, EmitterObj, "Emitter");
    try AK.SoundEngine.registerGameObjWithName(allocator, ListenerObj, "Listener");

    try AK.SoundEngine.setListeners(EmitterObj, &.{ListenerObj});

    self.bank_id = try AK.SoundEngine.loadBankString(allocator, "Bus3d_Demo.bnk", .{});

    _ = try AK.SoundEngine.postEventID(ID.EVENTS.PLAY_CLUSTER, EmitterObj, .{});
}

pub fn deinit(self: *Self, demo_state: *root.DemoState) void {
    _ = demo_state;

    self.lines.deinit(self.allocator);

    AK.SoundEngine.unregisterGameObj(ListenerObj) catch {};
    AK.SoundEngine.unregisterGameObj(EmitterObj) catch {};

    AK.SoundEngine.unloadBankID(self.bank_id, null, .{}) catch {};

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self, demo_state: *root.DemoState) !void {
    _ = demo_state;

    zgui.setNextWindowSize(.{
        .w = 640,
        .h = 480,
        .cond = .first_use_ever,
    });

    if (zgui.begin("Spatial Audio - Portals", .{ .popen = &self.is_visible, .flags = .{} })) {
        const window_size = zgui.getContentRegionAvail();

        if (self.is_first_update) {
            self.width = window_size[0] - Cursor.Margin;
            self.height = window_size[1] - Cursor.Margin;
            self.is_first_update = false;

            self.listener_cursor.update();
            self.emitter_cursor.update();

            self.emitter_cursor.x -= 30.0;
            self.listener_cursor.x += 30.0;

            try self.initSpatialAudio();
        }

        if (zgui.isKeyDown(.mod_shift)) {
            self.listener_cursor.update();
            try self.updateGameObjectPos(self.listener_cursor, ListenerObj);
        } else {
            self.emitter_cursor.update();
            try self.updateGameObjectPos(self.emitter_cursor, EmitterObj);
        }

        if (zgui.checkbox("Portal 0", .{ .v = &self.portal0_open })) {
            try self.setPortals();
        }

        if (zgui.checkbox("Portal 1", .{ .v = &self.portal1_open })) {
            try self.setPortals();
        }

        if (zgui.sliderFloat("Emitter Elevation", .{ .v = &self.emitter_elevation_deg, .min = 0.0, .max = 360.0 })) {
            self.emitter_elevation = std.math.degreesToRadians(f32, self.emitter_elevation_deg);
        }

        if (zgui.sliderFloat("Emitter Azimut", .{ .v = &self.emitter_azimut_deg, .min = 0.0, .max = 360.0 })) {
            self.emitter_azimut = std.math.degreesToRadians(f32, self.emitter_azimut_deg);
        }

        zgui.text("X: {d:.2}", .{self.game_object_x});
        zgui.text("Z: {d:.2}", .{self.game_object_z});
        zgui.text("Diffraction dry: {d:.2}", .{0.0});
        zgui.text("Diffraction wet: {d:.2}", .{0.0});
        zgui.text("Transmission loss: {d:.2}", .{0.0});

        var draw_list = zgui.getWindowDrawList();

        const white_color = zgui.colorConvertFloat4ToU32([4]f32{ 1.0, 1.0, 1.0, 1.0 });

        const window_pos = zgui.getCursorScreenPos();

        draw_list.addRect(.{
            .pmin = window_pos,
            .pmax = [2]f32{ window_pos[0] + window_size[0] - Cursor.Margin, window_pos[1] + window_size[1] - Cursor.Margin },
            .col = white_color,
        });

        self.emitter_cursor.draw(draw_list);
        self.listener_cursor.draw(draw_list);

        self.room.draw(draw_list);
        self.portal0.draw(draw_list);
        self.portal1.draw(draw_list);

        for (self.lines.items) |line| {
            line.draw(draw_list);
        }

        zgui.end();
    }

    if (!self.is_visible) {
        AK.SoundEngine.stopAll(.{});
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

fn pixelsToAkPosX(self: Self, in_x: f32) f32 {
    return ((in_x / self.width) - 0.5) * PositionRange;
}

fn pixelsToAkPosY(self: Self, in_y: f32) f32 {
    return -((in_y / self.height) - 0.5) * PositionRange;
}

fn pixelsToAkLenX(self: Self, in_x: f32) f32 {
    return (in_x / self.width) * PositionRange;
}

fn pixelsToAkLenY(self: Self, in_y: f32) f32 {
    return (in_y / self.height) * PositionRange;
}

fn akPosToPixelsX(self: Self, in_x: f32) f32 {
    return ((in_x / PositionRange) + 0.5) * self.width;
}

fn akPoosToPixelsY(self: Self, in_y: f32) f32 {
    return ((in_y / PositionRange) + 0.5) * self.height;
}

fn updateGameObjectPos(self: *Self, in_cursor: Cursor, in_game_object_id: AK.AkGameObjectID) !void {
    const x = in_cursor.x;
    const y = in_cursor.y;

    self.game_object_x = self.pixelsToAkPosX(x);
    self.game_object_z = self.pixelsToAkPosY(y);

    var sound_position = AK.AkSoundPosition{
        .position = .{
            .x = self.game_object_x,
            .z = self.game_object_z,
        },
        .orientation_front = .{
            .z = 1.0,
        },
        .orientation_top = .{
            .y = 1.0,
        },
    };

    try AK.SoundEngine.setPosition(in_game_object_id, sound_position, .{});
}

fn initSpatialAudio(self: *Self) !void {
    self.room = .{
        .x = 0,
        .y = 0,
        .width = self.width / 2.0,
        .height = self.height / 2.0,
        .color = [4]f32{ 1.0, 1.0, 0.0, 1.0 },
    };

    var room_params = AK.SpatialAudio.AkRoomParams{
        .front = .{
            .z = 1.0,
        },
        .up = .{
            .y = 1.0,
        },
        .transmission_loss = 0.9,
        .room_game_obj_keep_registered = true,
        .room_game_obj_aux_send_level_to_self = 0.25,
        .reverb_aux_bus = ID.AUX_BUSSES.ROOM,
        .geometry_instance_id = GeometryRoom,
    };

    try AK.SpatialAudio.setRoom(Room, &room_params, .{
        .allocator = self.allocator,
        .room_name = "Room Object",
    });

    room_params.transmission_loss = 0.0;
    room_params.room_game_obj_keep_registered = false;
    room_params.reverb_aux_bus = ID.AUX_BUSSES.OUTSIDE;
    room_params.geometry_instance_id = .{};

    try AK.SpatialAudio.setRoom(AK.SpatialAudio.getOutdoorRoomID(), &room_params, .{
        .allocator = self.allocator,
        .room_name = "Outside Object",
    });

    try self.setPortals();

    _ = try AK.SoundEngine.postEventID(ID.EVENTS.PLAY_AMBIENCE_QUAD, Room.asGameObjectID(), .{});
}

fn setPortals(self: *Self) !void {
    const PortalMargin: f32 = 15.0;
    const Portal0Width: f32 = 90.0;
    const Portal0Height: f32 = 60.0;

    self.portal0 = .{
        .x = self.room.width - Portal0Width / 2.0,
        .y = PortalMargin,
        .width = Portal0Width,
        .height = Portal0Height,
        .color = [4]f32{ 1.0, 1.0, 0.0, 1.0 },
    };

    const Portal1Height: f32 = 90.0;

    self.portal1 = .{
        .x = PortalMargin,
        .y = self.room.height - Portal1Height / 2.0,
        .width = self.room.width - 2.0 * PortalMargin,
        .height = Portal1Height,
        .color = [4]f32{ 1.0, 1.0, 0.0, 1.0 },
    };

    const portal0_params = AK.SpatialAudio.AkPortalParams{
        .transform = .{
            .position = .{
                .x = self.pixelsToAkPosX(self.portal0.x + Portal0Width / 2.0),
                .z = self.pixelsToAkPosY(self.portal0.y + Portal0Height / 2.0),
            },
            .orientation_front = .{
                .x = 1.0,
            },
            .orientation_top = .{
                .y = 1.0,
            },
        },
        .extent = .{
            .half_width = self.pixelsToAkLenY(Portal0Height / 2.0),
            .half_height = self.pixelsToAkLenY(Portal0Height / 2.0),
            .half_depth = self.pixelsToAkLenX(Portal0Width / 2.0),
        },
        .enabled = self.portal0_open,
        .front_room = AK.SpatialAudio.getOutdoorRoomID(),
        .back_room = Room,
    };

    try AK.SpatialAudio.setPortal(Portal0, &portal0_params, .{
        .allocator = self.allocator,
        .portal_name = "Portal ROOM->Outside, horizontal",
    });

    const portal1_params = AK.SpatialAudio.AkPortalParams{
        .transform = .{
            .position = .{
                .x = self.pixelsToAkPosX(self.portal1.x + self.portal1.width / 2.0),
                .z = self.pixelsToAkPosY(self.portal1.y + Portal1Height / 2.0),
            },
            .orientation_front = .{
                .z = 1.0,
            },
            .orientation_top = .{
                .y = 1.0,
            },
        },
        .extent = .{
            .half_width = self.pixelsToAkLenX(self.portal1.width / 2.0),
            .half_height = 30.0,
            .half_depth = self.pixelsToAkLenY(Portal1Height / 2.0),
        },
        .enabled = self.portal1_open,
        .front_room = Room,
        .back_room = AK.SpatialAudio.getOutdoorRoomID(),
    };

    try AK.SpatialAudio.setPortal(Portal1, &portal1_params, .{
        .allocator = self.allocator,
        .portal_name = "Portal ROOM->Outside, horizontal",
    });
}
