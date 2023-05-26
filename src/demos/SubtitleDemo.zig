const std = @import("std");
const DemoInterface = @import("../DemoInterface.zig");
const zgui = @import("zgui");

allocator: std.mem.Allocator = undefined,
subtitle_text: [:0]const u8 = undefined,
subtitle_index: u32 = 0,
subtitle_position: u32 = 0, // TOD: Use Ak.TimeMs
playing_id: u32 = 0, //TODO: Use AK.AkPlayingID
is_playing: bool = false,
is_visible: bool = false,
bank_id: u32 = 0, // TODO: Use AK.AkBankID

const Self = @This();

const DemoGameObjectID = 2;

pub fn init(self: *Self, allocator: std.mem.Allocator) !void {
    self.* = .{};

    self.allocator = allocator;
    self.subtitle_text = try self.allocator.dupeZ(u8, "");

    // self.bank_id = try Wwise.loadBankByString("MarkerTest.bnk");
    // try Wwise.registerGameObj(DemoGameObjectID, "SubtitleDemo");
}

pub fn deinit(self: *Self) void {
    //  _ = Wwise.unloadBankByID(self.bankID);

    //     Wwise.unregisterGameObj(DemoGameObjectID);

    self.allocator.free(self.subtitle_text);

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self) !void {
    if (zgui.begin("Subtitle Demo", .{ .popen = &self.is_visible, .flags = .{ .always_auto_resize = true } })) {
        if (self.is_playing) {
            zgui.text("--Playing--", .{});
        } else {
            if (zgui.button("Play Markers", .{ .w = 120 })) {
                //self.playingID = try Wwise.postEventWithCallback("Play_Markers_Test", DemoGameObjectID, Wwise.AkCallbackType.Marker | Wwise.AkCallbackType.EndOfEvent | Wwise.AkCallbackType.EnableGetSourcePlayPosition, WwiseSubtitleCallback, self);
                self.is_playing = true;
            }
        }

        if (!std.mem.eql(u8, self.subtitle_text, "")) {
            const play_position = 0; //Wwise.getSourcePlayPosition(self.playingID, true) catch 0;

            zgui.text("Cue #{}, Sample #{}", .{ self.subtitle_index, self.subtitle_position });
            zgui.text("Time: {} ms", .{play_position});
            zgui.text("{s}", .{self.subtitle_text});
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

pub fn setSubtitleText(self: *Self, text: [:0]const u8) void {
    self.allocator.free(self.subtitle_text);
    self.subtitle_text = self.allocator.dupeZ(u8, text) catch unreachable;
}

// fn WwiseSubtitleCallback(callbackType: u32, callbackInfo: [*c]Wwise.AkCallbackInfo) callconv(.C) void {
//     if (callbackType == Wwise.AkCallbackType.Marker) {
//         if (callbackInfo[0].pCookie) |cookie| {
//             var subtitleDemo = @ptrCast(*SubtitleDemo, @alignCast(8, cookie));
//             var markerCallback = @ptrCast(*Wwise.AkMarkerCallbackInfo, callbackInfo);

//             subtitleDemo.setSubtitleText(std.mem.span(markerCallback.strLabel));
//             subtitleDemo.subtitleIndex = markerCallback.uIdentifier;
//             subtitleDemo.subtitlePosition = markerCallback.uPosition;
//         }
//     } else if (callbackType == Wwise.AkCallbackType.EndOfEvent) {
//         if (callbackInfo[0].pCookie) |cookie| {
//             var subtitleDemo = @ptrCast(*SubtitleDemo, @alignCast(8, cookie));

//             subtitleDemo.setSubtitleText("");
//             subtitleDemo.subtitleIndex = 0;
//             subtitleDemo.subtitlePosition = 0;
//             subtitleDemo.playingID = 0;
//               self.is_playing = false;
//         }
//     }
// }
