const std = @import("std");
const DemoInterface = @import("../DemoInterface.zig");
const zgui = @import("zgui");

allocator: std.mem.Allocator = undefined,
is_visible: bool = false,
bank_id: u32 = 0, // TODO: Use AK.AkBankID
pos_x: f32 = 300,
pos_y: f32 = 240,
last_x: f32 = 300,
last_y: f32 = 240,
weight: f32 = 25.0,
surface: usize = std.math.maxInt(usize),
current_banks: u32 = 0,
tick_count: isize = 0,
last_tick_count: isize = 0,

const Self = @This();

const DemoGameObjectID = 5;
const CursorSpeed = 5.0;
const BufferZone: f32 = 20.0;
const DistanceToSpeed = 10 / CursorSpeed;
const WalkPeriod = 30;

var SurfaceGroup: u32 = undefined;

const SurfaceInfo = struct {
    bank_name: []const u8,
    switch_id: u32,

    pub fn init(bank_name: []const u8) !SurfaceInfo {
        //const dotPosition = std.mem.lastIndexOfScalar(u8, bank_name, '.');
        //const bank_name_without_ext = if (dotPosition) |pos| bank_name[0..pos] else bank_name;

        return SurfaceInfo{
            .bank_name = bank_name,
            .switch_id = 0, //try Wwise.getIDFromString(bank_name_without_ext),
        };
    }
};

var Surfaces: [4]SurfaceInfo = undefined;

pub fn init(self: *Self, allocator: std.mem.Allocator) !void {
    self.* = .{};
    self.allocator = allocator;

    // try Wwise.registerGameObj(DemoGameObjectID, "Human");

    Surfaces = [_]SurfaceInfo{
        try SurfaceInfo.init("Dirt.bnk"),
        try SurfaceInfo.init("Wood.bnk"),
        try SurfaceInfo.init("Metal.bnk"),
        try SurfaceInfo.init("Gravel.bnk"),
    };

    // SurfaceGroup = try Wwise.getIDFromString("Surface");
}

