const AK = @import("wwise-zig");
const Cursor = @import("Cursor.zig");
const DemoInterface = @import("../DemoInterface.zig");
const root = @import("root");
const std = @import("std");
const zgui = @import("zgui");
const ID = @import("wwise-ids");

allocator: std.mem.Allocator = undefined,
is_visible: bool = false,
bank_id: AK.AkBankID = AK.AK_INVALID_BANK_ID,
multi_buffer: MultiBuffer = .{},
chip: Cursor = .{},
npcs: [MAX_NUM_OF_NPC]NPCInfo = @splat(.{}),
width: f32 = 0.0,
height: f32 = 0.0,
visible_npcs: u32 = INITIAL_NUM_OF_NPC,
is_first_update: bool = true,
random_provider: std.Random.DefaultPrng = undefined,

const CommandBufferCrowdDemo = @This();

const MAX_NUM_OF_NPC = 501;
const INITIAL_NUM_OF_NPC = 51;
const NPC_INCREASE = 25;
const BUFFER_SIZE = 36000;
const NUM_OF_BUFFER = 3;
const GAME_OBJECT_FIRST_ID = 10;
const POSITION_RANGE: f32 = 200.0;

const NPCInfo = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    speed: f32 = 0.0,
    id: u32 = 0,
    name: []const u8 = &.{},
    name_buffer: [32]u8 = undefined,
};

const MultiBuffer = struct {
    buffers: [NUM_OF_BUFFER]AK.CommandBuffer = @splat(.{}),
    is_buffer_available: [NUM_OF_BUFFER]std.atomic.Value(u32) = @splat(.{ .raw = 0 }),
    buffer_index: u32 = 0,
};

const SubmitCookie = struct {
    demo: *CommandBufferCrowdDemo,
    buffer_index: u32 = 0,
};

pub fn init(self: *CommandBufferCrowdDemo, allocator: std.mem.Allocator, demo_state: *root.WwiseDemoApp) !void {
    _ = demo_state;
    self.* = .{
        .allocator = allocator,
        .chip = .{
            .label = "<L>",
        },
    };

    // Init our MultiBuffer
    for (0..NUM_OF_BUFFER) |index| {
        self.multi_buffer.buffers[index] = try AK.CommandBuffer.create(BUFFER_SIZE);

        self.multi_buffer.is_buffer_available[index].store(1, .release);
    }
    self.multi_buffer.buffer_index = 0;

    // Load the sound bank
    self.bank_id = try AK.SoundEngine.loadBankString(allocator, "Command_Buffer_Demo.bnk", .{});

    self.random_provider = std.Random.DefaultPrng.init(@bitCast(std.time.timestamp()));
}

pub fn deinit(self: *CommandBufferCrowdDemo, demo_state: *root.WwiseDemoApp) void {
    _ = demo_state;

    self.allocator.destroy(self);
}

pub fn initGameObject(self: *CommandBufferCrowdDemo) !void {
    const buffer_size =
        // Add space for the header of the buffer and the AkCommand_EndOfBuffer located at the end of the buffer
        AK.CommandBuffer.minSize() +
        // Add space for the NPCs RegisterObject command
        (MAX_NUM_OF_NPC * AK.CommandBuffer.cmdSizeType(AK.AkCmd_RegisterGameObject)) +
        // Add space for the NPCs Name
        (MAX_NUM_OF_NPC * @sizeOf(u8) * 32) +
        // Add space for the NPCs PostEvent command
        (MAX_NUM_OF_NPC + AK.CommandBuffer.cmdSizeType(AK.AkCmd_PostEvent)) +
        // Add space for all the NPCs SetPosition command
        (MAX_NUM_OF_NPC + AK.CommandBuffer.cmdSizeType(AK.AkCmd_SetPosition)) +
        // Add space for the listener SetPosition command
        (1 * AK.CommandBuffer.cmdSizeType(AK.AkCmd_SetPosition));

    var init_buffer = try AK.CommandBuffer.create(buffer_size);

    const random = self.random_provider.random();

    // Init every potential NPC in advance to avoid doing it at runtime when new game objects are registered
    for (0..MAX_NUM_OF_NPC) |index| {
        self.npcs[index].id = @truncate(index);
        self.npcs[index].name = try std.fmt.bufPrint(&self.npcs[index].name_buffer, "NPC_{}", .{GAME_OBJECT_FIRST_ID + index});

        const random_number_x = random.float(f32) * self.width;
        const random_number_y = random.float(f32) * self.height;

        self.npcs[index].x = if (index >= self.visible_npcs) random_number_x else random_number_x - (self.width + 50.0);
        self.npcs[index].y = random_number_y;

        self.npcs[index].speed = if (random.float(f32) < 0.02) 8 else 5;
    }

    // register only half the NPCs to the Sound Engine
    for (0..INITIAL_NUM_OF_NPC) |index| {
        try self.registerGameObject(init_buffer, &self.npcs[index]);
    }

    // Set Listener initial position
    const set_position_cmd = try init_buffer.add(AK.AkCmd_SetPosition);
    set_position_cmd.game_object_id = root.LISTENER_GAME_OBJECT_ID;
    set_position_cmd.flags = .default;
    set_position_cmd.position.position = .{ .x = self.width / 2.0, .y = self.height / 2.0, .z = 0.0 };
    set_position_cmd.position.orientation_front = .{ .x = 0, .y = 0, .z = 1 };
    set_position_cmd.position.orientation_top = .{ .x = 0, .y = 1, .z = 0 };

    submitInitAndReleaseCommandBuffer(init_buffer);
}

