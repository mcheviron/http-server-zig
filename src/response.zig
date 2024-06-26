const std = @import("std");

pub const HttpResponse = union(enum) {
    Ok: ?OkResponse,
    Created,
    NotFound,

    pub const Content = union(enum) {
        PlainText: []const u8,
        OctetStream: []const u8,
    };

    pub const Encoding = enum {
        Gzip,
    };

    pub const OkResponse = struct {
        content: ?Content,
        encoding: ?Encoding,
    };

    fn compressContent(content: []const u8, encoding: Encoding, allocator: std.mem.Allocator, writer: anytype) !void {
        var compressed_data = std.ArrayList(u8).init(allocator);
        defer compressed_data.deinit();

        switch (encoding) {
            .Gzip => {
                try writer.print("Content-Encoding: gzip\r\n", .{});
                var reader = std.io.fixedBufferStream(content);
                try std.compress.gzip.compress(reader.reader(), compressed_data.writer(), .{});
                try writer.print("Content-Length: {}\r\n", .{compressed_data.items.len});
                try writer.writeAll("\r\n");
                try writer.writeAll(compressed_data.items);
            },
        }
    }

    pub fn bytes(self: HttpResponse, allocator: std.mem.Allocator) ![]const u8 {
        var responseBuffer = std.ArrayList(u8).init(allocator);
        defer responseBuffer.deinit();
        const writer = responseBuffer.writer();

        switch (self) {
            .Ok => |ok_response| {
                if (ok_response) |resp| {
                    try writer.print("HTTP/1.1 200 OK\r\n", .{});
                    if (resp.content) |content_type| switch (content_type) {
                        .PlainText => |text| {
                            if (resp.encoding) |encoding| {
                                try compressContent(text, encoding, allocator, writer);
                            } else {
                                try writer.print("Content-Type: text/plain\r\n", .{});
                                try writer.print("Content-Length: {}\r\n", .{text.len});
                                try writer.writeAll("\r\n");
                                try writer.writeAll(text);
                            }
                        },
                        .OctetStream => |data| {
                            if (resp.encoding) |encoding| {
                                try compressContent(data, encoding, allocator, writer);
                            } else {
                                try writer.print("Content-Type: application/octet-stream\r\n", .{});
                                try writer.print("Content-Length: {}\r\n", .{data.len});
                                try writer.writeAll("\r\n");
                                try writer.writeAll(data);
                            }
                        },
                    };
                }
                try writer.writeAll("\r\n");
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
            .Ok => |ok_response| {
                if (ok_response) |resp| {
                    if (resp.content) |content_type| switch (content_type) {
                        .OctetStream => |data| allocator.free(data),
                        .PlainText => {},
                    };
                }
            },
            else => {},
        }
    }
};