pub fn deinit(self: *Self) void {
    // _ = Wwise.unloadBankByID(self.bankID);

    //     Wwise.unregisterGameObj(DemoGameObjectID);

    //     for (Surfaces) |surface| {
    //         Wwise.unloadBankByString(surface.bank_name) catch {};
    //     }

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self) !void {
    self.tick_count += 1;

    zgui.setNextWindowSize(.{
        .w = 640,
        .h = 480,
        .cond = .first_use_ever,
    });

    if (zgui.begin("Footsteps Demo", .{ .popen = &self.is_visible, .flags = .{} })) {
        var draw_list = zgui.getWindowDrawList();

        _ = zgui.sliderFloat("Weight", .{ .v = &self.weight, .min = 0.0, .max = 100.0 });

        const white_color = zgui.colorConvertFloat4ToU32([4]f32{ 1.0, 1.0, 1.0, 1.0 });
        const red_color = zgui.colorConvertFloat4ToU32([4]f32{ 1.0, 0.0, 0.0, 1.0 });

        if (zgui.isKeyDown(.up_arrow)) {
            self.pos_y -= CursorSpeed;
        } else if (zgui.isKeyDown(.down_arrow)) {
            self.pos_y += CursorSpeed;
        } else if (zgui.isKeyDown(.left_arrow)) {
            self.pos_x -= CursorSpeed;
        } else if (zgui.isKeyDown(.right_arrow)) {
            self.pos_x += CursorSpeed;
        }

        const window_pos = zgui.getCursorScreenPos();
        const window_size = zgui.getContentRegionAvail();

        if (self.pos_x < 7) {
            self.pos_x = 7;
        } else if (self.pos_x >= window_size[0] - 7) {
            self.pos_x = window_size[0] - 7;
        }

        if (self.pos_y < 7) {
            self.pos_y = 7;
        } else if (self.pos_y >= window_size[1] - 7) {
            self.pos_y = window_size[1] - 7;
        }

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

        draw_list.addCircle(.{
            .p = [2]f32{ window_pos[0] + self.pos_x, window_pos[1] + self.pos_y },
            .r = 7.0,
            .col = red_color,
            .num_segments = 8,
            .thickness = 2.0,
        });

        zgui.end();

        self.manageSurfaces(window_size);
        try self.playFootstep();
    }

    if (!self.is_visible) {
        //Wwise.stopAllOnGameObject(DemoGameObjectID);
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

fn manageSurfaces(self: *Self, window_size: [2]f32) void {
    var bank_masks: u32 = self.computeUsedBankMask(window_size);

    var i: usize = 0;
    while (i < Surfaces.len) : (i += 1) {
        const bit = @as(u32, 1) << @intCast(u5, i);

        if ((bank_masks & bit) == bit and (self.current_banks & bit) != bit) {
            // _ = Wwise.loadBankByString(Surfaces[i].bank_name) catch {
            //     bank_masks &= ~bit;
            // };
        }

        if ((bank_masks & bit) != bit and ((self.current_banks & bit) == bit)) {
            // Wwise.unloadBankByString(Surfaces[i].bank_name) catch {
            //     bank_masks |= bit;
            // };
        }
    }

    self.current_banks = bank_masks;

    const half_width = @floatToInt(usize, window_size[0] / 2.0);
    const half_height = @floatToInt(usize, window_size[1] / 2.0);
    const index_surface = @boolToInt(@floatToInt(usize, self.pos_x) > half_width) | (@as(usize, @boolToInt(@floatToInt(usize, self.pos_y) > half_height)) << @as(u6, 1));
    if (self.surface != index_surface) {
        //Wwise.setSwitchByID(SurfaceGroup, Surfaces[index_surface].switch_id, DemoGameObjectID);
        self.surface = index_surface;
    }
}

fn computeUsedBankMask(self: Self, window_size: [2]f32) u32 {
    const half_width = @floatToInt(i32, window_size[0] / 2);
    const half_height = @floatToInt(i32, window_size[1] / 2);
    const buffer_zone = @floatToInt(i32, BufferZone * 2);

    const left_div = @as(i32, @boolToInt(@floatToInt(i32, self.pos_x) > (half_width - buffer_zone)));
    const right_div = @as(i32, @boolToInt(@floatToInt(i32, self.pos_x) < (half_width + buffer_zone)));
    const top_div = @as(i32, @boolToInt(@floatToInt(i32, self.pos_y) > (half_height - buffer_zone)));
    const bottom_div = @as(i32, @boolToInt(@floatToInt(i32, self.pos_y) < (half_height + buffer_zone)));

    return @bitCast(u32, ((right_div & bottom_div) << 0) | ((left_div & bottom_div) << 1) | ((right_div & top_div) << 2) | ((left_div & top_div) << 3)) & 0x0F;
}

fn playFootstep(self: *Self) !void {
    const dx = self.pos_x - self.last_x;
    const dy = self.pos_y - self.last_y;
    const distance = std.math.sqrt(dx * dx + dy * dy);

    const speed = distance * DistanceToSpeed;
    //try Wwise.setRTPCValueByString("Footstep_Speed", speed, DemoGameObjectID);

    const period = @floatToInt(isize, WalkPeriod - speed);
    if (distance < 0.1 and self.last_tick_count != -1) {
        // try Wwise.setRTPCValueByString("Footstep_Weight", self.weight / 2.0, DemoGameObjectID);
        // _ = try Wwise.postEvent("Play_Footsteps", DemoGameObjectID);

        self.last_tick_count = -1;
    } else if (distance > 0.1 and (self.tick_count - self.last_tick_count) > period) {
        // try Wwise.setRTPCValueByString("Footstep_Weight", self.weight, DemoGameObjectID);
        // _ = try Wwise.postEvent("Play_Footsteps", DemoGameObjectID);

        self.last_tick_count = self.tick_count;
    }

    self.last_x = self.pos_x;
    self.last_y = self.pos_y;
}
