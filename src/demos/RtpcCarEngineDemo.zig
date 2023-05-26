const std = @import("std");
const DemoInterface = @import("../DemoInterface.zig");
const zgui = @import("zgui");

allocator: std.mem.Allocator = undefined,
is_visible: bool = false,
bank_id: u32 = 0, // TODO: Use AK.AkBankID
is_playing: bool = false,
rpm_value: i32 = 0,

const Self = @This();

const MinRPMValue = 1000;
const MaxRPMValue = 10000;

pub fn init(self: *Self, allocator: std.mem.Allocator) !void {
    self.allocator = allocator;

    self.rpm_value = MinRPMValue;

    // self.bankID = try Wwise.loadBankByString("Car.bnk");
    // try Wwise.registerGameObj(DemoGameObjectID, "Car");

    // try Wwise.setRTPCValueByString("RPM", @intToFloat(f32, self.rpmValue), DemoGameObjectID);
}

pub fn deinit(self: *Self) void {
    //    _ = Wwise.unloadBankByID(self.bankID);

    //     Wwise.unregisterGameObj(DemoGameObjectID);

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self) !void {
    if (zgui.begin("RTPC Demo (Car Engine)", .{ .popen = &self.is_visible, .flags = .{ .always_auto_resize = true } })) {
        const button_text = if (self.is_playing) "Stop Engine" else "Start Engine";

        if (zgui.button(button_text, .{})) {
            if (self.is_playing) {
                // _ = try Wwise.postEvent("Stop_Engine", DemoGameObjectID);
                self.is_playing = false;
            } else {
                // _ = try Wwise.postEvent("Play_Engine", DemoGameObjectID);
                self.is_playing = true;
            }
        }

        if (zgui.sliderInt("RPM", .{ .v = &self.rpm_value, .min = MinRPMValue, .max = MaxRPMValue })) {
            //try Wwise.setRTPCValueByString("RPM", @intToFloat(f32, self.rpmValue), DemoGameObjectID);
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
