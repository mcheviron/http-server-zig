const std = @import("std");

pub const HttpRequestError = error{
    InvalidHttpRequest,
    InvalidHttpMethod,
    UnsupportedHttpMethod,
    InvalidHttpResource,
    InvalidHttpProtocol,
    UnsupportedHttpProtocol,
    InvalidHttpHeader,
    InvalidHttpHeaderValue,
};

pub const HttpMethod = enum {
    Get,
    Post,
    Put,
    Delete,
};

pub const HttpProtocol = enum {
    Http11,
};

pub const HttpRequest = struct {
    method: HttpMethod,
    resource: []const u8,
    protocol: HttpProtocol,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    params: ?std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, request: []const u8) !HttpRequest {
        std.log.debug("Initializing HttpRequest...", .{});
        var lines = std.mem.splitSequence(u8, request, "\r\n");
        const first_line = lines.next() orelse return HttpRequestError.InvalidHttpRequest;
        std.log.debug("First line: {s}", .{first_line});
        var first_line_parts = std.mem.splitSequence(u8, first_line, " ");
        const method = blk: {
            const method_str = first_line_parts.next() orelse return HttpRequestError.InvalidHttpMethod;
            std.log.debug("Method: {s}", .{method_str});
            if (std.mem.eql(u8, method_str, "GET")) {
                break :blk HttpMethod.Get;
            } else if (std.mem.eql(u8, method_str, "POST")) {
                break :blk HttpMethod.Post;
            } else if (std.mem.eql(u8, method_str, "PUT")) {
                break :blk HttpMethod.Put;
            } else if (std.mem.eql(u8, method_str, "DELETE")) {
                break :blk HttpMethod.Delete;
            } else {
                return HttpRequestError.UnsupportedHttpMethod;
            }
        };
        const resource = first_line_parts.next() orelse return HttpRequestError.InvalidHttpResource;
        std.log.debug("Resource: {s}", .{resource});
        const protocol = blk: {
            const protocol_str = first_line_parts.next() orelse return HttpRequestError.InvalidHttpProtocol;
            std.log.debug("Protocol: {s}", .{protocol_str});
            if (std.mem.eql(u8, protocol_str, "HTTP/1.1")) {
                break :blk HttpProtocol.Http11;
            } else {
                return HttpRequestError.UnsupportedHttpProtocol;
            }
        };

        var headers = std.StringHashMap([]const u8).init(allocator);
        errdefer headers.deinit();
        while (lines.next()) |line| {
            if (line.len == 0) break;
            std.log.debug("Header line: {s}", .{line});
            var header_parts = std.mem.splitSequence(u8, line, ":");
            const header_name = std.mem.trim(u8, header_parts.next() orelse return HttpRequestError.InvalidHttpHeader, " ");
            const header_value = std.mem.trim(u8, header_parts.next() orelse return HttpRequestError.InvalidHttpHeaderValue, " ");
            std.log.debug("Header: {s} = {s}", .{ header_name, header_value });
            try headers.put(header_name, header_value);
        }

        const body = lines.rest();
        std.log.debug("Body: {s}", .{body});

        std.log.debug("HttpRequest initialized successfully", .{});
        return HttpRequest{
            .method = method,
            .resource = resource,
            .protocol = protocol,
            .headers = headers,
            .body = body,
            .params = null,
        };
    }

    pub fn deinit(self: *HttpRequest) void {
        self.headers.deinit();
        if (self.params) |*params| {
            params.deinit();
        }
    }
};