pub fn releaseAll(self: *CommandBufferCrowdDemo) !void {
    const buffer_size =
        // Add space for the header of the buffer and the AkCommand_EndOfBuffer located at the end of the buffer
        AK.CommandBuffer.minSize() +
        // Add space for the NPCs StopAll command
        (MAX_NUM_OF_NPC * AK.CommandBuffer.cmdSizeType(AK.AkCmd_StopAll)) +
        //  Add space for the NPCs UnregisterGameObject command
        (MAX_NUM_OF_NPC + AK.CommandBuffer.cmdSizeType(AK.AkCmd_UnregisterGameObject)) +
        // Add space for the listener SetPosition command
        (1 * AK.CommandBuffer.cmdSizeType(AK.AkCmd_SetPosition));

    const release_buffer = try AK.CommandBuffer.create(buffer_size);

    const set_position_cmd = try release_buffer.add(AK.AkCmd_SetPosition);
    set_position_cmd.game_object_id = root.LISTENER_GAME_OBJECT_ID;
    set_position_cmd.flags = .default;
    set_position_cmd.position.position = .{ .x = 0, .y = 0, .z = 0 };
    set_position_cmd.position.orientation_front = .{ .x = 0, .y = 0, .z = 1 };
    set_position_cmd.position.orientation_top = .{ .x = 0, .y = 1, .z = 0 };

    for (0..self.visible_npcs) |index| {
        try unregisterGameObject(release_buffer, self.npcs[index].id);
    }

    submitInitAndReleaseCommandBuffer(release_buffer);

    // Stall until all buffers are available
    var can_break = false;
    while (!can_break) {
        try AK.SoundEngine.renderAudio(true);

        can_break = true;
        for (0..NUM_OF_BUFFER) |index| {
            if (self.multi_buffer.is_buffer_available[index].load(.acquire) == 0) {
                can_break = false;
                std.Thread.sleep(10);
                break;
            }
        }
    }

    // Destroy all our buffers
    for (0..NUM_OF_BUFFER) |index| {
        self.multi_buffer.buffers[index].destroy();
    }

    try AK.SoundEngine.unloadBankID(self.bank_id, null, .{});
}

pub fn onUI(self: *CommandBufferCrowdDemo, demo_state: *root.WwiseDemoApp) !void {
    _ = demo_state;

    zgui.setNextWindowSize(.{
        .w = 640,
        .h = 480,
        .cond = .first_use_ever,
    });

    if (zgui.begin("Command Buffer with multiple commands)", .{ .popen = &self.is_visible, .flags = .{} })) {
        if (zgui.button("Add NPC", .{})) {
            if (self.getAvailableBuffer()) |available_buffer| {
                try self.addNPC(available_buffer);
                try self.submitCommandBuffer(available_buffer);
            }
        }

        zgui.sameLine(.{});
        if (zgui.button("Remove NPC", .{})) {
            if (self.getAvailableBuffer()) |available_buffer| {
                try self.removeNPC(available_buffer);
                try self.submitCommandBuffer(available_buffer);
            }
        }

        zgui.text("Game Objects: {}", .{self.visible_npcs});

        const window_size = zgui.getContentRegionAvail();

        if (self.is_first_update) {
            self.width = window_size[0] - Cursor.MARGIN;
            self.height = window_size[1] - Cursor.MARGIN;

            try self.initGameObject();

            self.is_first_update = false;
        }

        self.chip.update();

        if (self.getAvailableBuffer()) |available_buffer| {
            try self.updateGameObjPos(available_buffer);
            try self.submitCommandBuffer(available_buffer);
        }

        var draw_list = zgui.getWindowDrawList();

        const white_color = zgui.colorConvertFloat4ToU32([4]f32{ 1.0, 1.0, 1.0, 1.0 });

        const yellow_color = zgui.colorConvertFloat4ToU32([4]f32{ 1.0, 1.0, 0.0, 1.0 });

        const window_pos = zgui.getCursorScreenPos();

        draw_list.addRect(.{
            .pmin = window_pos,
            .pmax = [2]f32{ window_pos[0] + window_size[0] - Cursor.MARGIN, window_pos[1] + window_size[1] - Cursor.MARGIN },
            .col = white_color,
        });

        for (0..self.visible_npcs) |index| {
            draw_list.addCircle(.{
                .p = .{ window_pos[0] + self.npcs[index].x, window_pos[1] + self.npcs[index].y },
                .r = 3.0,
                .col = yellow_color,
            });
        }

        self.chip.draw(draw_list);

        zgui.end();
    }

    if (!self.is_visible) {
        try self.releaseAll();
    }
}

