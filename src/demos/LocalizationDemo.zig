const std = @import("std");
const DemoInterface = @import("../DemoInterface.zig");
const zgui = @import("zgui");
const AK = @import("wwise-zig");

allocator: std.mem.Allocator = undefined,
is_visible: bool = false,
bank_id: AK.AkBankID = AK.AK_INVALID_BANK_ID,
current_selected_language: usize = 0,

const Self = @This();
const DemoGameObjectID: AK.AkGameObjectID = 3;

const Languages = &[_][:0]const u8{ "English(US)", "French(Canada)" };

pub fn init(self: *Self, allocator: std.mem.Allocator) !void {
    self.* = .{
        .allocator = allocator,
    };

    try AK.StreamMgr.setCurrentLanguage(allocator, Languages[0]);

    self.bank_id = try AK.SoundEngine.loadBankString(allocator, "Human.bnk", .{});
    try AK.SoundEngine.registerGameObjWithName(allocator, DemoGameObjectID, "LocalizationDemo");
}

pub fn deinit(self: *Self) void {
    AK.StreamMgr.setCurrentLanguage(self.allocator, Languages[0]) catch {};

    AK.SoundEngine.unloadBankID(self.bank_id, null, .{}) catch {};
    AK.SoundEngine.unregisterGameObj(DemoGameObjectID) catch {};

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self) !void {
    if (zgui.begin("Localization Demo", .{ .popen = &self.is_visible, .flags = .{ .always_auto_resize = true } })) {
        if (zgui.button("Say \"Hello\"", .{})) {
            _ = try AK.SoundEngine.postEventString(self.allocator, "Play_Hello", DemoGameObjectID, .{});
        }

        const first_language = Languages[self.current_selected_language];

        if (zgui.beginCombo("Language", .{ .preview_value = first_language })) {
            for (Languages, 0..) |language, i| {
                const is_selected = (self.current_selected_language == i);

                if (zgui.selectable(language, .{ .selected = is_selected })) {
                    self.current_selected_language = i;

                    try AK.StreamMgr.setCurrentLanguage(self.allocator, Languages[self.current_selected_language]);

                    try AK.SoundEngine.unloadBankID(self.bank_id, null, .{});

                    self.bank_id = try AK.SoundEngine.loadBankString(self.allocator, "Human.bnk", .{});
                }

                if (is_selected) {
                    zgui.setItemDefaultFocus();
                }
            }

            zgui.endCombo();
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
