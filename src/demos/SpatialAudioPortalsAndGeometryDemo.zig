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
transmission_loss: f32 = 0.0,
emitter_elevation_deg: f32 = 0.0,
emitter_elevation: f32 = 0.0,
emitter_azimut_deg: f32 = 0.0,
emitter_azimut: f32 = 0.0,
room_corner_x: f32 = 0.0,
room_corner_y: f32 = 0.0,
portal0_open: bool = true,
portal1_open: bool = true,
listener_player_offset: f32 = 0.0,
width: f32 = 0.0,
height: f32 = 0.0,
is_first_update: bool = true,
distance_probe_registered: bool = false,
last_tick: u32 = 0,
current_tick: u32 = 0,
geometry_in_rooms: GeometryInRooms = .{},

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

    try AK.SoundEngine.registerGameObjWithName(allocator, EmitterObj, "Emitter E");
    try AK.SoundEngine.registerGameObjWithName(allocator, ListenerObj, "Listener L");

    try AK.SoundEngine.setListeners(EmitterObj, &.{ListenerObj});
    try AK.SoundEngine.setListeners(ListenerObj, &.{ListenerObj});

    try AK.SpatialAudio.registerListener(ListenerObj);

    self.bank_id = try AK.SoundEngine.loadBankString(allocator, "Bus3d_Demo.bnk", .{});

    _ = try AK.SoundEngine.postEventID(ID.EVENTS.PLAY_CLUSTER, EmitterObj, .{});
}

pub fn deinit(self: *Self, demo_state: *root.DemoState) void {
    _ = demo_state;

    self.lines.deinit(self.allocator);

    AK.SpatialAudio.removePortal(Portal0) catch {};
    AK.SpatialAudio.removePortal(Portal1) catch {};
    AK.SpatialAudio.removeRoom(Room) catch {};
    AK.SpatialAudio.removeRoom(AK.SpatialAudio.getOutdoorRoomID()) catch {};

    AK.SoundEngine.unregisterGameObj(ListenerObj) catch {};
    AK.SoundEngine.unregisterGameObj(EmitterObj) catch {};
    if (self.distance_probe_registered) {
        AK.SoundEngine.unregisterGameObj(DistanceProbe) catch {};
        self.distance_probe_registered = false;
    }

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

    if (zgui.begin("Spatial Audio - Portals and Geometry", .{ .popen = &self.is_visible, .flags = .{} })) {
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

            try self.geometry_in_rooms.init(self);
        }

        if (zgui.isKeyDown(.mod_shift)) {
            self.emitter_cursor.update();
        } else {
            const last_x = self.listener_cursor.x;
            const last_y = self.listener_cursor.y;
            self.listener_cursor.update();

            if ((self.last_tick + RepeatTime) <= self.current_tick and (last_x != self.listener_cursor.x or last_y != self.listener_cursor.y)) {
                _ = try AK.SoundEngine.postEventID(ID.EVENTS.PLAY_FOOTSTEP, ListenerObj, .{});
                self.last_tick = self.current_tick;
            }
        }

        try self.updateMoved();

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

        _ = zgui.sliderFloat("Listener Player Offset", .{ .v = &self.listener_player_offset, .min = 0.0, .max = 20.0 });

        zgui.text("X: {d:.2}", .{self.game_object_x});
        zgui.text("Z: {d:.2}", .{self.game_object_z});
        zgui.text("Diffraction dry: {d:.2}", .{self.dry_diffraction});
        zgui.text("Diffraction wet: {d:.2}", .{self.wet_diffraction});
        zgui.text("Transmission loss: {d:.2}", .{self.transmission_loss});

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

        self.geometry_in_rooms.draw(draw_list);

        zgui.end();
    }

    if (!self.is_visible) {
        AK.SoundEngine.stopAll(.{});
    }

    self.current_tick += 1;
}

