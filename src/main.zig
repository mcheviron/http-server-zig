const std = @import("std");
const log = std.log;
const net = std.net;
const HttpResponse = @import("response.zig").HttpResponse;
const HttpRequest = @import("request.zig").HttpRequest;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) @panic("Leaked memory");
    const allocator = gpa.allocator();

    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    log.info("listening on http://127.0.0.1:4221", .{});

    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    const connection = try listener.accept();
    log.info("accepted new connection", .{});

    const writer = connection.stream.writer();
    const reader = connection.stream.reader();
    var buffer: [1024]u8 = undefined;

    const bytes_read = try reader.read(&buffer);
    var request = try HttpRequest.init(allocator, buffer[0..bytes_read]);
    defer request.deinit();

    const response = if (std.mem.eql(u8, request.resource, "/")) HttpResponse{ .Ok = null } else HttpResponse.NotFound;
    @memset(&buffer, 0);
    const response_bytes = try response.bytes(&buffer);
    try writer.writeAll(response_bytes);

    connection.stream.close();
}
