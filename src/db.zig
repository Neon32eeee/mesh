const std = @import("std");
const Mesh = @import("root.zig");

const ddb = Mesh.ddb;
const VoidDB = @import("voiddb.zig").VoidDB;

/// A generic database handle.
/// Can contain either a pointer to a real ddb.DB or a VoidDB.
/// No flags, unions, anyopaques, or generics.
pub const DB = struct {
    ddb: ?*ddb.DB = null,
    void_db: ?*VoidDB = null,

    /// Real DDB-mode.
    pub fn fromDDB(p: *ddb.DB) DB {
        return .{ .ddb = p };
    }

    /// VoidDB-mode. Doesn't save anything.
    pub fn fromVoid(p: *VoidDB) DB {
        return .{ .void_db = p };
    }

    /// Completely empty mode (if even a VoidDB instance is not needed).
    pub fn empty() DB {
        return .{};
    }

    /// Saves if real DB. Void/empty -> no-op.
    pub fn save(self: DB) !void {
        if (self.ddb) |d| return d.save();
    }

    /// Get the real DDB. null if we are working in VoidDB/empty.
    pub fn asDdb(self: DB) ?*ddb.DB {
        return self.ddb;
    }

    /// true if this is a real database
    pub fn isReal(self: DB) bool {
        return self.ddb != null;
    }
};

// ------------------- Tests -------------------

test "empty: no ddb, no void_db, not real" {
    const db = DB.empty();
    try std.testing.expect(db.ddb == null);
    try std.testing.expect(db.void_db == null);
    try std.testing.expect(!db.isReal());
    try std.testing.expect(db.asDdb() == null);
}

test "empty: save is a no-op" {
    const db = DB.empty();
    try db.save();
}

test "fromDDB: real, exposes pointer" {
    var fake: ddb.DB = undefined;
    const db = DB.fromDDB(&fake);

    try std.testing.expect(db.isReal());
    try std.testing.expect(db.asDdb() == &fake);
    try std.testing.expect(db.void_db == null);
}

test "fromVoid: not real, no ddb" {
    var fake: VoidDB = undefined;
    const db = DB.fromVoid(&fake);

    try std.testing.expect(!db.isReal());
    try std.testing.expect(db.asDdb() == null);
    try std.testing.expect(db.void_db == &fake);
}

test "fromVoid: save is a no-op" {
    var fake: VoidDB = undefined;
    const db = DB.fromVoid(&fake);
    try db.save();
}

test "default fields are null" {
    const db = DB{};
    try std.testing.expect(db.ddb == null);
    try std.testing.expect(db.void_db == null);
    try std.testing.expect(!db.isReal());
}

test "empty and default DB are equivalent" {
    const a = DB.empty();
    const b = DB{};
    try std.testing.expect(a.ddb == b.ddb);
    try std.testing.expect(a.void_db == b.void_db);
}

test "DB is copyable" {
    var fake: ddb.DB = undefined;
    const a = DB.fromDDB(&fake);
    const b = a;
    try std.testing.expect(b.isReal());
    try std.testing.expect(b.asDdb() == &fake);
}
