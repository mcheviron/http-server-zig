const std = @import("std");
const HttpMethod = @import("request.zig").HttpMethod;
const HttpRequest = @import("request.zig").HttpRequest;
const HttpResponse = @import("response.zig").HttpResponse;
const Content = @import("response.zig").HttpResponse.Content;

pub const HandlerFn = *const fn (HttpRequest) HttpResponse;

pub const Route = struct {
    path: []const u8,
    params: ?[]const []const u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Route {
        if (!std.mem.containsAtLeast(u8, path, 1, "{") or !std.mem.containsAtLeast(u8, path, 1, "}")) {
            return Route{
                .path = path,
                .params = null,
            };
        }

        var params = std.ArrayList([]const u8).init(allocator);
        defer params.deinit();
        var clean_path = std.ArrayList(u8).init(allocator);
        defer clean_path.deinit();
        var parts = std.mem.splitSequence(u8, path, "/");

        var index: usize = 0;
        while (parts.next()) |part| {
            if (std.mem.startsWith(u8, part, "{") and std.mem.endsWith(u8, part, "}")) {
                const param_name = part[1 .. part.len - 1];
                try params.append(param_name);
                if (index > 0) {
                    try clean_path.append('/');
                }
                try clean_path.appendSlice("{}");
            } else {
                if (index > 0) {
                    try clean_path.append('/');
                }
                try clean_path.appendSlice(part);
            }
            index += 1;
        }

        return Route{
            .path = try clean_path.toOwnedSlice(),
            .params = try params.toOwnedSlice(),
        };
    }

    pub fn deinit(self: Route, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        if (self.params) |params| {
            allocator.free(params);
        }
    }

    pub fn matches(self: Route, allocator: std.mem.Allocator, path: []const u8) !?std.StringHashMap([]const u8) {
        var extracted_params = std.StringHashMap([]const u8).init(allocator);
        errdefer extracted_params.deinit();

        var route_parts = std.mem.splitSequence(u8, self.path, "/");
        var req_parts = std.mem.splitSequence(u8, path, "/");

        while (route_parts.next()) |route_part| {
            const req_part = req_parts.next() orelse {
                return null;
            };

            if (route_part.len == 2 and std.mem.eql(u8, route_part, "{}")) {
                if (self.params) |params| {
                    const param_name = params[extracted_params.count()];
                    try extracted_params.put(param_name, req_part);
                }
            } else if (!std.mem.eql(u8, route_part, req_part)) {
                return null;
            }
        }

        if (req_parts.next() != null) {
            return null;
        }

        return extracted_params;
    }
};

pub const Router = struct {
    routes: std.ArrayList(RouteEntry),
    listener: std.net.Server,
    directory: ?[]const u8,
    allocator: std.mem.Allocator,

    const RouteEntry = struct {
        method: HttpMethod,
        route: Route,
        handler: HandlerFn,
    };

    pub fn init(allocator: std.mem.Allocator, listener: std.net.Server, directory: ?[]const u8) Router {
        return Router{
            .routes = std.ArrayList(RouteEntry).init(allocator),
            .listener = listener,
            .directory = directory,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Router) void {
        for (self.routes.items) |route_entry| {
            route_entry.route.deinit(self.allocator);
        }
        self.routes.deinit();
    }

    fn addRoute(self: *Router, method: HttpMethod, path: []const u8, handler: HandlerFn) !void {
        const route = try Route.init(self.allocator, path);
        try self.routes.append(.{ .method = method, .route = route, .handler = handler });
    }

    pub fn get(self: *Router, path: []const u8, handler: HandlerFn) !void {
        try self.addRoute(HttpMethod.Get, path, handler);
    }

    pub fn post(self: *Router, path: []const u8, handler: HandlerFn) !void {
        try self.addRoute(HttpMethod.Post, path, handler);
    }

    pub fn put(self: *Router, path: []const u8, handler: HandlerFn) !void {
        try self.addRoute(HttpMethod.Put, path, handler);
    }

    pub fn delete(self: *Router, path: []const u8, handler: HandlerFn) !void {
        try self.addRoute(HttpMethod.Delete, path, handler);
    }

    pub fn handleRequest(self: *Router, request: HttpRequest) !HttpResponse {
        for (self.routes.items) |route_entry| {
            if (route_entry.method == request.method) {
                if (try route_entry.route.matches(self.allocator, request.resource)) |params| {
                    var req = request;
                    req.params = params;
                    return route_entry.handler(req);
                }
            }
        }

        if (std.mem.startsWith(u8, request.resource, "/files/")) {
            if (self.directory) |directory| {
                const file_path = try std.fs.path.join(self.allocator, &[_][]const u8{ directory, request.resource[7..] });
                defer self.allocator.free(file_path);

                switch (request.method) {
                    HttpMethod.Get => {
                        if (std.fs.openFileAbsolute(file_path, .{})) |file| {
                            defer file.close();
                            const contents = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
                            return HttpResponse{
                                .Ok = HttpResponse.OkResponse{
                                    .content = HttpResponse.Content{ .OctetStream = contents },
                                    .encoding = null,
                                },
                            };
                        } else |_| {}
                    },
                    HttpMethod.Post => {
                        const file = try std.fs.createFileAbsolute(file_path, .{});
                        defer file.close();
                        try file.writeAll(request.body);
                        return HttpResponse.Created;
                    },
                    else => {},
                }
            }
        }

        return HttpResponse.NotFound;
    }

    pub fn run(self: *Router) !void {
        while (true) {
            const connection = try self.listener.accept();
            const thread = try std.Thread.spawn(.{}, handleConnection, .{ self, connection });
            thread.detach();
        }
    }

    fn handleConnection(router: *Router, connection: std.net.Server.Connection) !void {
        const writer = connection.stream.writer();
        const reader = connection.stream.reader();

        const buffer = try router.allocator.alloc(u8, 1024);
        defer router.allocator.free(buffer);
        const bytes_read = try reader.read(buffer);
        const request_str = buffer[0..bytes_read];

        var request = try HttpRequest.init(router.allocator, request_str);
        defer request.deinit();

        const response = try router.handleRequest(request);
        defer response.deinit(router.allocator);

        const response_bytes = try response.bytes(router.allocator);
        defer router.allocator.free(response_bytes);

        try writer.writeAll(response_bytes);

        connection.stream.close();
    }
};
