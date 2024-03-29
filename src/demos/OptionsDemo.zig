const std = @import("std");
const DemoInterface = @import("../DemoInterface.zig");
const zgui = @import("zgui");
const root = @import("root");
const AK = @import("wwise-zig");
const builtin = @import("builtin");

allocator: std.mem.Allocator = undefined,
string_area: std.heap.ArenaAllocator = undefined,
string_area_allocator: std.mem.Allocator = undefined,
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
num_job_workers: u32 = 0,
memory_settings: MemorySettings = .{},
init_settings: InitSettings = .{},
platform_settings: PlatformSettings = .{},

const Self = @This();

const DeviceId = struct {
    shareset_id: u32 = 0,
    device_id: u32 = 0,
};

pub fn init(self: *Self, allocator: std.mem.Allocator, demo_state: *root.DemoState) !void {
    self.* = .{
        .allocator = allocator,
        .string_area = std.heap.ArenaAllocator.init(allocator),
    };

    self.string_area_allocator = self.string_area.allocator();

    try self.populateOutputDeviceOptions();

    self.active_panning_rule = try AK.SoundEngine.getPanningRule(0);
    self.active_channel_config = AK.SoundEngine.getSpeakerConfiguration(0);
    self.active_channel_index = indexOfChannelConfig(DefaultSpeakerConfig, self.active_channel_config) orelse 0;

    try self.memory_settings.init(&demo_state.wwise_context.memory_settings);
    try self.init_settings.init(&demo_state.wwise_context.init_settings);
    try self.platform_settings.init(&demo_state.wwise_context.platform_init_settings);

    if (AK.JobWorkerMgr != void) {
        self.num_job_workers = @intCast(demo_state.wwise_context.init_settings.settings_job_manager.max_active_workers[AK.AkJobType_AudioProcessing]);
    }
}

pub fn deinit(self: *Self, demo_state: *root.DemoState) void {
    _ = demo_state;

    self.string_area.deinit();

    self.device_ids.deinit(self.allocator);
    self.device_names.deinit(self.allocator);

    self.allocator.destroy(self);
}

