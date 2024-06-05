const std = @import("std");
const log = std.log;
const net = std.net;
const HttpResponse = @import("response.zig").HttpResponse;
const HttpRequest = @import("request.zig").HttpRequest;
const Router = @import("router.zig").Router;
const Content = @import("response.zig").HttpResponse.Content;

fn handleHome(_: HttpRequest) HttpResponse {
    return HttpResponse{ .Ok = .{ .content = null, .encoding = null } };
}

fn handleEcho(request: HttpRequest) HttpResponse {
    if (request.params) |params| {
        if (params.get("str")) |str_value| {
            const encoding = blk: {
                if (request.headers.get("Accept-Encoding")) |header_encoding| {
                    if (std.mem.containsAtLeast(u8, header_encoding, 1, "gzip")) {
                        break :blk "gzip";
                    }
                }
                break :blk null;
            };
            return HttpResponse{
                .Ok = .{
                    .content = Content{ .PlainText = str_value },
                    .encoding = if (encoding) |enc| enc[0..] else null,
                },
            };
        }
    }
    return HttpResponse.NotFound;
}

fn handleUserAgent(request: HttpRequest) HttpResponse {
    if (request.headers.get("User-Agent")) |user_agent| {
        return HttpResponse{
            .Ok = .{
                .content = Content{ .PlainText = user_agent },
                .encoding = null,
            },
        };
    }
    return HttpResponse.NotFound;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) @panic("Leaked memory");
    const allocator = gpa.allocator();

    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    log.info("listening on http://127.0.0.1:4221", .{});

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const directory = blk: {
        for (args[1..], 1..) |arg, i| {
            if (std.mem.eql(u8, arg, "--directory")) {
                if (i + 1 < args.len) {
                    break :blk args[i + 1];
                }
            }
        }
        break :blk null;
    };

    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    var router = Router.init(allocator, listener, directory);
    try router.get("/", handleHome);
    try router.get("/echo/{str}", handleEcho);
    try router.get("/user-agent", handleUserAgent);
    try router.run();
}
