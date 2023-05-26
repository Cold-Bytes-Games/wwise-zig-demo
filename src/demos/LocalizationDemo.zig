const std = @import("std");
const DemoInterface = @import("../DemoInterface.zig");
const zgui = @import("zgui");

allocator: std.mem.Allocator = undefined,
is_visible: bool = false,
bank_id: u32 = 0, // TODO: Use AK.AkBankID
current_selected_language: usize = 0,

const Self = @This();
const DemoGameObjectID = 3;

const Languages = &[_][:0]const u8{ "English(US)", "French(Canada)" };

pub fn init(self: *Self, allocator: std.mem.Allocator) !void {
    self.allocator = allocator;

    self.current_selected_language = 0;

    // try Wwise.setCurrentLanguage(Languages[0]);

    // self.bankID = try Wwise.loadBankByString("Human.bnk");
    // try Wwise.registerGameObj(DemoGameObjectID, "LocalizationDemo");
}

pub fn deinit(self: *Self) void {
    // _ = Wwise.unloadBankByID(self.bankID);

    // Wwise.unregisterGameObj(DemoGameObjectID);

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self) !void {
    if (zgui.begin("Localization Demo", .{ .popen = &self.is_visible, .flags = .{ .always_auto_resize = true } })) {
        if (zgui.button("Say \"Hello\"", .{})) {
            //_ = try AK.SoundEngine.postEventString("Play_Hello", DemoGameObjectID, .{});
        }

        const first_language = Languages[self.current_selected_language];

        if (zgui.beginCombo("Language", .{ .preview_value = first_language })) {
            for (Languages, 0..) |language, i| {
                const is_selected = (self.current_selected_language == i);

                if (zgui.selectable(language, .{ .selected = is_selected })) {
                    self.current_selected_language = i;

                    // try Wwise.setCurrentLanguage(Languages[self.current_selected_language]);

                    // _ = Wwise.unloadBankByID(self.bankID);
                    // self.bankID = try Wwise.loadBankByString("Human.bnk");
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
