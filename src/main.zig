const std = @import("std");
const net = std.net;
const StreamServer = net.StreamServer;
const Address = net.Address;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
pub const io_mode = .evented;


pub fn main() !void {
    var gpa = GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var stream_server = StreamServer.init(.{});
    defer stream_server.close();
    const address = try Address.resolveIp("0.0.0.0", 8081);
    try stream_server.listen(address);

    var frames = std.ArrayList(*Connection).init(allocator);
    while (true) {
        const connection = try stream_server.accept();
        var conn = try allocator.create(Connection);
        conn.* = .{
            .frame = async handler(allocator, connection.stream),
        };
        try frames.append(conn);
    }
}

const Connection = struct {
    frame: @Frame(handler),
};

const ParsingError = error {
    MethodNotValid,
    VersionNotValid,
};

const Method = enum {
    GET,
    POST,
    PUT,
    PATCH,
    OPTION,
    DELETE,

    pub fn fromString(s: []const u8) !Method {
        if (std.mem.eql(u8, "GET", s)) return .GET;
        if (std.mem.eql(u8, "POST", s)) return .POST;
        if (std.mem.eql(u8, "PUT", s)) return .PUT;
        if (std.mem.eql(u8, "PATCH", s)) return .PATCH;
        if (std.mem.eql(u8, "OPTION", s)) return .OPTION;
        if (std.mem.eql(u8, "DELETE", s)) return .DELETE;
        return ParsingError.MethodNotValid;
    }
};

const Version = enum {
    @"1.1",
    @"2",

    pub fn fromString(s: []const u8) !Version {
        if (std.mem.eql(u8, "HTTP/1.1", s)) return .@"1.1";
        if (std.mem.eql(u8, "HTTP/2", s)) return .@"2";
        return ParsingError.VersionNotValid;
    }

    pub fn asString(self: Version) []const u8 {
        if (self == Version.@"1.1") return "HTTP/1.1";
        if (self == Version.@"2") return "HTTP/2";
        unreachable; 
    }
};

const Status = enum {
    OK,

    pub fn asString(self: Status) []const u8 {
        if (self == Status.OK) return "OK";
    }

    pub fn asNumber(self: Status) usize {
        if (self == Status.OK) return 200;
    }
};

const HTTPContext = struct {
    method: Method,
    uri: []const u8,
    version: Version,
    headers: std.StringHashMap([]const u8),
    stream: net.Stream,

    pub fn bodyReader(self: *HTTPContext) net.Stream.Reader {
        return self.stream.reader();
    }

    pub fn response(self: *HTTPContext) net.Stream.Writer {
        return self.stream.writer();
    }

    pub fn respond(self: *HTTPContext, status: Status, _headers: ?std.StringHashMap([]const u8), body: []const u8) !void {
        var writer = self.response();
        try writer.print("{s} {} {s}\r\n", .{self.version.asString(), status.asNumber(), status.asString()});
        if (_headers) |headers| {
            var headers_iter = headers.iterator();
            while (headers_iter.next()) |entry| {
                try writer.print("{s}: {s}\n", .{entry.key_ptr.* ,entry.value_ptr.*});
            }
        }
        try writer.print("\r\n", .{});

        _ = try writer.write(body);
    }

    pub fn debugPrintRequest(self: *HTTPContext) void {
        std.debug.print("method: {any}\nuri: {s}\nversion: {any}\n", .{self.method, self.uri, self.version});
        var headers_iter = self.headers.iterator();
         std.debug.print("headers:\n", .{});
        while (headers_iter.next()) |entry| {
            std.debug.print("{s}: {s}\n", .{entry.key_ptr.* ,entry.value_ptr.*});
        }
    }

    pub fn init(allocator: std.mem.Allocator, stream: net.Stream) !HTTPContext {
        var first_line = try stream.reader().readUntilDelimiterAlloc(allocator, '\n', std.math.maxInt(usize));
        first_line = first_line[0..first_line.len - 1];
        var first_line_iter = std.mem.split(u8, first_line, " ");

        const method = first_line_iter.next().?;
        const uri = first_line_iter.next().?;
        const version = first_line_iter.next().?;
        var headers = std.StringHashMap([]const u8).init(allocator);

        while (true) {
            var line = try stream.reader().readUntilDelimiterAlloc(allocator, '\n', std.math.maxInt(usize));
            if (line.len == 1 and std.mem.eql(u8, line, "\r")) break;
            line = line[0..line.len];
            var line_iter = std.mem.split(u8, line, ":");
            const key = line_iter.next().?;
            var value = line_iter.next().?;
            if (value[0] == ' ') value = value[1..];
            try headers.put(key, value);
        }

        return HTTPContext {
            .headers = headers,
            .method = try Method.fromString(method),
            .version = try Version.fromString(version),
            .uri = uri,
            .stream = stream,
        };
    }
};

fn handler(allocator: std.mem.Allocator, stream: net.Stream) !void {
        defer stream.close();
        var http_context = try HTTPContext.init(allocator, stream);
        http_context.debugPrintRequest();

        try http_context.respond(Status.OK, null, "Hello from Zig!");
}