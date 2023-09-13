const std = @import("std");
const Allocator = std.mem.Allocator;
const DisjointSet = @import("zunion").DisjointSet;

// The strategy here is going to be
// 1. Insert dummy types for all the finicky structures (dictionaries, union-find, allocators, ...)
// 2. Build the API around those
// 3. One-by-one, back those operations with real data structures, adding error handling where necessary
// 4. Replace the wrapped data structures with the thing they're wrapping
// 5. As required we'll un-const the inputs
// 6. We'll re-factor a bit from there
// 7. We'll start implementing the rest of the paper
// 8. We can worry about performance/allocations in the distant future
//
// TODO:
// 1. Our notion of an EClass is some sort of doubly-linked pointer thing involving the
//    DisjointSet pointer structure. Probably ought to split that into the data we want
//    attached to the class (EClassState maybe?) and just use the DisjointSet pointer
//    structure as the EClass.

pub fn EGraph(comptime OpType: type, comptime max_node_children: usize) type {
    return struct {
        pub const ENode = struct {
            op: OpType,

            // avoid a lot of fragmentation, pointer chasing, and memory churn
            // in the common case of a grammar with unary/binary terms
            _buffer: [max_node_children]*EClass = undefined,
            _count: usize = 0,

            pub inline fn children(self: *@This()) []*EClass {
                return self._buffer[0..self._count];
            }

            pub inline fn make(op: OpType, _children: anytype) !@This() {
                if (_children.len > max_node_children)
                    return error.Overflow;
                var rtn: @This() = .{ .op = op, ._count = _children.len };
                for (rtn.children(), _children) |*target, c|
                    target.* = c;
                return rtn;
            }

            fn _hash(ctx: HashContext, key: @This()) u64 {
                _ = ctx;
                var hasher = std.hash.Wyhash.init(0);
                hasher.update(std.mem.asBytes(&@intFromEnum(key.op)));
                hasher.update(std.mem.asBytes(&key._count));
                for (key._buffer[0..key._count]) |eclass_ptr|
                    hasher.update(std.mem.asBytes(&@intFromPtr(eclass_ptr)));
                return hasher.final();
            }

            fn _eql(ctx: HashContext, a: @This(), b: @This()) bool {
                _ = ctx;
                if (a.op != b.op)
                    return false;
                if (a._count != b._count)
                    return false;
                for (a._buffer[0..a._count], b._buffer[0..b._count]) |x, y| {
                    if (x != y)
                        return false;
                }
                return true;
            }

            pub const HashContext = struct {
                pub const hash = _hash;
                pub const eql = _eql;
            };
        };

        pub const U = DisjointSet(*EClass);

        pub const EClass = struct {
            set: *U,
            parents: HashCons = .{},
        };

        const HashCons = std.HashMapUnmanaged(ENode, *EClass, ENode.HashContext, 80);

        hashcons: HashCons,
        worklist: std.ArrayList(*EClass),
        all_eclasses: std.AutoHashMapUnmanaged(*EClass, void),
        // TODO: the memory usage in this data structure is fairly fragmented, but some patterns
        // are optimizable, like the constant create/destroy of the hash map for counting
        // unique eclasses
        allocator: Allocator,
        raw_arena: *std.heap.ArenaAllocator,
        arena: Allocator,

        pub fn init(allocator: Allocator) !@This() {
            var raw_arena = try allocator.create(std.heap.ArenaAllocator);
            errdefer allocator.destroy(raw_arena);

            raw_arena.* = std.heap.ArenaAllocator.init(allocator);
            errdefer raw_arena.deinit();

            var worklist = std.ArrayList(*EClass).init(allocator);
            errdefer worklist.deinit();

            return @This(){
                .hashcons = HashCons{},
                .worklist = worklist,
                .all_eclasses = std.AutoHashMapUnmanaged(*EClass, void){},
                .allocator = allocator,
                .raw_arena = raw_arena,
                .arena = raw_arena.allocator(),
            };
        }

        pub fn deinit(self: *@This()) void {
            var iter = self.all_eclasses.keyIterator();
            while (iter.next()) |eclass_ptr|
                eclass_ptr.*.parents.deinit(self.allocator);
            self.hashcons.deinit(self.allocator);
            self.worklist.deinit();
            self.raw_arena.deinit();
            self.allocator.destroy(self.raw_arena);
        }

        pub fn add(self: *@This(), _enode: ENode) !*EClass {
            var enode = self.canonicalize(_enode);
            if (self.hashcons.get(enode)) |eclass_ptr| {
                return eclass_ptr;
            } else {
                var eclass = try self.arena.create(EClass);
                errdefer self.arena.destroy(eclass);
                var eclass_set = try U.make(self.arena, eclass);
                errdefer self.arena.destroy(eclass_set);
                eclass.set = eclass_set;
                try self.all_eclasses.put(self.arena, eclass, {});
                errdefer {
                    _ = self.all_eclasses.remove(eclass);
                }
                for (enode.children()) |child|
                    try child.parents.put(self.allocator, enode, eclass);
                try self.hashcons.put(self.allocator, enode, eclass);
                return eclass;
            }
        }

        pub fn merge(self: *@This(), id1: *EClass, id2: *EClass) !*EClass {
            if (self.find(id1) == self.find(id2))
                return self.find(id1);
            id1.set.join(id2.set);
            const new_id = id1.set.find().value;
            try self.worklist.append(new_id);
            return new_id;
        }

        pub fn canonicalize(self: *@This(), enode: ENode) ENode {
            var rtn: ENode = enode;
            for (rtn.children()) |*child|
                child.* = self.find(child.*);
            return rtn;
        }

        pub fn find(self: *@This(), eclass: *EClass) *EClass {
            _ = self;
            return eclass.set.find().value;
        }

        pub fn rebuild(self: *@This()) !void {
            while (self.worklist.items.len > 0) {
                var todo = try self.worklist.clone();
                defer todo.deinit();
                self.worklist.clearRetainingCapacity();
                var set = std.AutoHashMapUnmanaged(*EClass, void){};
                defer set.deinit(self.allocator);
                for (todo.items) |child|
                    try set.put(self.allocator, self.find(child), {});
                var set_iter = set.keyIterator();
                while (set_iter.next()) |eclass|
                    try self.repair(eclass.*);
            }
        }

        pub fn repair(self: *@This(), eclass: *EClass) !void {
            var p_iter = eclass.parents.iterator();
            while (p_iter.next()) |kv| {
                _ = self.hashcons.remove(kv.key_ptr.*);
                try self.hashcons.put(
                    self.allocator,
                    self.canonicalize(kv.key_ptr.*),
                    self.find(kv.value_ptr.*),
                );
            }
            var p_clone = try eclass.parents.clone(self.allocator);
            defer p_clone.deinit(self.allocator);
            eclass.parents.clearRetainingCapacity();

            var new_iter = p_clone.iterator();
            while (new_iter.next()) |kv| {
                var p_node = self.canonicalize(kv.key_ptr.*);
                if (eclass.parents.get(p_node)) |p_class|
                    _ = try self.merge(kv.value_ptr.*, p_class); // TODO: Should merge even return anything?
                try eclass.parents.put(self.allocator, p_node, self.find(kv.value_ptr.*));
            }
        }
    };
}

const Ops = enum {
    add,
    sub,
    mul,
    div,
};

noinline fn just_false() bool {
    return false;
}

test {
    const allocator = std.testing.allocator;

    const E = EGraph(Ops, 2);
    var e = try E.init(allocator);
    defer e.deinit();

    var enode = try E.ENode.make(.add, .{});
    if (just_false()) {
        _ = try e.add(enode);
        try e.rebuild();
    }
}