pub fn onUI(self: *Self, demo_state: *root.DemoState) !void {
    if (zgui.begin("Options", .{ .popen = &self.is_visible, .flags = .{ .always_auto_resize = true } })) {
        if (zgui.beginCombo("Device", .{ .preview_value = self.device_names.items[self.active_device_index] })) {
            for (self.device_names.items, 0..) |device_name, index| {
                const is_selected = self.active_device_index == index;

                if (zgui.selectable(device_name, .{ .selected = is_selected })) {
                    self.active_device_index = index;
                    try self.updateSpeakerConfigForShareset();
                    try self.updateOutputDevice(demo_state);
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
                    try self.updateOutputDevice(demo_state);
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
                    try self.updateOutputDevice(demo_state);
                }

                if (is_selected) {
                    zgui.setItemDefaultFocus();
                }
            }

            zgui.endCombo();
        }

        try self.init_settings.onUI(self, demo_state, initSettingsChanged);

        if (AK.JobWorkerMgr != void) {
            if (zgui.sliderScalar("Job Workers", u32, .{ .v = &self.num_job_workers, .min = 0, .max = 8 })) {
                if (demo_state.wwise_context.job_worker_settings.num_worker_threads > 0 and self.num_job_workers > 0) {
                    for (0..AK.AK_NUM_JOB_TYPES) |index| {
                        demo_state.wwise_context.init_settings.settings_job_manager.max_active_workers[index] = self.num_job_workers;
                        try AK.SoundEngine.setJobMgrMaxActiveWorkers(@truncate(index), self.num_job_workers);
                    }
                } else {
                    try self.initSettingsChanged(demo_state);
                }
            }
        }

        try self.memory_settings.onUI(self, demo_state, initSettingsChanged);
        try self.platform_settings.onUI(self, demo_state, initSettingsChanged);

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
    try self.device_names.append(self.allocator, try self.string_area_allocator.dupeZ(u8, "Use Default"));

    if (AK.SoundEngine.isInitialized()) {
        const init_settings = blk: {
            if (AK.SoundEngine.getGlobalPluginContext()) |plugin_context| {
                if (try plugin_context.getInitSettings(self.allocator)) |init_settings| {
                    break :blk init_settings;
                }
            }

            return error.NoValidInitSettings;
        };
        defer init_settings.deinit(self.allocator);

        const id_current = AK.SoundEngine.getOutputID(0, 0);

        for (SupportedAudioDeviceShareset) |shareset_name| {
            const shareset_id = try AK.SoundEngine.getIDFromString(self.allocator, shareset_name);

            var device_count: u32 = 0;
            AK.SoundEngine.getDeviceListShareSet(self.allocator, shareset_id, &device_count, null) catch {};
            if (device_count == 0) {
                const name = try std.fmt.allocPrintZ(self.string_area_allocator, "{s} - Primary  Output", .{shareset_name});
                try self.device_ids.append(self.allocator, DeviceId{ .shareset_id = shareset_id });
                try self.device_names.append(self.allocator, name);
            } else {
                const devices = try self.allocator.alloc(AK.AkDeviceDescription, device_count);
                defer {
                    for (devices) |device| {
                        device.deinit(self.allocator);
                    }
                    self.allocator.free(devices);
                }

                try AK.SoundEngine.getDeviceListShareSet(self.allocator, shareset_id, &device_count, @ptrCast(devices));

                var real_count: u32 = 0;
                for (devices) |device| {
                    if (device.device_state_mask.active) {
                        const name = try std.fmt.allocPrintZ(self.string_area_allocator, "{s} - {s}", .{ shareset_name, device.device_name });
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

fn updateOutputDevice(self: *Self, demo_state: *root.DemoState) !void {
    if (!AK.SoundEngine.isInitialized()) {
        try self.initSettingsChanged(demo_state);
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

fn initSettingsChanged(self: *Self, demo_state: *root.DemoState) !void {
    try root.destroyWwise(self.allocator, demo_state);

    const memory_settings = &demo_state.wwise_context.memory_settings;
    const init_settings = &demo_state.wwise_context.init_settings;
    const platform_init_settings = &demo_state.wwise_context.platform_init_settings;

    try self.fillOutputSetting(&init_settings.settings_main_output);

    try self.memory_settings.fillSettings(memory_settings);
    try self.init_settings.fillSettings(init_settings);
    try self.platform_settings.fillSettings(platform_init_settings);

    if (AK.JobWorkerMgr != void) {
        const job_worker_mgr_settings = &demo_state.wwise_context.job_worker_settings;
        job_worker_mgr_settings.num_worker_threads = if (self.num_job_workers > 0) root.MaxThreadWorkers else 0;

        var job_mgr_settings = job_worker_mgr_settings.getJobMgrSettings();
        for (0..AK.AK_NUM_JOB_TYPES) |index| {
            job_mgr_settings.max_active_workers[index] = self.num_job_workers;
        }

        init_settings.settings_job_manager = job_mgr_settings;
    }

    try root.initWwise(self.allocator, demo_state);
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

fn NamedValue(comptime ValueType: type) type {
    return struct {
        name: [:0]const u8,
        value: ValueType,
    };
}

fn indexOfNamedValue(value: anytype, list: []const NamedValue(@TypeOf(value))) ?usize {
    for (0..list.len) |index| {
        if (list[index].value == value) {
            return index;
        }
    }

    return null;
}

fn NamedValueInstance(comptime value_list: anytype) type {
    return struct {
        selected_index: usize = 0,

        pub const NamedValues = value_list;
    };
}

fn SettingsInterface(comptime WrapperType: type, comptime SettingsType: type) type {
    return struct {
        pub fn init(self: *WrapperType, settings: *SettingsType) !void {
            inline for (std.meta.fields(WrapperType)) |field| {
                switch (@typeInfo(field.type)) {
                    .Bool,
                    .Int,
                    .ComptimeFloat,
                    .ComptimeInt,
                    .Float,
                    => {
                        @field(self, field.name) = @field(settings, field.name);
                    },
                    .Struct => {
                        @field(self, field.name).selected_index = indexOfNamedValue(@field(settings, field.name), @field(field.type, "NamedValues")) orelse 0;
                    },
                    else => @compileError("Not supported"),
                }
            }
        }

        pub fn onUI(self: *WrapperType, demo: *Self, demo_state: *root.DemoState, callback: *const fn (self: *Self, demo_state: *root.DemoState) anyerror!void) !void {
            inline for (std.meta.fields(WrapperType)) |field| {
                switch (@typeInfo(field.type)) {
                    .Bool => {
                        if (zgui.checkbox(@field(WrapperType.DisplayNames, field.name), .{ .v = &@field(self, field.name) })) {
                            try callback(demo, demo_state);
                        }
                    },
                    .Int,
                    .ComptimeFloat,
                    .ComptimeInt,
                    .Float,
                    => {
                        if (zgui.sliderScalar(@field(WrapperType.DisplayNames, field.name), field.type, .{ .v = &@field(self, field.name) })) {
                            try callback(demo, demo_state);
                        }
                    },
                    .Struct => {
                        const NamedValues = @field(field.type, "NamedValues");

                        if (zgui.beginCombo(@field(WrapperType.DisplayNames, field.name), .{ .preview_value = NamedValues[@field(self, field.name).selected_index].name })) {
                            for (0..NamedValues.len) |index| {
                                const is_selected = @field(self, field.name).selected_index == index;

                                if (zgui.selectable(NamedValues[index].name, .{ .selected = is_selected })) {
                                    @field(self, field.name).selected_index = index;
                                    try callback(demo, demo_state);
                                }

                                if (is_selected) {
                                    zgui.setItemDefaultFocus();
                                }
                            }

                            zgui.endCombo();
                        }
                    },
                    else => @compileError("Not supported"),
                }
            }
        }

        pub fn fillSettings(self: *WrapperType, settings: *SettingsType) !void {
            inline for (std.meta.fields(WrapperType)) |field| {
                switch (@typeInfo(field.type)) {
                    .Bool,
                    .Int,
                    .ComptimeFloat,
                    .ComptimeInt,
                    .Float,
                    => {
                        @field(settings, field.name) = @field(self, field.name);
                    },
                    .Struct => {
                        @field(settings, field.name) = @field(field.type, "NamedValues")[@field(self, field.name).selected_index].value;
                    },
                    else => @compileError("Not supported"),
                }
            }
        }
    };
}

const InitSettings = struct {
    num_samples_per_frame: NamedValueInstance(FrameSizes) = .{},
    debug_out_of_range_limit: NamedValueInstance(RangeChecks) = .{},
    debug_out_of_range_check_enabled: bool = false,

    pub const DisplayNames = .{
        .num_samples_per_frame = "Frame Size",
        .debug_out_of_range_limit = "Range Check Limit",
        .debug_out_of_range_check_enabled = "Range Check",
    };

    pub const FrameSizes: []const NamedValue(u32) = &.{
        .{ .name = "128", .value = 128 },
        .{ .name = "256", .value = 256 },
        .{ .name = "512", .value = 512 },
        .{ .name = "1024", .value = 1024 },
        .{ .name = "2048", .value = 2048 },
    };

    pub const RangeChecks: []const NamedValue(f32) = &.{
        .{ .name = "+6dB", .value = 2.0 },
        .{ .name = "+12dB", .value = 4.0 },
        .{ .name = "+24dB", .value = 16.0 },
        .{ .name = "+48dB", .value = 256.0 },
    };

    pub usingnamespace SettingsInterface(InitSettings, AK.AkInitSettings);
};

const MemorySettings = struct {
    mem_allocation_size_limit: NamedValueInstance(MemoryLimits) = .{},
    memory_debug_level: NamedValueInstance(MemoryDebugLevels) = .{},

    pub const DisplayNames = .{
        .mem_allocation_size_limit = "Memory Limit",
        .memory_debug_level = "Memory Debug Option",
    };

    pub const MemoryLimits: []const NamedValue(u64) = &.{
        .{ .name = "Disabled", .value = 0 },
        .{ .name = "32 MB", .value = 32 * 1024 * 1024 },
        .{ .name = "64 MB", .value = 64 * 1024 * 1024 },
        .{ .name = "128 MB", .value = 128 * 1024 * 1024 },
    };

    pub const MemoryDebugLevels: []const NamedValue(u32) = &.{
        .{ .name = "Disabled", .value = 0 },
        .{ .name = "Leaks", .value = 1 },
        .{ .name = "Stomp Allocator", .value = 2 },
        .{ .name = "Stomp Allocator and Leaks", .value = 3 },
    };

    pub usingnamespace SettingsInterface(MemorySettings, AK.AkMemSettings);
};

const RefillBuffers: []const NamedValue(u16) = &.{
    .{ .name = "2", .value = 2 },
    .{ .name = "3", .value = 3 },
    .{ .name = "4", .value = 4 },
    .{ .name = "8", .value = 8 },
    .{ .name = "16", .value = 16 },
    .{ .name = "32", .value = 32 },
};
const RefillBuffersDisplayName = "Refill Buffers";

pub const SampleRates: []const NamedValue(u32) = &.{
    .{ .name = "24000", .value = 24000 },
    .{ .name = "32000", .value = 32000 },
    .{ .name = "44100", .value = 44100 },
    .{ .name = "48000", .value = 48000 },
};
const SampleRateDisplayName = "Sample Rate";

const PlatformSettings = switch (AK.platform) {
    .windows => WindowsPlatformSettings,
    .linux => LinuxPlatformSettings,
    .macos => MacPlatformSettings,
    .android => AndroidPlatformSettings,
    .ios, .tvos => iOSPlatformSettings,
    else => @compileError("Add Platform Settings mapping for your platform"),
};

const WindowsPlatformSettings = struct {
    num_refills_in_voice: NamedValueInstance(RefillBuffers) = .{},
    sample_rate: NamedValueInstance(SampleRates) = .{},
    enable_avx_support: bool = false,
    max_system_audio_objects: NamedValueInstance(MaxSystemAudioObjects) = .{},

    pub const DisplayNames = .{
        .num_refills_in_voice = RefillBuffersDisplayName,
        .sample_rate = SampleRateDisplayName,
        .enable_avx_support = "Use AVX",
        .max_system_audio_objects = "Max System Audio Objects",
    };

    pub const MaxSystemAudioObjects: []const NamedValue(u32) = &.{
        .{ .name = "0", .value = 0 },
        .{ .name = "5", .value = 0 },
        .{ .name = "30", .value = 0 },
    };

    pub usingnamespace SettingsInterface(WindowsPlatformSettings, AK.AkPlatformInitSettings);
};

const LinuxPlatformSettings = struct {
    num_refills_in_voice: NamedValueInstance(RefillBuffers) = .{},
    sample_rate: NamedValueInstance(SampleRates) = .{},
    sample_type: NamedValueInstance(SampleFormats) = .{},
    audio_api: NamedValueInstance(AudioAPIs),

    pub const DisplayNames = .{
        .num_refills_in_voice = RefillBuffersDisplayName,
        .sample_rate = SampleRateDisplayName,
        .sample_type = "Sample Format",
        .audio_api = "Audio API",
    };

    pub const SampleFormats: []const NamedValue(AK.AkDataTypeID) = &.{
        .{ .name = "16-bit signed integer", .value = AK.AK_INT },
        .{ .name = "32-bit floating point", .value = AK.AK_FLOAT },
    };

    pub const AudioAPIs: []const NamedValue(AK.AkAudioAPILinux) = &.{
        .{ .name = "Automatic", .value = AK.AkAudioAPILinux.Default },
        .{ .name = "PulseAudio", .value = AK.AkAudioAPILinux{ .pulse_audio = true } },
        .{ .name = "ALSA", .value = AK.AkAudioAPILinux{ .alsa = true } },
    };

    pub usingnamespace SettingsInterface(LinuxPlatformSettings, AK.AkPlatformInitSettings);
};

const MacPlatformSettings = struct {
    num_refills_in_voice: NamedValueInstance(RefillBuffers) = .{},
    sample_rate: NamedValueInstance(SampleRates) = .{},

    pub const DisplayNames = .{
        .num_refills_in_voice = RefillBuffersDisplayName,
        .sample_rate = SampleRateDisplayName,
    };

    pub usingnamespace SettingsInterface(MacPlatformSettings, AK.AkPlatformInitSettings);
};

const iOSPlatformSettings = struct {
    num_refills_in_voice: NamedValueInstance(RefillBuffers) = .{},
    sample_rate: NamedValueInstance(SampleRates) = .{},
    verbose_system_output: bool = false,

    pub const DisplayNames = .{
        .num_refills_in_voice = RefillBuffersDisplayName,
        .sample_rate = SampleRateDisplayName,
        .verbose_system_output = "Verbose Debug Output",
    };

    pub usingnamespace SettingsInterface(iOSPlatformSettings, AK.AkPlatformInitSettings);
};

const AndroidPlatformSettings = struct {
    num_refills_in_voice: NamedValueInstance(RefillBuffers) = .{},
    sample_rate: NamedValueInstance(SampleRates) = .{},
    audio_api: NamedValueInstance(AudioAPIs) = .{},
    round_frame_size_to_hw_size: bool = false,
    verbose_sink: bool = false,
    enable_low_latency: bool = false,

    pub const DisplayNames = .{
        .num_refills_in_voice = RefillBuffersDisplayName,
        .sample_rate = SampleRateDisplayName,
        .audio_api = "Audio API",
        .round_frame_size_to_hw_size = "Round Frame To HW Size",
        .verbose_sink = "Verbose Debug Logcat",
        .enable_low_latency = "Use Low Latency Mode",
    };

    pub const AudioAPIs: []const NamedValue(AK.AkAudioAPIAndroid) = &.{
        .{ .name = "Automatic", .value = AK.AkAudioAPIAndroid.Default },
        .{ .name = "AAudio", .value = AK.AkAudioAPIAndroid{ .aaudio = true } },
        .{ .name = "OpenSL ES", .value = AK.AkAudioAPIAndroid{ .opensl_es = true } },
    };

    pub usingnamespace SettingsInterface(AndroidPlatformSettings, AK.AkPlatformInitSettings);
};
