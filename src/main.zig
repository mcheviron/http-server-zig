const std = @import("std");
const net = std.net;
const HttpResponse = @import("response.zig").HttpResponse;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("Logs from your program will appear here!\n", .{});

    const address = try net.Address.resolveIp("127.0.0.1", 4221);

    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    const connection = try listener.accept();
    try stdout.print("accepted new connection", .{});

    var response = HttpResponse.init(std.heap.page_allocator, .Ok, null);
    defer response.deinit();
    try response.send(connection.stream.writer());

    connection.stream.close();
}
