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
geometry: [2]Line = [_]Line{Line{}} ** 2,
lines: std.ArrayListUnmanaged(Line) = .{},
game_object_x: f32 = 0.0,
game_object_z: f32 = 0.0,
diffraction: f32 = 0.0,
transmission_loss: f32 = 0.0,
width: f32 = 0.0,
height: f32 = 0.0,
is_first_update: bool = true,

const Self = @This();

const EmitterObj: AK.AkGameObjectID = 100;
const ListenerObj: AK.AkGameObjectID = 103;
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
}

pub fn deinit(self: *Self, demo_state: *root.DemoState) void {
    _ = demo_state;

    self.lines.deinit(self.allocator);

    AK.SpatialAudio.removeGeometry(.{ .id = 0 }) catch {};
    AK.SpatialAudio.removeGeometry(.{ .id = 1 }) catch {};

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

    if (zgui.begin("Spatial Audio - Geometry", .{ .popen = &self.is_visible, .flags = .{} })) {
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
            self.emitter_cursor.update();
        } else {
            self.listener_cursor.update();
        }

        try self.updateMoved();

        zgui.text("X: {d:.2}", .{self.game_object_x});
        zgui.text("Z: {d:.2}", .{self.game_object_z});
        zgui.text("Diffraction: {d:.2}", .{self.diffraction});
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

        for (self.lines.items) |line| {
            line.draw(draw_list);
        }

        for (self.geometry) |line| {
            line.draw(draw_list);
        }

        zgui.end();
    }

    if (!self.is_visible) {
        AK.SoundEngine.stopAll(.{});
    }
}

