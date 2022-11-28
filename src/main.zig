const std = @import("std");
const net = std.net;
const StreamServer = net.StreamServer;
const Address = net.Address;
pub const io_mode = .evented;


pub fn main() anyerror!void {
    var stream_server = StreamServer.init(.{});
    defer stream_server.close();
    const address = try Address.resolveIp("0.0.0.0", 8081);
    try stream_server.listen(address);

    while (true) {
        const connection = try stream_server.accept();
        try connection.stream.writer().print("Hello world from Zig", .{});
        connection.stream.close();
    }    
}