pub fn isVisible(self: *CommandBufferCrowdDemo) bool {
    return self.is_visible;
}

pub fn show(self: *CommandBufferCrowdDemo) void {
    self.is_visible = true;
}

pub fn demoInterface(self: *CommandBufferCrowdDemo) DemoInterface {
    return DemoInterface.toDemoInteface(self);
}

fn pixelsToAkPosX(self: CommandBufferCrowdDemo, in_x: f32) f32 {
    return ((in_x / self.width) - 0.5) * POSITION_RANGE;
}

fn pixelsToAkPosY(self: CommandBufferCrowdDemo, in_y: f32) f32 {
    return -((in_y / self.height) - 0.5) * POSITION_RANGE;
}

fn registerGameObject(self: *CommandBufferCrowdDemo, out_buffer: AK.CommandBuffer, in_npc: *const NPCInfo) !void {
    const register_game_object_cmd = try out_buffer.add(AK.AkCmd_RegisterGameObject);
    register_game_object_cmd.game_object_id = in_npc.id;
    _ = try out_buffer.addString(self.allocator, in_npc.name);

    const set_position_cmd = try out_buffer.add(AK.AkCmd_SetPosition);
    set_position_cmd.game_object_id = in_npc.id;
    set_position_cmd.flags = .default;
    set_position_cmd.position.position = .{
        .y = 0,
        .x = self.pixelsToAkPosX(in_npc.x),
        .z = self.pixelsToAkPosY(in_npc.y),
    };
    set_position_cmd.position.orientation_front = .{ .x = 0, .y = 0, .z = 1 };
    set_position_cmd.position.orientation_top = .{ .x = 0, .y = 1, .z = 0 };

    const post_event_cmd = try out_buffer.add(AK.AkCmd_PostEvent);
    post_event_cmd.event_id = ID.EVENTS.PLAY_COMMAND_BUFFER_DEMO;
    post_event_cmd.playing_id = AK.SoundEngine.generatePlayingID();
    post_event_cmd.game_object_id = in_npc.id;
}

fn unregisterGameObject(out_buffer: AK.CommandBuffer, id: u32) !void {
    const stop_all_cmd = try out_buffer.add(AK.AkCmd_StopAll);
    stop_all_cmd.game_object_id = id;

    const unregister_game_object_cmd = try out_buffer.add(AK.AkCmd_UnregisterGameObject);
    unregister_game_object_cmd.game_object_id = id;
}

fn submitInitAndReleaseCommandBuffer(io_buffer: AK.CommandBuffer) void {
    io_buffer.header.completion_callback = onInitAndReleaseCommandBufferDone;
    io_buffer.header.completion_callback_cookie = io_buffer.header;

    io_buffer.submit();
}

fn onInitAndReleaseCommandBufferDone(io_cookie: ?*anyopaque) callconv(.c) void {
    var command_buffer: AK.CommandBuffer = .{
        .header = @ptrCast(@alignCast(io_cookie)),
    };

    var it: AK.AkCommandBufferIterator = command_buffer.begin();
    while (it.next()) {
        if (it.header.result != .success) {
            std.log.debug("Command with code {} failed: Result = {}", .{ it.header.code, it.header.result });
        }
    }

    command_buffer.destroy();
}

fn getAvailableBuffer(self: *CommandBufferCrowdDemo) ?AK.CommandBuffer {
    var are_all_buffer_used = true;

    while (are_all_buffer_used) {
        for (0..NUM_OF_BUFFER) |index| {
            if (self.multi_buffer.is_buffer_available[index].load(.acquire) > 0) {
                self.multi_buffer.buffer_index = @truncate(index);
                are_all_buffer_used = false;

                return self.multi_buffer.buffers[index];
            }
        }

        std.Thread.sleep(10);
    }

    return null;
}

