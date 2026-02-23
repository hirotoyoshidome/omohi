const _store_hash = @import("store/object/hash.zig");
const _store_atomic = @import("store/storage/atomic_write.zig");
const _store_lock = @import("store/storage/lock.zig");
const _store_time_utc = @import("store/storage/time/utc.zig");

test "load modules" {
    _ = _store_hash;
    _ = _store_atomic;
    _ = _store_lock;
    _ = _store_time_utc;
}
