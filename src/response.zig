const std = @import("std");

pub const ContentType = union(enum) {
    PlainText: []const u8,
    OctetStream: []const u8,
};

pub const HttpResponse = union(enum) {
    Ok: ?ContentType,
    Created,
    NotFound,

    pub fn bytes(self: HttpResponse, buffer: []u8) ![]const u8 {
        var fbs = std.io.fixedBufferStream(buffer);
        const writer = fbs.writer();

        switch (self) {
            .Ok => |content_type| {
                try writer.print("HTTP/1.1 200 OK\r\n", .{});
                if (content_type) |ct| {
                    try writer.print("Content-Type: {s}\r\n", .{switch (ct) {
                        .PlainText => "text/plain",
                        .OctetStream => "application/octet-stream",
                    }});
                }
            },
            .Created => try writer.print("HTTP/1.1 201 Created\r\n", .{}),
            .NotFound => try writer.print("HTTP/1.1 404 Not Found\r\n", .{}),
        }

        try writer.writeAll("\r\n");

        return fbs.getWritten();
    }
};