fn updateGameObjPos(self: *CommandBufferCrowdDemo, out_buffer: AK.CommandBuffer) !void {
    // Update listener position
    // Converting X-Y UI into X-Z world plan.
    const listener_set_position_cmd = try out_buffer.add(AK.AkCmd_SetPosition);
    listener_set_position_cmd.game_object_id = root.LISTENER_GAME_OBJECT_ID;
    listener_set_position_cmd.flags = .default;
    listener_set_position_cmd.position.position = .{
        .x = self.pixelsToAkPosX(self.chip.x),
        .y = 0.0,
        .z = self.pixelsToAkPosY(self.chip.y),
    };
    listener_set_position_cmd.position.orientation_front = .{ .x = 0, .y = 0, .z = 1 };
    listener_set_position_cmd.position.orientation_top = .{ .x = 0, .y = 1, .z = 0 };

    // Update NPC position
    var npc_position: AK.AkVector64 = .{};
    npc_position.y = 0.0;

    for (0..self.visible_npcs) |index| {
        self.moveNpc(&self.npcs[index]);

        // Converting X-Y UI into X-Z world plan.
        npc_position.x = self.pixelsToAkPosX(self.npcs[index].x);
        npc_position.z = self.pixelsToAkPosY(self.npcs[index].y);

        const npc_set_position_cmd = try out_buffer.add(AK.AkCmd_SetPosition);
        npc_set_position_cmd.game_object_id = self.npcs[index].id;
        npc_set_position_cmd.flags = .default;
        npc_set_position_cmd.position.position = npc_position;
        npc_set_position_cmd.position.orientation_front = .{ .x = 0, .y = 0, .z = 1 };
        npc_set_position_cmd.position.orientation_top = .{ .x = 0, .y = 1, .z = 0 };
    }
}

fn moveNpc(self: *CommandBufferCrowdDemo, npc: *NPCInfo) void {
    const random = self.random_provider.random();

    // Move npc to other side of the screen at a random position when it exits from the right
    if (npc.x > self.width + 10) {
        npc.x = -10;
        npc.y = random.float(f32) * (self.height - 220) + 90.0;
    }

    const random_number_x = random.float(f32) * 3;
    const random_number_y = random.float(f32);

    if ((npc.y + random_number_y) < 100) {
        npc.y += 5;
    }
    if ((npc.y + random_number_y) > self.height - 140) {
        npc.y -= 5;
    }

    const dx_to_player = npc.x - self.chip.x;
    const dy_to_player = npc.y - self.chip.y;
    const distance_to_player = @sqrt(dx_to_player * dx_to_player + dy_to_player * dy_to_player);

    // Make the NPC move away from the player within a certain radius
    if (distance_to_player < 40) {
        npc.y += (dy_to_player / (distance_to_player / npc.speed));
    }

    npc.x += random_number_x + npc.speed;
    npc.y += random_number_y;
}

fn submitCommandBuffer(self: *CommandBufferCrowdDemo, io_buffer: AK.CommandBuffer) !void {
    self.multi_buffer.is_buffer_available[self.multi_buffer.buffer_index].store(0, .release);

    const submit_cookie = try self.allocator.create(SubmitCookie);
    submit_cookie.* = .{
        .demo = self,
        .buffer_index = self.multi_buffer.buffer_index,
    };

    io_buffer.header.completion_callback = onCommandBufferDone;
    io_buffer.header.completion_callback_cookie = submit_cookie;
    io_buffer.submit();
}

fn onCommandBufferDone(in_cookie: ?*anyopaque) callconv(.c) void {
    const submit_cookie: *SubmitCookie = @ptrCast(@alignCast(in_cookie));

    const self = submit_cookie.demo;

    // Reset the buffer and make it available for reuse
    self.multi_buffer.buffers[submit_cookie.buffer_index].reset(BUFFER_SIZE) catch return;
    self.multi_buffer.is_buffer_available[submit_cookie.buffer_index].store(1, .release);

    self.allocator.destroy(submit_cookie);
}

fn addNPC(self: *CommandBufferCrowdDemo, out_buffer: AK.CommandBuffer) !void {
    if (self.visible_npcs + NPC_INCREASE <= MAX_NUM_OF_NPC) {
        for (0..NPC_INCREASE) |_| {
            try self.registerGameObject(out_buffer, &self.npcs[self.visible_npcs]);

            self.visible_npcs += 1;
        }
    }
}

fn removeNPC(self: *CommandBufferCrowdDemo, out_buffer: AK.CommandBuffer) !void {
    if (self.visible_npcs - NPC_INCREASE >= 0) {
        for (0..NPC_INCREASE) |_| {
            self.visible_npcs -= 1;
            try unregisterGameObject(out_buffer, self.npcs[self.visible_npcs].id);
        }
    }
}
