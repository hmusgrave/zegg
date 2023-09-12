const std = @import("std");

// The strategy here is going to be
// 1. Insert dummy types for all the finicky structures (dictionaries, union-find, allocators, ...)
// 2. Build the API around those
// 3. One-by-one, back those operations with real data structures, adding error handling where necessary
// 4. Replace the wrapped data structures with the thing they're wrapping
// 5. As required we'll un-const the inputs
// 6. We'll re-factor a bit from there
// 7. We'll start implementing the rest of the paper
// 8. We can worry about performance/allocations in the distant future

pub fn List(comptime T: type) type {
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

        pub fn len(self: *const @This()) usize {
            _ = self;
            return 0;
        }

        pub fn clone(self: *const @This()) @This() {
            return self.*;
        }
    };
}

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

pub fn EGraph(comptime OpType: type) type {
    return struct {
        pub const ENode = struct {
            op: OpType,
            children: List(*EClass),
        };

        pub const U = DisjointSet(*EClass);

        pub const EClass = struct {
            parents: Dict(ENode, *@This()),
            set: *U,
        };

        hashcons: Dict(ENode, *EClass),
        worklist: List(*EClass),

        pub fn add(self: *@This(), _enode: ENode) *EClass {
            const enode = self.canonicalize(_enode);
            if (self.hashcons.get(enode)) |eclass_ptr| {
                return eclass_ptr;
            } else {
                // TODO: allocation/creation/destruction (everywhere, not just here)
                var eclass: EClass = undefined;
                var iter = enode.children.iter();
                while (iter.next()) |child|
                    child.parents.add(enode, &eclass);
                self.hashcons.add(enode, &eclass);
                return &eclass;
            }
        }

        pub fn merge(self: *@This(), id1: *EClass, id2: *EClass) *EClass {
            if (self.find(id1) == self.find(id2))
                return self.find(id1);
            id1.set.join(id2.set);
            const new_id = id1.set.find().value;
            self.worklist.add(new_id);
            return new_id;
        }

        pub fn canonicalize(self: *@This(), enode: ENode) ENode {
            var list: List(*EClass) = undefined;
            var iter = enode.children.iter();
            while (iter.next()) |child|
                list.add(self.find(child));
            return .{ .op = enode.op, .children = list };
        }

        pub fn find(self: *@This(), eclass: *EClass) *EClass {
            _ = self;
            return eclass.set.find().value;
        }

        pub fn rebuild(self: *@This()) void {
            while (self.worklist.len() > 0) {
                var todo = self.worklist.clone();
                var set: Set(*EClass) = undefined;
                var iter = todo.iter();
                while (iter.next()) |child|
                    set.add(self.find(child));
                var set_iter = set.iter();
                while (set_iter.next()) |eclass|
                    self.repair(eclass);
            }
        }

        pub fn repair(self: *@This(), eclass: *EClass) void {
            var p_iter = eclass.parents.iter();
            while (p_iter.next()) |kv| {
                self.hashcons.remove(kv.key);
                self.hashcons.add(
                    self.canonicalize(kv.key),
                    self.find(kv.val),
                );
            }

            var new_parents: Dict(ENode, *EClass) = undefined;
            var new_iter = new_parents.iter();
            while (new_iter.next()) |kv| {
                var p_node = self.canonicalize(kv.key);
                if (new_parents.get(p_node)) |p_class|
                    _ = self.merge(kv.val, p_class); // TODO: Should merge even return anything?
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
    const E = EGraph(Ops);
    var e: E = undefined;

    const ENode = E.ENode;
    var enode: ENode = undefined;
    if (just_false()) {
        _ = e.add(enode);
        e.rebuild();
    }
}