pub fn updateMoved(self: *Self) !void {
    self.room_corner_x = self.room.x + self.room.width;
    self.room_corner_y = self.room.y + self.room.height;

    try self.updateGameObjectPos(self.emitter_cursor, EmitterObj);
    try self.updateGameObjectPos(self.listener_cursor, ListenerObj);

    self.lines.clearRetainingCapacity();

    var emitter_position: AK.AkVector64 = .{};
    var listener_position: AK.AkVector64 = .{};
    var paths: [8]AK.SpatialAudio.AkDiffractionPathInfo = undefined;
    var num_paths: u32 = 8;

    AK.SpatialAudio.queryDiffractionPaths(EmitterObj, 0, &listener_position, &emitter_position, &paths, &num_paths) catch {};

    var num_lines: usize = 0;

    for (0..num_paths) |path| {
        num_lines += (paths[path].node_count + 1);
    }

    self.dry_diffraction = 0.0;
    self.wet_diffraction = 0.0;
    self.transmission_loss = 0.0;

    if (num_lines > 0) {
        var dry_diffraction: f32 = 1.0;
        var wet_diffraction: f32 = 1.0;
        var tramission_loss: f32 = 0.0;
        var wet_diffraction_set: bool = false;

        for (0..num_paths) |path| {
            if (paths[path].node_count > 0) {
                try self.lines.append(self.allocator, .{
                    .start_x = self.akPosToPixelsX(@floatCast(listener_position.x)),
                    .start_y = self.akPosToPixelsY(@floatCast(listener_position.z)),
                    .end_x = self.akPosToPixelsX(@floatCast(paths[path].nodes[0].x)),
                    .end_y = self.akPosToPixelsY(@floatCast(paths[path].nodes[0].z)),
                });

                var portal_id = paths[path].portals[0];

                var node: u32 = 1;

                while (node < paths[path].node_count) : (node += 1) {
                    try self.lines.append(self.allocator, .{
                        .start_x = self.akPosToPixelsX(@floatCast(paths[path].nodes[node - 1].x)),
                        .start_y = self.akPosToPixelsY(@floatCast(paths[path].nodes[node - 1].z)),
                        .end_x = self.akPosToPixelsX(@floatCast(paths[path].nodes[node].x)),
                        .end_y = self.akPosToPixelsY(@floatCast(paths[path].nodes[node].z)),
                    });
                    if (!portal_id.isValid()) {
                        portal_id = paths[path].portals[node];
                    }
                }
                // Last node to emitter
                try self.lines.append(self.allocator, .{
                    .start_x = self.akPosToPixelsX(@floatCast(paths[path].nodes[node - 1].x)),
                    .start_y = self.akPosToPixelsY(@floatCast(paths[path].nodes[node - 1].z)),
                    .end_x = self.akPosToPixelsX(@floatCast(emitter_position.x)),
                    .end_y = self.akPosToPixelsY(@floatCast(emitter_position.z)),
                });

                var valid_wet: bool = true;
                var portal_wet_diffraction: f32 = AK.SpatialAudio.queryWetDiffraction(portal_id) catch blk: {
                    valid_wet = false;
                    break :blk 0.0;
                };

                if (portal_id.isValid() and valid_wet and portal_wet_diffraction < wet_diffraction) {
                    wet_diffraction = portal_wet_diffraction;
                    wet_diffraction_set = true;
                }
            } else {
                try self.lines.append(self.allocator, .{
                    .start_x = self.akPosToPixelsX(@floatCast(listener_position.x)),
                    .start_y = self.akPosToPixelsY(@floatCast(listener_position.z)),
                    .end_x = self.akPosToPixelsX(@floatCast(emitter_position.x)),
                    .end_y = self.akPosToPixelsY(@floatCast(emitter_position.z)),
                });
            }

            if (paths[path].transmission_loss == 0.0) {
                dry_diffraction = @min(dry_diffraction, paths[path].diffraction);
            } else {
                tramission_loss = paths[path].transmission_loss;
            }
        }

        self.dry_diffraction = dry_diffraction * 100.0;
        self.wet_diffraction = if (wet_diffraction_set) wet_diffraction * 100.0 else 0.0;
        self.transmission_loss = tramission_loss * 100.0;
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

fn pixelsToAkPosX(self: *const Self, in_x: f32) f32 {
    return ((in_x / self.width) - 0.5) * PositionRange;
}

fn pixelsToAkPosY(self: *const Self, in_y: f32) f32 {
    return -((in_y / self.height) - 0.5) * PositionRange;
}

fn pixelsToAkLenX(self: *const Self, in_x: f32) f32 {
    return (in_x / self.width) * PositionRange;
}

fn pixelsToAkLenY(self: *const Self, in_y: f32) f32 {
    return (in_y / self.height) * PositionRange;
}

fn akPosToPixelsX(self: *const Self, in_x: f32) f32 {
    return ((in_x / PositionRange) + 0.5) * self.width;
}

fn akPosToPixelsY(self: *const Self, in_y: f32) f32 {
    return ((-in_y / PositionRange) + 0.5) * self.height;
}

pub fn isInRoom(self: *const Self, in_x: f32, in_y: f32) AK.SpatialAudio.AkRoomID {
    if (in_x <= self.room_corner_x and in_y <= self.room_corner_y) {
        return Room;
    }

    return AK.SpatialAudio.getOutdoorRoomID();
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

    if (in_game_object_id == ListenerObj) {
        sound_position.orientation_front.x = std.math.sin(self.emitter_azimut) * std.math.cos(self.emitter_elevation);
        sound_position.orientation_front.y = std.math.sin(self.emitter_elevation);
        sound_position.orientation_front.z = std.math.cos(self.emitter_azimut) * std.math.cos(self.emitter_elevation);

        sound_position.orientation_top.x = std.math.sin(self.emitter_elevation) * -std.math.sin(self.emitter_azimut);
        sound_position.orientation_top.y = std.math.cos(self.emitter_elevation);
        sound_position.orientation_top.z = -std.math.sin(self.emitter_elevation) * std.math.cos(self.emitter_azimut);

        if (self.listener_player_offset > 0.0) {
            if (!self.distance_probe_registered) {
                try AK.SoundEngine.registerGameObjWithName(self.allocator, DistanceProbe, "Distance Probe");
                try AK.SoundEngine.setDistanceProbe(ListenerObj, DistanceProbe);
                self.distance_probe_registered = true;
            }

            try AK.SoundEngine.setPosition(DistanceProbe, sound_position, .{});

            const distance_probe_room_id = self.isInRoom(self.akPosToPixelsX(@floatCast(sound_position.position.x)), self.akPosToPixelsY(@floatCast(sound_position.position.z)));
            try AK.SpatialAudio.setGameObjectInRoom(DistanceProbe, distance_probe_room_id);

            sound_position.position.x -= sound_position.orientation_front.x * self.listener_player_offset;
            sound_position.position.y -= sound_position.orientation_front.y * self.listener_player_offset;
            sound_position.position.z -= sound_position.orientation_front.z * self.listener_player_offset;
        } else {
            if (self.distance_probe_registered) {
                try AK.SoundEngine.unregisterGameObj(DistanceProbe);
                try AK.SoundEngine.setDistanceProbe(ListenerObj, AK.AK_INVALID_GAME_OBJECT);
                self.distance_probe_registered = false;
            }
        }
    }

    try AK.SoundEngine.setPosition(in_game_object_id, sound_position, .{});

    const room_id = self.isInRoom(self.akPosToPixelsX(@floatCast(sound_position.position.x)), self.akPosToPixelsY(@floatCast(sound_position.position.z)));

    try AK.SpatialAudio.setGameObjectInRoom(in_game_object_id, room_id);

    if (in_game_object_id == EmitterObj) {
        try AK.SpatialAudio.setGameObjectRadius(in_game_object_id, self.pixelsToAkLenX(self.room.width / 8.0), self.pixelsToAkLenY(self.room.width / 12.0));
    }
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

    _ = try AK.SoundEngine.postEventID(ID.EVENTS.PLAY_ROOM_EMITTER, EmitterObj, .{});
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
        .portal_name = "Outside->ROOM, vertical",
    });
}

