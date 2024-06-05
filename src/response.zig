const std = @import("std");

pub const ContentType = union(enum) {
    PlainText: []const u8,
    OctetStream: []const u8,
};

pub const HttpResponse = union(enum) {
    Ok: ?ContentType,
    Created,
    NotFound,

    pub fn bytes(self: HttpResponse, allocator: std.mem.Allocator) ![]const u8 {
        var responseBuffer = std.ArrayList(u8).init(allocator);
        defer responseBuffer.deinit();
        const writer = responseBuffer.writer();

        switch (self) {
            .Ok => |content| {
                try writer.print("HTTP/1.1 200 OK\r\n", .{});
                if (content) |content_type| switch (content_type) {
                    .PlainText => |text| {
                        try writer.print("Content-Type: text/plain\r\n", .{});
                        try writer.print("Content-Length: {}\r\n", .{text.len});
                        try writer.writeAll("\r\n");
                        try writer.writeAll(text);
                    },
                    .OctetStream => |data| {
                        try writer.print("Content-Type: application/octet-stream\r\n", .{});
                        try writer.print("Content-Length: {}\r\n", .{data.len});
                        try writer.writeAll("\r\n");
                        try writer.writeAll(data);
                    },
                };
            },
            .Created => {
                try writer.print("HTTP/1.1 201 Created\r\n", .{});
                try writer.writeAll("\r\n");
            },
            .NotFound => {
                try writer.print("HTTP/1.1 404 Not Found\r\n", .{});
                try writer.writeAll("\r\n");
            },
        }

        return responseBuffer.toOwnedSlice();
    }

    pub fn deinit(self: HttpResponse, allocator: std.mem.Allocator) void {
        switch (self) {
            .Ok => |content| {
                if (content) |content_type| switch (content_type) {
                    .OctetStream => |data| allocator.free(data),
                    .PlainText => {},
                };
            },
            else => {},
        }
    }
};
