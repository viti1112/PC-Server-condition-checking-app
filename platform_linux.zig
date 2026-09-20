const std = @import("std");

pub const CpuTicks = struct {
    idle: u64,
    total: u64,
};

pub fn readUptime(io: std.Io, allocator: std.mem.Allocator) !f64 {
    const file = try std.Io.Dir.openFileAbsolute(io, "/proc/uptime", .{});
    defer file.close(io);

    var file_buffer: [1024]u8 = undefined;
    var reader = file.readerStreaming(io, &file_buffer);
    const contents = try reader.interface.allocRemaining(allocator, .unlimited);
    defer allocator.free(contents);

    var fields = std.mem.tokenizeScalar(u8, contents, ' ');
    const uptime_str = fields.next() orelse return error.ParseFailed;
    return std.fmt.parseFloat(f64, uptime_str);
}

pub fn readMemAvailableKb(io: std.Io, allocator: std.mem.Allocator) !u64 {
    const file = try std.Io.Dir.openFileAbsolute(io, "/proc/meminfo", .{});
    defer file.close(io);

    var file_buffer: [4096]u8 = undefined;
    var reader = file.readerStreaming(io, &file_buffer);
    const contents = try reader.interface.allocRemaining(allocator, .unlimited);
    defer allocator.free(contents);

    var lines = std.mem.tokenizeScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "MemAvailable:")) {
            var fields = std.mem.tokenizeScalar(u8, line, ' ');
            _ = fields.next(); // skip "MemAvailable:"
            const value_str = fields.next() orelse return error.ParseFailed;
            return std.fmt.parseInt(u64, value_str, 10);
        }
    }
    return error.ParseFailed;
}

pub fn readCpuTicks(io: std.Io, allocator: std.mem.Allocator) !CpuTicks {
    const file = try std.Io.Dir.openFileAbsolute(io, "/proc/stat", .{});
    defer file.close(io);

    var file_buffer: [1024]u8 = undefined;
    var reader = file.readerStreaming(io, &file_buffer);
    const contents = try reader.interface.allocRemaining(allocator, .unlimited);
    defer allocator.free(contents);

    var lines = std.mem.tokenizeScalar(u8, contents, '\n');
    const cpu_line = lines.next() orelse return error.ParseFailed;

    var fields = std.mem.tokenizeScalar(u8, cpu_line, ' ');
    _ = fields.next();

    var total: u64 = 0;
    var idle: u64 = 0;
    var field_index: u8 = 0;
    while (fields.next()) |field_str| {
        const value = try std.fmt.parseInt(u64, field_str, 10);
        total += value;
        if (field_index == 3) idle = value;
        field_index += 1;
    }

    return CpuTicks{ .idle = idle, .total = total };
}
