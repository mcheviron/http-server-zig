const std = @import("std");

pub const HttpVersion = enum {
    http1_1,
};

pub const ContentType = union(enum) {
    PlainText: []const u8,
    OctetStream: []const u8,
};

pub const HttpStatus = union(enum) {
    Ok,
    Created,
    NotFound,
};

pub const HttpResponse = struct {
    status: HttpStatus,
    body: ?ContentType,
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, status: HttpStatus, body: ?ContentType) HttpResponse {
        return .{
            .status = status,
            .body = body,
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *HttpResponse) void {
        self.buffer.deinit();
    }

    fn bytes(self: *HttpResponse) ![]const u8 {
        self.buffer.clearRetainingCapacity();
        const writer = self.buffer.writer();

        switch (self.status) {
            .Ok => {
                try writer.print("HTTP/1.1 200 OK\r\n", .{});
                if (self.body) |content_type| {
                    try writer.print("Content-Type: {s}\r\n", .{switch (content_type) {
                        .PlainText => "text/plain",
                        .OctetStream => "application/octet-stream",
                    }});
                }
            },
            .Created => try writer.print("HTTP/1.1 201 Created\r\n", .{}),
            .NotFound => try writer.print("HTTP/1.1 404 Not Found\r\n", .{}),
        }

        try writer.writeAll("\r\n");

        return self.buffer.items;
    }

    pub fn send(self: *HttpResponse, writer: anytype) !void {
        const response_bytes = try self.bytes();
        try writer.writeAll(response_bytes);
    }
};
