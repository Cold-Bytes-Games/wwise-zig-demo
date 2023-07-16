const std = @import("std");
const DemoInterface = @import("../DemoInterface.zig");
const zgui = @import("zgui");
const root = @import("root");
const AK = @import("wwise-zig");
const builtin = @import("builtin");

allocator: std.mem.Allocator = undefined,
is_visible: bool = false,
active_panning_rule: AK.AkPanningRule = .speakers,
active_channel_config: AK.AkChannelConfig = .{},
active_device_index: usize = 0,
active_channel_index: usize = 0,
device_ids: std.ArrayListUnmanaged(DeviceId) = .{},
device_names: std.ArrayListUnmanaged([:0]const u8) = .{},
default_audio_device_shareset_id: ?u32 = null,
spatial_audio_shareset_id: ?u32 = null,
spatial_audio_available: bool = false,
spatial_audio_requested: bool = false,

const Self = @This();

const DeviceId = struct {
    shareset_id: u32 = 0,
    device_id: u32 = 0,
};

pub fn init(self: *Self, allocator: std.mem.Allocator, demo_state: *root.DemoState) !void {
    _ = demo_state;
    self.* = .{
        .allocator = allocator,
    };

    try self.populateOutputDeviceOptions();

    self.active_panning_rule = try AK.SoundEngine.getPanningRule(0);
    self.active_channel_config = AK.SoundEngine.getSpeakerConfiguration(0);
    self.active_channel_index = indexOfChannelConfig(DefaultSpeakerConfig, self.active_channel_config) orelse 0;
}

