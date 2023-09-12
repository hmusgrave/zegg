const std = @import("std");
const Allocator = std.mem.Allocator;

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

pub fn Set(comptime T: type) type {
    return struct {
        pub const Iter = struct {
            pub fn next(self: *@This()) ?T {
                _ = self;
                return null;
            }
        };

        pub fn iter(self: *const @This()) Iter {
            _ = self;
            return .{};
        }

        pub fn add(self: *@This(), x: T) void {
            _ = self;
            _ = x;
        }
    };
}

pub fn Dict(comptime K: type, comptime V: type) type {
    return struct {
        pub const Iter = struct {
            pub fn next(self: *@This()) ?struct { key: K, val: V } {
                _ = self;
                return null;
            }
        };

        pub fn iter(self: *const @This()) Iter {
            _ = self;
            return .{};
        }

        pub fn get(self: *const @This(), key: K) ?V {
            _ = self;
            _ = key;
            return null;
        }

        pub fn add(self: *@This(), key: K, val: V) void {
            _ = self;
            _ = key;
            _ = val;
        }

        pub fn remove(self: *@This(), key: K) void {
            _ = self;
            _ = key;
        }
    };
}

pub fn DisjointSet(comptime T: type) type {
    return struct {
        value: T,

        pub fn find(self: *@This()) *@This() {
            return self;
        }

        pub fn join(self: *@This(), other: *@This()) void {
            _ = self;
            _ = other;
        }
    };
}

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
        };

        pub const U = DisjointSet(*EClass);

        pub const EClass = struct {
            parents: Dict(ENode, *@This()),
            set: *U,
        };

        hashcons: Dict(ENode, *EClass),
        worklist: std.ArrayList(*EClass),
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
                .hashcons = undefined,
                .worklist = worklist,
                .allocator = allocator,
                .raw_arena = raw_arena,
                .arena = raw_arena.allocator(),
            };
        }

        pub fn deinit(self: *const @This()) void {
            self.worklist.deinit();
            self.raw_arena.deinit();
            self.allocator.destroy(self.raw_arena);
        }

        pub fn add(self: *@This(), _enode: ENode) *EClass {
            var enode = self.canonicalize(_enode);
            if (self.hashcons.get(enode)) |eclass_ptr| {
                return eclass_ptr;
            } else {
                // TODO: allocation/creation/destruction (everywhere, not just here)
                var eclass: EClass = undefined;
                for (enode.children()) |child|
                    child.parents.add(enode, &eclass);
                self.hashcons.add(enode, &eclass);
                return &eclass;
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
                var set: Set(*EClass) = undefined;
                for (todo.items) |child|
                    set.add(self.find(child));
                var set_iter = set.iter();
                while (set_iter.next()) |eclass|
                    try self.repair(eclass);
            }
        }

        pub fn repair(self: *@This(), eclass: *EClass) !void {
            var p_iter = eclass.parents.iter();
            while (p_iter.next()) |kv| {
                self.hashcons.remove(kv.key);
                self.hashcons.add(
                    self.canonicalize(kv.key),
                    self.find(kv.val),
                );
            }

            var new_parents: Dict(ENode, *EClass) = undefined;
            var new_iter = eclass.parents.iter();
            while (new_iter.next()) |kv| {
                var p_node = self.canonicalize(kv.key);
                if (new_parents.get(p_node)) |p_class|
                    _ = try self.merge(kv.val, p_class); // TODO: Should merge even return anything?
                new_parents.add(p_node, self.find(kv.val));
            }

            eclass.parents = new_parents;
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
        _ = e.add(enode);
        try e.rebuild();
    }
}