pub fn updateMoved(self: *Self) !void {
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

    self.diffraction = 0.0;
    self.transmission_loss = 0.0;

    var diffraction: f32 = 1.0;
    var tramission_loss: f32 = 0.0;

    if (num_lines > 0) {
        for (0..num_paths) |path| {
            if (paths[path].node_count > 0) {
                // Listener to node 0.
                try self.lines.append(self.allocator, .{
                    .start_x = self.akPosToPixelsX(@floatCast(listener_position.x)),
                    .start_y = self.akPosToPixelsY(@floatCast(listener_position.z)),
                    .end_x = self.akPosToPixelsX(@floatCast(paths[path].nodes[0].x)),
                    .end_y = self.akPosToPixelsY(@floatCast(paths[path].nodes[0].z)),
                });

                var node: u32 = 1;
                while (node < paths[path].node_count) : (node += 1) {
                    try self.lines.append(self.allocator, .{
                        .start_x = self.akPosToPixelsX(@floatCast(paths[path].nodes[node - 1].x)),
                        .start_y = self.akPosToPixelsY(@floatCast(paths[path].nodes[node - 1].z)),
                        .end_x = self.akPosToPixelsX(@floatCast(paths[path].nodes[node].x)),
                        .end_y = self.akPosToPixelsY(@floatCast(paths[path].nodes[node].z)),
                    });
                }

                // Last node to emitter
                try self.lines.append(self.allocator, .{
                    .start_x = self.akPosToPixelsX(@floatCast(paths[path].nodes[node - 1].x)),
                    .start_y = self.akPosToPixelsY(@floatCast(paths[path].nodes[node - 1].z)),
                    .end_x = self.akPosToPixelsX(@floatCast(emitter_position.x)),
                    .end_y = self.akPosToPixelsY(@floatCast(emitter_position.z)),
                });
            } else {
                // A path with no node: completely obstructed. Draw a line from emitter to listener, with style "Selected" (Draw() checks m_diffraction)
                try self.lines.append(self.allocator, .{
                    .start_x = self.akPosToPixelsX(@floatCast(emitter_position.x)),
                    .start_y = self.akPosToPixelsY(@floatCast(emitter_position.z)),
                    .end_x = self.akPosToPixelsX(@floatCast(listener_position.x)),
                    .end_y = self.akPosToPixelsY(@floatCast(listener_position.z)),
                });
            }

            if (paths[path].transmission_loss == 0.0) {
                diffraction = @min(diffraction, paths[path].diffraction);
            } else {
                tramission_loss = paths[path].transmission_loss;
            }
        }

        self.diffraction = diffraction * 100.0;
        self.transmission_loss = tramission_loss * 100.0;
    } else {
        // No path: we must have direct line of sight. Draw a line from emitter to listener.
        try self.lines.append(self.allocator, .{
            .start_x = self.akPosToPixelsX(@floatCast(emitter_position.x)),
            .start_y = self.akPosToPixelsY(@floatCast(emitter_position.z)),
            .end_x = self.akPosToPixelsX(@floatCast(listener_position.x)),
            .end_y = self.akPosToPixelsY(@floatCast(listener_position.z)),
        });
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

fn updateGameObjectPos(self: *Self, in_cursor: Cursor, in_game_object_id: AK.AkGameObjectID) !void {
    const x = in_cursor.x;
    const y = in_cursor.y;

    self.game_object_x = self.pixelsToAkPosX(x);
    self.game_object_z = self.pixelsToAkPosY(y);

    const sound_position = AK.AkSoundPosition{
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
    try self.initGeometry();

    _ = try AK.SoundEngine.postEventID(ID.EVENTS.PLAY_ROOM_EMITTER, EmitterObj, .{});
}

fn initGeometry(self: *Self) !void {
    const room0_width_px = self.width / 2.0;
    var room0_height_px: f32 = self.height / 2.0 - 60.0;
    if (room0_height_px < 0) {
        room0_height_px = 0;
    }

    // 2 disjoint meshes: an horizontal wall (on the bottom left) and a vertical wall (on the right).
    // For diffraction, it is important to join meshes to avoid sound leaking through cracks.
    // Here in our 2D geometry, we do not assign triangles to the top and bottom planes (through screen), and utilize
    // AkGeometryParams::EnableDiffractionOnBoundaryEdges = false so that edges on top and bottom will not allow sound to pass
    // through the ceiling or floor. Likewise, we do not assign triangles on the left of the horizontal wall.
    //
    //        |
    // ----   |

    // Vertical wall.
    //

    // Draw Line.

    const center_x = self.akPosToPixelsX(0.0);
    const center_y = self.akPosToPixelsY(0.0);

    self.geometry[0] = .{
        .start_x = center_x,
        .start_y = center_y,
        .end_x = center_x,
        .end_y = center_y - room0_height_px,
    };

    const room0_height = self.pixelsToAkLenY(room0_height_px);

    var geom = AK.SpatialAudio.AkGeometryParams{};

    const vertices0 = [8]AK.SpatialAudio.AkVertex{
        .{ .x = 0.0, .y = -30.0, .z = 0.0 },
        .{ .x = 0.0, .y = 30.0, .z = 0.0 },
        .{ .x = 0.0, .y = 30.0, .z = room0_height },
        .{ .x = 0.0, .y = -30.0, .z = room0_height },
        .{ .x = -1.0, .y = -30.0, .z = room0_height },
        .{ .x = -1.0, .y = 30.0, .z = room0_height },
        .{ .x = -1.0, .y = 30.0, .z = 0.0 },
        .{ .x = -1.0, .y = -30.0, .z = 0.0 },
    };
    geom.num_vertices = 8;
    geom.vertices = &vertices0;

    geom.num_surfaces = 2;
    const surfaces = [2]AK.SpatialAudio.AkAcousticSurface{
        .{
            .str_name = "Outside",
            .texture_id = try AK.SoundEngine.getIDFromString(self.allocator, "Brick"),
        },
        .{
            .str_name = "Inside",
            .texture_id = try AK.SoundEngine.getIDFromString(self.allocator, "Drywall"),
        },
    };
    geom.surfaces = &surfaces;

    geom.num_triangles = 8;
    const triangles0 = [8]AK.SpatialAudio.AkTriangle{
        .{ .point0 = 0, .point1 = 1, .point2 = 2, .surface = 0 },
        .{ .point0 = 0, .point1 = 2, .point2 = 3, .surface = 0 },
        .{ .point0 = 2, .point1 = 3, .point2 = 4, .surface = 0 },
        .{ .point0 = 2, .point1 = 4, .point2 = 5, .surface = 0 },
        .{ .point0 = 4, .point1 = 5, .point2 = 6, .surface = 0 },
        .{ .point0 = 4, .point1 = 6, .point2 = 7, .surface = 0 },
        .{ .point0 = 7, .point1 = 0, .point2 = 6, .surface = 0 },
        .{ .point0 = 6, .point1 = 0, .point2 = 1, .surface = 0 },
    };
    geom.triangles = &triangles0;

    geom.enable_diffraction = true;
    geom.enable_diffraction_on_boundary_edges = false;

    try AK.SpatialAudio.setGeometry(.{ .id = 0 }, &geom);

    var instance_params = AK.SpatialAudio.AkGeometryInstanceParams{
        .geometry_set_id = .{ .id = 0 },
    };

    try AK.SpatialAudio.setGeometryInstance(.{ .id = 0 }, &instance_params);

    // Horizontal wall
    //

    const horizontal_wall_right_px = center_x - 60;
    self.geometry[1] = .{
        .start_x = horizontal_wall_right_px,
        .start_y = center_y,
        .end_x = center_x - room0_width_px,
        .end_y = center_y,
    };

    const horizontal_wall_right = -self.pixelsToAkLenX(60.0);
    const horizontal_wall_left = -self.pixelsToAkLenX(room0_width_px);

    const vertices1 = [8]AK.SpatialAudio.AkVertex{
        .{ .x = horizontal_wall_right, .y = -30.0, .z = 0.0 },
        .{ .x = horizontal_wall_right, .y = 30.0, .z = 0.0 },
        .{ .x = horizontal_wall_right, .y = 30.0, .z = -1.0 },
        .{ .x = horizontal_wall_right, .y = -30.0, .z = -1.0 },
        .{ .x = horizontal_wall_left, .y = -30.0, .z = -1.0 },
        .{ .x = horizontal_wall_left, .y = 30.0, .z = -1.0 },
        .{ .x = horizontal_wall_left, .y = 30.0, .z = 0.0 },
        .{ .x = horizontal_wall_left, .y = -30.0, .z = 0.0 },
    };
    geom.num_vertices = 8;
    geom.vertices = &vertices1;

    geom.num_triangles = 6;
    const triangles1 = [6]AK.SpatialAudio.AkTriangle{
        .{ .point0 = 0, .point1 = 1, .point2 = 2, .surface = 0 },
        .{ .point0 = 0, .point1 = 2, .point2 = 3, .surface = 0 },
        .{ .point0 = 2, .point1 = 3, .point2 = 4, .surface = 0 },
        .{ .point0 = 2, .point1 = 4, .point2 = 5, .surface = 0 },
        .{ .point0 = 7, .point1 = 0, .point2 = 6, .surface = 0 },
        .{ .point0 = 6, .point1 = 0, .point2 = 1, .surface = 0 },
    };
    geom.triangles = &triangles1;

    geom.enable_diffraction = true;
    geom.enable_diffraction_on_boundary_edges = false;

    try AK.SpatialAudio.setGeometry(.{ .id = 1 }, &geom);

    instance_params.geometry_set_id = .{ .id = 1 };

    try AK.SpatialAudio.setGeometryInstance(.{ .id = 1 }, &instance_params);
}