pub fn deinit(self: *Self, demo_state: *root.DemoState) void {
    _ = demo_state;

    self.device_ids.deinit(self.allocator);

    for (self.device_names.items) |entry| {
        self.allocator.free(entry);
    }
    self.device_names.deinit(self.allocator);

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self, demo_state: *root.DemoState) !void {
    _ = demo_state;
    if (zgui.begin("Options", .{ .popen = &self.is_visible, .flags = .{ .always_auto_resize = true } })) {
        if (zgui.beginCombo("Device", .{ .preview_value = self.device_names.items[self.active_device_index] })) {
            for (self.device_names.items, 0..) |device_name, index| {
                const is_selected = self.active_device_index == index;

                if (zgui.selectable(device_name, .{ .selected = is_selected })) {
                    self.active_device_index = index;
                    try self.updateSpeakerConfigForShareset();
                    try self.updateOutputDevice();
                }
            }

            zgui.endCombo();
        }
        const panning_rule_cstr = try self.toPrettyCString(@tagName(self.active_panning_rule));
        defer self.allocator.free(panning_rule_cstr);

        if (zgui.beginCombo("Speaker Panning", .{ .preview_value = panning_rule_cstr })) {
            inline for (std.meta.fields(AK.AkPanningRule)) |panning_field| {
                const is_selected = @intFromEnum(self.active_panning_rule) == panning_field.value;

                const field_name_cstr = try self.toPrettyCString(panning_field.name);
                defer self.allocator.free(field_name_cstr);

                if (zgui.selectable(field_name_cstr, .{ .selected = is_selected })) {
                    self.active_panning_rule = @enumFromInt(panning_field.value);
                    try self.updateOutputDevice();
                }

                if (is_selected) {
                    zgui.setItemDefaultFocus();
                }
            }

            zgui.endCombo();
        }

        if (zgui.beginCombo("Speaker Config", .{ .preview_value = DefaultSpeakerConfigsName[self.active_channel_index] })) {
            for (0..DefaultSpeakerConfig.len) |index| {
                const is_selected = self.active_channel_index == index;

                if (zgui.selectable(DefaultSpeakerConfigsName[index], .{ .selected = is_selected })) {
                    self.active_channel_index = index;
                    try self.updateSpeakerConfigForShareset();
                    try self.updateOutputDevice();
                }

                if (is_selected) {
                    zgui.setItemDefaultFocus();
                }
            }

            zgui.endCombo();
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
    return DemoInterface.toDemoInteface(self);
}

fn populateOutputDeviceOptions(self: *Self) !void {
    try self.device_ids.append(self.allocator, DeviceId{});
    try self.device_names.append(self.allocator, try self.allocator.dupeZ(u8, "Use Default"));

    if (AK.SoundEngine.isInitialized()) {
        const init_settings = blk: {
            if (AK.SoundEngine.getGlobalPluginContext()) |plugin_context| {
                if (plugin_context.getInitSettings()) |init_settings| {
                    break :blk init_settings;
                }
            }

            return error.NoValidInitSettings;
        };

        const id_current = AK.SoundEngine.getOutputID(0, 0);

        for (SupportedAudioDeviceShareset) |shareset_name| {
            const shareset_id = try AK.SoundEngine.getIDFromString(self.allocator, shareset_name);

            var device_count: u32 = 0;
            AK.SoundEngine.getDeviceListShareSet(self.allocator, shareset_id, &device_count, null) catch {};
            if (device_count == 0) {
                const name = try std.fmt.allocPrintZ(self.allocator, "{s} - Primary  Output", .{shareset_name});
                try self.device_ids.append(self.allocator, DeviceId{ .shareset_id = shareset_id });
                try self.device_names.append(self.allocator, name);
            } else {
                const devices = try self.allocator.alloc(AK.AkDeviceDescription, device_count);
                defer {
                    for (devices) |device| {
                        device.deinit(self.allocator);
                    }
                }

                try AK.SoundEngine.getDeviceListShareSet(self.allocator, shareset_id, &device_count, @ptrCast(devices));

                var real_count: u32 = 0;
                for (devices) |device| {
                    if (device.device_state_mask.active) {
                        const name = try std.fmt.allocPrintZ(self.allocator, "{s} - {s}", .{ shareset_name, device.device_name });
                        try self.device_ids.append(self.allocator, DeviceId{ .shareset_id = shareset_id, .device_id = device.id_device });
                        try self.device_names.append(self.allocator, name);

                        if (device.is_default_device and shareset_id == init_settings.settings_main_output.audio_device_shareset) {
                            // Two possibilities to check: either the soundengine is using this output because we specifically asked it
                            // OR, it is the default.
                            if (init_settings.settings_main_output.id_device == 0) {
                                self.active_device_index = 0;
                            } else if (AK.SoundEngine.getOutputID(shareset_id, device.id_device) == id_current) {
                                //Specified explicitely
                                self.active_device_index = real_count + 1;
                            }
                        }

                        real_count += 1;
                    }
                }
            }
        }
    }
}

fn updateSpeakerConfigForShareset(self: *Self) !void {
    if (self.device_ids.items[self.active_device_index].shareset_id == try self.getDefaultAudioSharesetId() or self.device_ids.items[self.active_channel_index].shareset_id == 0) {
        self.active_channel_config = DefaultSpeakerConfig[self.active_channel_index];
    } else {
        self.active_channel_config = AK.AkChannelConfig{};
        self.active_channel_index = 0;
    }
}

fn updateOutputDevice(self: *Self) !void {
    if (!AK.SoundEngine.isInitialized()) {
        self.initSettingsChanged();
    }

    var new_settings: AK.AkOutputSettings = .{};
    try self.fillOutputSetting(&new_settings);

    try AK.SoundEngine.replaceOutput(&new_settings, 0, null);
}

fn fillOutputSetting(self: *Self, new_settings: *AK.AkOutputSettings) !void {
    const new_device_id = if (self.active_device_index < self.device_ids.items.len) self.device_ids.items[self.active_device_index] else DeviceId{ .shareset_id = try self.getDefaultAudioSharesetId() };

    const new_channel_config = self.active_channel_config;

    self.spatial_audio_available = blk: {
        AK.SoundEngine.getDeviceSpatialAudioSupport(new_device_id.device_id) catch {
            break :blk false;
        };

        break :blk true;
    };

    new_settings.audio_device_shareset = if (self.spatial_audio_requested and self.spatial_audio_available) try self.getSpatialAudioSharesetId() else new_device_id.shareset_id;
    new_settings.id_device = new_device_id.device_id;
    new_settings.panning_rule = self.active_panning_rule;

    if (new_channel_config.isValid()) {
        new_settings.channel_config = new_channel_config;
    } else {
        new_settings.channel_config.clear();
    }
}

fn toPrettyCString(self: *Self, value: []const u8) ![:0]const u8 {
    const pretty_ctring = try self.allocator.dupeZ(u8, value);
    pretty_ctring[0] = std.ascii.toUpper(pretty_ctring[0]);
    return pretty_ctring;
}

fn getDefaultAudioSharesetId(self: *Self) !u32 {
    if (self.default_audio_device_shareset_id) |default_audio_device_shareset_id| {
        return default_audio_device_shareset_id;
    }

    self.default_audio_device_shareset_id = try AK.SoundEngine.getIDFromString(self.allocator, SupportedAudioDeviceShareset[0]);
    return self.default_audio_device_shareset_id.?;
}

fn initSettingsChanged(self: *Self) void {
    _ = self;
}

fn indexOfChannelConfig(slice: []const AK.AkChannelConfig, value: AK.AkChannelConfig) ?usize {
    var i: usize = 0;
    while (i < slice.len) : (i += 1) {
        if (slice[i].toC() == value.toC()) {
            return i;
        }
    }
    return null;
}

fn getSpatialAudioSharesetId(self: *Self) !u32 {
    if (self.spatial_audio_shareset_id) |spatial_audio_shareset_id| {
        return spatial_audio_shareset_id;
    }

    self.spatial_audio_shareset_id = switch (AK.platform) {
        .windows, .xboxone, .xboxseries => try AK.SoundEngine.getIDFromString(self.allocator, "Microsoft_Spatial_Sound_Platform_Output"),
        .ps4, .ps5 => try AK.SoundEngine.getIDFromString(self.allocator, "SCE_Audio3d_Bed_Output"),
        else => 0,
    };
    return self.spatial_audio_shareset_id.?;
}

const SupportedAudioDeviceShareset: []const [:0]const u8 = switch (AK.platform) {
    else => &.{"System"},
};

const DefaultSpeakerConfigsName: []const [:0]const u8 = switch (AK.platform) {
    .windows => &.{ "Automatic", "Mono", "Stereo", "5.1", "7.1", "7.1.4" },
    .android => &.{ "Automatic", "Mono", "Stereo", "5.1" },
    .linux, .macos, .ios, .tvos => &.{ "Automatic", "Stereo", "5.1" },
    else => @compileError("Add default speaker config name for your platform"),
};

const DefaultSpeakerConfig: []const AK.AkChannelConfig = switch (AK.platform) {
    .windows => &.{
        AK.AkChannelConfig.standard(.{}),
        AK.AkChannelConfig.standard(AK.AkSpeakerSetup.Mono),
        AK.AkChannelConfig.standard(AK.AkSpeakerSetup.Stereo),
        AK.AkChannelConfig.standard(AK.AkSpeakerSetup.@"5.1"),
        AK.AkChannelConfig.standard(AK.AkSpeakerSetup.@"7.1"),
        AK.AkChannelConfig.standard(AK.AkSpeakerSetup.@"Dolby 7.1.4"),
    },
    .android => &.{
        AK.AkChannelConfig.standard(.{}),
        AK.AkChannelConfig.standard(AK.AkSpeakerSetup.Mono),
        AK.AkChannelConfig.standard(AK.AkSpeakerSetup.Stereo),
        AK.AkChannelConfig.standard(AK.AkSpeakerSetup.@"5.1"),
    },
    .linux, .macos, .ios, .tvos => &.{
        AK.AkChannelConfig.standard(.{}),
        AK.AkChannelConfig.standard(AK.AkSpeakerSetup.Stereo),
        AK.AkChannelConfig.standard(AK.AkSpeakerSetup.@"5.1"),
    },
    else => @compileError("Add default speaker config for your platform"),
};

comptime {
    std.debug.assert(DefaultSpeakerConfigsName.len == DefaultSpeakerConfig.len);
}