const GeometryInRooms = struct {
    inited: bool = false,
    geometry: [10]Line = undefined,

    pub fn init(self: *GeometryInRooms, demo: *const Self) !void {
        const room0_width_px = demo.room.width;
        const room0_height_px: f32 = if (demo.room.height >= 0) demo.room.height else 0.0;

        var line: usize = 0.0;
        const center_x = demo.akPosToPixelsX(0.0);
        const center_y = demo.akPosToPixelsY(0.0);
        const horizontal_wall_left = -demo.pixelsToAkLenX(room0_width_px);
        const room0_height = demo.pixelsToAkLenY(room0_height_px);

        {
            // Outer wall (assigned to Outside)
            //
            //		  |
            //        |
            // -------|

            // Draw lines
            self.geometry[line] = .{
                .start_x = center_x,
                .start_y = center_y,
                .end_x = center_x,
                .end_y = center_y - room0_height_px,
            };
            line += 1;
            self.geometry[line] = .{
                .start_x = center_x,
                .start_y = center_y,
                .end_x = center_x - room0_width_px,
                .end_y = center_y,
            };
            line += 1;

            // Register to SpatialAudio
            const NumVertices = 6;

            var geom = AK.SpatialAudio.AkGeometryParams{
                .num_vertices = NumVertices,
            };

            const vertices = [NumVertices]AK.SpatialAudio.AkVertex{
                .{ .x = 0.0, .y = -30.0, .z = 0.0 },
                .{ .x = 0.0, .y = 30.0, .z = 0.0 },
                .{ .x = 0.0, .y = 30.0, .z = room0_height },
                .{ .x = 0.0, .y = -30.0, .z = room0_height },
                .{ .x = horizontal_wall_left, .y = -30.0, .z = 0.0 },
                .{ .x = horizontal_wall_left, .y = 30.0, .z = 0.0 },
            };
            geom.vertices = &vertices;

            geom.num_surfaces = 1;
            const outer_surface = AK.SpatialAudio.AkAcousticSurface{
                .str_name = "Outside",
                .texture_id = try AK.SoundEngine.getIDFromString(demo.allocator, "Brick"),
                .transmission_loss = 0.8,
            };
            geom.surfaces = @ptrCast(&outer_surface);

            const NumTriOutside = 4;
            geom.num_triangles = NumTriOutside;

            const triangles = [NumTriOutside]AK.SpatialAudio.AkTriangle{
                .{ .point0 = 0, .point1 = 1, .point2 = 2, .surface = 0 },
                .{ .point0 = 0, .point1 = 2, .point2 = 3, .surface = 0 },
                .{ .point0 = 0, .point1 = 1, .point2 = 4, .surface = 0 },
                .{ .point0 = 1, .point1 = 4, .point2 = 5, .surface = 0 },
            };
            geom.triangles = &triangles;

            geom.enable_diffraction = true;
            // We did not add triangles on the top and bottom (through screen) of our "wall", and set EnableDiffractionOnBoundaryEdges to false,
            // so that sound does not diffract via the top and bottom edges.
            geom.enable_diffraction_on_boundary_edges = false;

            geom.enable_triangles = true;

            try AK.SpatialAudio.setGeometry(GeometryRoom, &geom);

            const instance_params = AK.SpatialAudio.AkGeometryInstanceParams{
                .geometry_set_id = GeometryRoom,
                .room_id = AK.SpatialAudio.getOutdoorRoomID(),
            };

            try AK.SpatialAudio.setGeometryInstance(GeometryRoom, &instance_params);
        }

        {
            // Inner wall (assigned to ROOM)
            // Note: the geometry assigned to ROOM is offset from the outside wall constructed above, by k_offsetInnerWall pixels, to represent the wall of a room and the thickness of the "building" as it would
            // typically occur in a video game, or real life. However this is not necessary; the walls may be coincident (k_offsetInnerWall = 0) or even reversed (k_offsetInnerWall < 0). An emitter in room ROOM
            // will always only see these walls
            //

            // 45|------|32
            //	 |		|
            // 76|------|01

            // Draw Lines.
            const OffsetInnerWall = 5;
            const top_left_x_px: f32 = 0.0;
            const top_left_y_px: f32 = 0.0;
            const bottom_right_x_px = room0_width_px - OffsetInnerWall;
            const bottom_right_y_px = room0_height_px - OffsetInnerWall;

            self.geometry[line] = .{
                .start_x = top_left_x_px,
                .start_y = top_left_y_px,
                .end_x = bottom_right_x_px,
                .end_y = top_left_y_px,
            };
            line += 1;
            self.geometry[line] = .{
                .start_x = bottom_right_x_px,
                .start_y = top_left_y_px,
                .end_x = bottom_right_x_px,
                .end_y = bottom_right_y_px,
            };
            line += 1;
            self.geometry[line] = .{
                .start_x = bottom_right_x_px,
                .start_y = bottom_right_y_px,
                .end_x = top_left_x_px,
                .end_y = bottom_right_y_px,
            };
            line += 1;
            self.geometry[line] = .{
                .start_x = top_left_x_px,
                .start_y = bottom_right_y_px,
                .end_x = top_left_x_px,
                .end_y = top_left_y_px,
            };

            // Register to SpatialAudio
            const top_left_x = demo.pixelsToAkPosX(top_left_x_px);
            const top_left_y = demo.pixelsToAkPosY(top_left_y_px);
            const bottom_right_x = demo.pixelsToAkPosX(bottom_right_x_px);
            const bottom_right_y = demo.pixelsToAkPosY(bottom_right_y_px);

            const NumVertices = 8;
            var geom = AK.SpatialAudio.AkGeometryParams{};
            geom.num_vertices = NumVertices;

            // In the coordinate system we have chosen, x is right-left, z is top-bottom and y is through screen. (0,0,0) is the center of the window.
            const vertices = [NumVertices]AK.SpatialAudio.AkVertex{
                .{ .x = bottom_right_x, .y = -30.0, .z = bottom_right_y },
                .{ .x = bottom_right_x, .y = 30.0, .z = bottom_right_y },
                .{ .x = bottom_right_x, .y = 30.0, .z = top_left_y },
                .{ .x = bottom_right_x, .y = -30.0, .z = top_left_y },
                .{ .x = top_left_x, .y = -30.0, .z = top_left_y },
                .{ .x = top_left_x, .y = 30.0, .z = top_left_y },
                .{ .x = top_left_x, .y = 30.0, .z = bottom_right_y },
                .{ .x = top_left_x, .y = -30.0, .z = bottom_right_y },
            };
            geom.vertices = &vertices;

            geom.num_surfaces = 1;

            // Assign surfaces. Direct path diffraction is not affected by the acoustic properties of surfaces, because in this model, the edges don't absorb any energy.
            // In this demo, the only purpose of using acoustic surfaces with textures defined in Wwise is for showing colors in the 3D Game Object Viewer.
            const inner_surface = AK.SpatialAudio.AkAcousticSurface{
                .str_name = "Inside",
                .texture_id = try AK.SoundEngine.getIDFromString(demo.allocator, "Drywall"),
                .transmission_loss = 0.8, // Let's set a transmission loss smaller than that of the room, so that the transmission loss of the room dominates.
            };
            geom.surfaces = @ptrCast(&inner_surface);

            const NumTriRoom = 8;
            geom.num_triangles = NumTriRoom;

            const triangles = [NumTriRoom]AK.SpatialAudio.AkTriangle{
                .{ .point0 = 0, .point1 = 1, .point2 = 2, .surface = 0 },
                .{ .point0 = 0, .point1 = 2, .point2 = 3, .surface = 0 },
                .{ .point0 = 2, .point1 = 3, .point2 = 4, .surface = 0 },
                .{ .point0 = 2, .point1 = 4, .point2 = 5, .surface = 0 },
                .{ .point0 = 4, .point1 = 5, .point2 = 6, .surface = 0 },
                .{ .point0 = 4, .point1 = 6, .point2 = 7, .surface = 0 },
                .{ .point0 = 0, .point1 = 1, .point2 = 6, .surface = 0 },
                .{ .point0 = 0, .point1 = 6, .point2 = 7, .surface = 0 },
            };
            geom.triangles = &triangles;

            const spatial_audio_id = AK.SpatialAudio.AkSpatialAudioID{ .id = 1 };
            try AK.SpatialAudio.setGeometry(spatial_audio_id, &geom);

            const instance_params = AK.SpatialAudio.AkGeometryInstanceParams{
                .geometry_set_id = spatial_audio_id,
                .room_id = Room,
            };

            try AK.SpatialAudio.setGeometryInstance(spatial_audio_id, &instance_params);
        }

        {
            // Obstacle, outside.
            //

            // Draw Lines.
            const Thickness = 5;

            const top_left_x_px = room0_width_px / 3.0;
            const top_left_y_px = room0_height_px * 1.333;
            const bottom_right_x_px = room0_width_px * 1.333;
            const bottom_right_y_px = top_left_y_px + Thickness;

            self.geometry[line] = .{
                .start_x = top_left_x_px,
                .start_y = top_left_y_px,
                .end_x = bottom_right_x_px,
                .end_y = top_left_y_px,
            };
            line += 1;
            self.geometry[line] = .{
                .start_x = bottom_right_x_px,
                .start_y = top_left_y_px,
                .end_x = bottom_right_x_px,
                .end_y = bottom_right_y_px,
            };
            line += 1;
            self.geometry[line] = .{
                .start_x = bottom_right_x_px,
                .start_y = bottom_right_y_px,
                .end_x = top_left_x_px,
                .end_y = bottom_right_y_px,
            };
            line += 1;
            self.geometry[line] = .{
                .start_x = top_left_x_px,
                .start_y = bottom_right_y_px,
                .end_x = top_left_x_px,
                .end_y = top_left_y_px,
            };
            line += 1;

            const top_left_x = demo.pixelsToAkPosX(top_left_x_px);
            const top_left_y = demo.pixelsToAkPosY(top_left_y_px);
            const bottom_right_x = demo.pixelsToAkPosX(bottom_right_x_px);
            const bottom_right_y = demo.pixelsToAkPosY(bottom_right_y_px);

            const NumVertices = 8;

            var geom = AK.SpatialAudio.AkGeometryParams{};
            geom.num_vertices = NumVertices;

            // In the coordinate system we have chosen, x is right-left, z is top-bottom and y is through screen. (0,0,0) is the center of the window.
            const vertices = [NumVertices]AK.SpatialAudio.AkVertex{
                .{ .x = top_left_x, .y = 30.0, .z = top_left_y },
                .{ .x = top_left_x, .y = -30.0, .z = top_left_y },
                .{ .x = bottom_right_x, .y = -30.0, .z = top_left_y },
                .{ .x = bottom_right_x, .y = 30.0, .z = top_left_y },
                .{ .x = bottom_right_x, .y = 30.0, .z = bottom_right_y },
                .{ .x = bottom_right_x, .y = -30.0, .z = bottom_right_y },
                .{ .x = top_left_x, .y = -30.0, .z = bottom_right_y },
                .{ .x = top_left_x, .y = 30.0, .z = bottom_right_y },
            };
            geom.vertices = &vertices;

            // Assign surfaces. Direct path diffraction is not affected by the acoustic properties of surfaces, because in this model, the edges don't absorb any energy.
            // In this demo, the only purpose of using acoustic surfaces with textures defined in Wwise is for showing colors in the 3D Game Object Viewer.
            geom.num_surfaces = 1;
            const obstacle_surface = AK.SpatialAudio.AkAcousticSurface{
                .str_name = "Wall",
                .texture_id = try AK.SoundEngine.getIDFromString(demo.allocator, "Brick"),
                .transmission_loss = 0.95,
            };
            geom.surfaces = @ptrCast(&obstacle_surface);

            const NumTriRoom = 8;
            geom.num_triangles = NumTriRoom;

            const triangles = [NumTriRoom]AK.SpatialAudio.AkTriangle{
                .{ .point0 = 0, .point1 = 1, .point2 = 2, .surface = 0 },
                .{ .point0 = 0, .point1 = 2, .point2 = 3, .surface = 0 },
                .{ .point0 = 2, .point1 = 3, .point2 = 4, .surface = 0 },
                .{ .point0 = 2, .point1 = 4, .point2 = 5, .surface = 0 },
                .{ .point0 = 4, .point1 = 5, .point2 = 6, .surface = 0 },
                .{ .point0 = 4, .point1 = 6, .point2 = 7, .surface = 0 },
                .{ .point0 = 6, .point1 = 7, .point2 = 6, .surface = 0 },
                .{ .point0 = 6, .point1 = 0, .point2 = 1, .surface = 0 },
            };
            geom.triangles = &triangles;

            geom.enable_diffraction = true;
            // We did not add triangles on the top and bottom (through screen) of our "wall", and set EnableDiffractionOnBoundaryEdges to false,
            // so that sound does not diffract via the top and bottom edges.
            geom.enable_diffraction_on_boundary_edges = false;

            const spatial_audio_id = AK.SpatialAudio.AkSpatialAudioID{ .id = 1 };
            try AK.SpatialAudio.setGeometry(spatial_audio_id, &geom);

            const instance_params = AK.SpatialAudio.AkGeometryInstanceParams{
                .geometry_set_id = spatial_audio_id,
                .room_id = AK.SpatialAudio.getOutdoorRoomID(),
            };
            try AK.SpatialAudio.setGeometryInstance(spatial_audio_id, &instance_params);
        }

        self.inited = true;
    }

    pub fn deinit(self: GeometryInRooms) void {
        _ = self;

        AK.SpatialAudio.removeGeometry(0) catch {};
        AK.SpatialAudio.removeGeometry(1) catch {};
        AK.SpatialAudio.removeGeometry(2) catch {};
    }

    pub fn draw(self: GeometryInRooms, draw_list: zgui.DrawList) void {
        if (!self.inited) {
            return;
        }

        for (self.geometry) |line| {
            line.draw(draw_list);
        }
    }
};
