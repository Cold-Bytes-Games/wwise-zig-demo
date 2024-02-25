const std = @import("std");
const DemoInterface = @import("../DemoInterface.zig");
const zgui = @import("zgui");
const root = @import("root");
const AK = @import("wwise-zig");

allocator: std.mem.Allocator = undefined,
is_visible: bool = false,
bank_id: AK.AkBankID = AK.AK_INVALID_BANK_ID,
is_media_set: bool = false,
media_buffer: ?*anyopaque = null,
media_size: u32 = 0,
is_prepared: bool = false,

const Self = @This();
const DemoGameObjectID: AK.AkGameObjectID = 100;

const EventName = "Play_Hello_Reverb";
const MediaID: AK.AkUniqueID = 399670944;
const MediaFilename = "399670944.wem";

pub fn init(self: *Self, allocator: std.mem.Allocator, demo_state: *root.DemoState) !void {
    _ = demo_state;
    self.* = .{
        .allocator = allocator,
    };

    try AK.SoundEngine.registerGameObjWithName(allocator, DemoGameObjectID, "Human");

    self.bank_id = try AK.SoundEngine.loadBankString(allocator, EventName ++ ".bnk", .{ .bank_type = .event });
}

pub fn deinit(self: *Self, demo_state: *root.DemoState) void {
    _ = demo_state;

    if (self.is_prepared) {
        self.togglePrepared() catch {};
    }

    while (self.is_media_set) {
        self.toggleSetMedia() catch {};

        if (self.is_media_set) {
            AK.SoundEngine.renderAudio(true) catch {};
        }
    }

    AK.SoundEngine.unloadBankID(self.bank_id, null, .{}) catch {};

    AK.SoundEngine.unregisterGameObj(DemoGameObjectID) catch {};

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self, demo_state: *root.DemoState) !void {
    _ = demo_state;
    if (zgui.begin("Autobanks Demo", .{ .popen = &self.is_visible, .flags = .{ .always_auto_resize = true } })) {
        if (self.is_prepared) {
            if (zgui.button("Un-prepare the event", .{})) {
                try self.togglePrepared();
            }
        } else {
            if (zgui.button("Load media using PrepareEvent", .{})) {
                try self.togglePrepared();
            }
        }

        if (self.is_media_set) {
            if (zgui.button("Unset media", .{})) {
                try self.toggleSetMedia();
            }
        } else {
            if (zgui.button("Load media using SetMedia", .{})) {
                try self.toggleSetMedia();
            }
        }

        if (zgui.button("Post Event", .{})) {
            _ = try AK.SoundEngine.postEventString(self.allocator, EventName, DemoGameObjectID, .{});
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
    return DemoInterface.toDemoInteface(self);
}

fn togglePrepared(self: *Self) !void {
    if (!self.is_prepared) {
        try AK.SoundEngine.prepareEventString(self.allocator, .load, &.{EventName});
        self.is_prepared = true;
    } else {
        try AK.SoundEngine.prepareEventString(self.allocator, .unload, &.{EventName});
        self.is_prepared = false;
    }
}

fn toggleSetMedia(self: *Self) !void {
    if (!self.is_media_set) {
        const stream_mgr_opt = AK.IAkStreamMgr.get();
        if (stream_mgr_opt) |stream_mgr| {
            var stream_opt: ?*AK.IAkStdStream = null;

            const flags = AK.AkFileSystemFlags{
                .company_id = AK.AKCOMPANYID_AUDIOKINETIC,
                .codec_id = AK.AKCODECID_VORBIS,
                .is_language_specific = true,
            };

            const open_file_data = AK.AkFileOpenData{
                .file_name = MediaFilename,
                .flags = flags,
                .open_mode = .read,
            };

            try stream_mgr.createStd(self.allocator, open_file_data, &stream_opt, true);

            if (stream_opt) |stream| {
                defer stream.destroy();

                const info = try stream.getInfo(self.allocator);
                defer info.deinit(self.allocator);

                const alloc_size: usize = (@as(usize, info.size) + @as(usize, stream.getBlockSize()) - 1) / @as(usize, stream.getBlockSize()) * @as(usize, stream.getBlockSize());

                self.media_buffer = AK.MemoryMgr.malign(@intFromEnum(AK.MemoryMgr.AkMemID.media), alloc_size, AK.AK_BANK_PLATFORM_DATA_ALIGNMENT);

                if (self.media_buffer) |media_buffer| {
                    errdefer {
                        AK.MemoryMgr.free(@intFromEnum(AK.MemoryMgr.AkMemID.media), self.media_buffer);
                        self.media_buffer = null;
                        self.media_size = 0;
                    }

                    try stream.read(media_buffer, @as(u32, @truncate(alloc_size)), true, AK.AK_DEFAULT_BANK_IO_PRIORITY, @as(f32, @floatFromInt(info.size)) / AK.AK_DEFAULT_BANK_THROUGHPUT, &self.media_size);

                    if (stream.getStatus() == .completed) {
                        std.debug.assert(self.media_size == info.size);

                        try AK.SoundEngine.setMedia(&.{
                            .{
                                .source_id = MediaID,
                                .media_memory = self.media_buffer,
                                .media_size = self.media_size,
                            },
                        });
                        self.is_media_set = true;
                    }
                }
            }
        }
    } else {
        AK.SoundEngine.tryUnsetMedia(
            &.{
                .{
                    .source_id = MediaID,
                    .media_memory = self.media_buffer,
                    .media_size = self.media_size,
                },
            },
            null,
        ) catch |err| {
            if (err != AK.WwiseError.ResourceInUse) {
                return err;
            }
        };

        AK.MemoryMgr.free(@intFromEnum(AK.MemoryMgr.AkMemID.media), self.media_buffer);
        self.media_buffer = null;
        self.media_size = 0;
        self.is_media_set = false;
    }
}
