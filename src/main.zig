const std = @import("std");
const log = std.log;
const net = std.net;
const HttpResponse = @import("response.zig").HttpResponse;
const HttpRequest = @import("request.zig").HttpRequest;
const Router = @import("router.zig").Router;
const ContentType = @import("response.zig").ContentType;

fn handleHome(_: HttpRequest) HttpResponse {
    return HttpResponse{ .Ok = ContentType{ .PlainText = "" } };
}

fn handleEcho(request: HttpRequest) HttpResponse {
    if (request.params) |params| {
        if (params.get("str")) |str_value| {
            return HttpResponse{ .Ok = ContentType{ .PlainText = str_value } };
        }
    }
    return HttpResponse.NotFound;
}

fn handleUserAgent(request: HttpRequest) HttpResponse {
    if (request.headers.get("User-Agent")) |user_agent| {
        return HttpResponse{ .Ok = ContentType{ .PlainText = user_agent } };
    }
    return HttpResponse.NotFound;
}


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

    var router = Router.init(allocator, listener, null);
    try router.get("/", handleHome);
    try router.get("/echo/{str}", handleEcho);
    try router.get("/user-agent", handleUserAgent);
    try router.run();
}
