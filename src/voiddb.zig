const std = @import("std");

/// VoidDB is a stub database.
/// It has the same interface as ddb.DB, but does nothing.
/// Use it if persistence is not needed.
pub const VoidDB = struct {
    pub fn init() VoidDB {
        return .{};
    }

    pub fn deinit(_: *VoidDB) void {}

    pub fn save(_: *VoidDB) !void {}
};
