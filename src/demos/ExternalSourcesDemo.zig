const std = @import("std");
const DemoInterface = @import("../DemoInterface.zig");
const zgui = @import("zgui");
const root = @import("root");
const AK = @import("wwise-zig");
const ID = @import("../ID.zig");

allocator: std.mem.Allocator = undefined,
is_visible: bool = false,
bank_id: AK.AkBankID = AK.AK_INVALID_BANK_ID,
package_id: u32 = 0,

const CodecTypeStandard = AK.AKCODECID_ADPCM;

const Self = @This();
const DemoGameObjectID: AK.AkGameObjectID = 100;

pub fn init(self: *Self, allocator: std.mem.Allocator, demo_state: *root.DemoState) !void {
    self.* = .{
        .allocator = allocator,
    };

    if (demo_state.wwise_context.io_hook) |io_hook| {
        self.package_id = try io_hook.loadFilePackage(allocator, "ExternalSources.pck");
    } else {
        return error.InvalidIOHook;
    }
    self.bank_id = try AK.SoundEngine.loadBankString(allocator, "ExternalSources.bnk", .{});
    try AK.SoundEngine.registerGameObjWithName(allocator, DemoGameObjectID, "Human");
}

pub fn deinit(self: *Self, demo_state: *root.DemoState) void {
    AK.SoundEngine.unregisterGameObj(DemoGameObjectID) catch {};
    AK.SoundEngine.unloadBankID(self.bank_id, null, .{}) catch {};

    if (demo_state.wwise_context.io_hook) |io_hook| {
        io_hook.unloadFilePackage(self.package_id) catch {};
    }

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self, demo_state: *root.DemoState) !void {
    _ = demo_state;

    zgui.setNextWindowSize(.{
        .w = 215,
        .h = 80,
        .cond = .always,
    });
    if (zgui.begin("External Sources Demo", .{ .popen = &self.is_visible, .flags = .{ .always_auto_resize = true } })) {
        if (zgui.button("Play \"1 2 3\"", .{})) {
            const external_sources = [_]AK.AkExternalSourceInfo{
                .{
                    .external_src_cookie = try AK.SoundEngine.getIDFromString(self.allocator, "Extern_1st_number"),
                    .file = "01.wem",
                    .id_codec = CodecTypeStandard,
                },
                .{
                    .external_src_cookie = try AK.SoundEngine.getIDFromString(self.allocator, "Extern_2nd_number"),
                    .file = "02.wem",
                    .id_codec = CodecTypeStandard,
                },
                .{
                    .external_src_cookie = try AK.SoundEngine.getIDFromString(self.allocator, "Extern_3rd_number"),
                    .file = "03.wem",
                    .id_codec = CodecTypeStandard,
                },
            };

            _ = try AK.SoundEngine.postEventID(ID.EVENTS.PLAY_THREE_NUMBERS_IN_A_ROW, DemoGameObjectID, .{
                .allocator = self.allocator,
                .external_sources = &external_sources,
            });
        }

        if (zgui.button("Play \"4 5 6\"", .{})) {
            const external_sources = [_]AK.AkExternalSourceInfo{
                .{
                    .external_src_cookie = try AK.SoundEngine.getIDFromString(self.allocator, "Extern_1st_number"),
                    .file = "04.wem",
                    .id_codec = CodecTypeStandard,
                },
                .{
                    .external_src_cookie = try AK.SoundEngine.getIDFromString(self.allocator, "Extern_2nd_number"),
                    .file = "05.wem",
                    .id_codec = CodecTypeStandard,
                },
                .{
                    .external_src_cookie = try AK.SoundEngine.getIDFromString(self.allocator, "Extern_3rd_number"),
                    .file = "06_high.wem",
                    .id_codec = AK.AKCODECID_PCM,
                },
            };

            _ = try AK.SoundEngine.postEventID(ID.EVENTS.PLAY_THREE_NUMBERS_IN_A_ROW, DemoGameObjectID, .{
                .allocator = self.allocator,
                .external_sources = &external_sources,
            });
        }

        zgui.end();
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
