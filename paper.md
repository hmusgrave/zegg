I don't think the notion of an ID vs the object it's identifying is actually important except insofar as we need an easily hashable key to go into union-find, dictionaries, and whatnot. I'm going to give ignoring that a shot and see what happens.

Definition 2.1
1. A union-find structure lets you handle disjoint sets (EClasses) of objects (ENodes).
2. ENodes are defined by an operation (Op) and an ordered list of children the operation acts on (EClasses)
3. The rest of definition 2.1 is mumbo jumbo involving mappings of identifiers, which we said we'd ignore.

Definition 2.2
1. An eclass x is canonical iff find(x)==x
    - The union-find structure will do some canonicalization
      during the find operation
    - The union-find structure always returns the same root
      for any two equivalent sets (eclasses)
    - That property allows you to check for equivalence by
      checking if find(x)==find(y)

   Note that an eclass always represents the same "value" and
   doesn't morph as equality saturation progresses. Once you've
   found an eclass you can keep it around indefinitely. The
   eclasses it points to might vary over time.
2. An enode x (ENode) is canonical iff all its children (EClasses)
   are canonical.

Definition 2.4
1. eclasses are equivalent iff find(x)==find(y)
2. enodes are equivalent iff they're in the same eclass
3. terms (unused in code I think -- the grammatical equivalent of an enode)
   are equivalent iff their corresponding enodes are in the same eclass

Definition 2.6/2.7
1. Enodes must be closed under congruence
2. We must have a correct lookup from enodes to their canonical eclass

Upward Merging
1. each eclass has a parent list (all enodes with that class as a child)

Notes:
1. Hashcons is actually a structural dictionary. Two enodes should map to
   the same key iff their ops are the same and their eclasses are the same.
2. That means you can't just have something simple like storing the raw enodes
   or pointers to raw enodes as the keys because the canonical eclasses
   change over time and because raw pointers wouldn't capture that structural
   equality.
3. The repair step explicitly removes old nodes and adds new canonicalized
   nodes. The op stays the same, and the eclass changes. Since eclasses should
   always stick around and refer to their canonicalizations, that could be
   something as simple as a pointer to the current canonical eclass.
4. In that sense then, if that's the same structure an ENode has (it is), then
   the hashcons dict can literally use ENodes as keys and do a structural hash.

More Notes:
1. Something special is going to have to be done with respect to the ematch algorithm.
   We'll open that can of worms down the road. As a sketch of an idea, we can't do too
   much with the specific structure, so the only additional operation we probably need
   is enumeration of a class in the disjiont set structure. Turning those into a sort
   of doubly linked list probably suffices. Details might get dicey, but performance
   should be O(1) (though not cache friendly).

@This():
    hashcons: Dict[ENode, \*EClass]
    union_find: DisjointSet[EClass]
    worklist: List[EClass]

ENode:
  op: OpType,
  children: List[EClass],

EClass:
  parents: Dict[ENode, EClass],

fn add(self: @This(), enode: ENode) -> EClass {
    enode = self.canonicalize(enode)
    if (enode in self.hashcons)
        return self.hashcons[enode]
    else
        // TODO: we probably need to store something different here
        eclass = EClass{.enode=enode}
        for child in enode.children:
            child.parents.add((enode, eclass))
        self.hashcons[enode] = eclass
        return eclass_id
}

fn merge(self: @This(), id1: EClass, id2: EClass) EClass {
    if (self.find(id1) == self.find(id2))
        return self.find(id1);
    new_id = self.union_find.union(id1, id2)
    self.worklist.add(new_id)
    return new_id
}

fn canonicalize(self: @This(), enode: ENode) -> ENode {
    new_children = [self.find(e) for e in enode.children]
    return ENode{.op=enode.op, .children=new_ch};
}

fn find(self: @This(), eclass: EClass) -> EClass {
    return self.union_find.find(eclass);
}

fn rebuild(self: @This()) void {
    while (self.worklist.len > 0) {
        todo = self.worklist.clone()
        todo = {self.find(eclass) for eclass in todo}
        for eclass in todo:
            self.repair(eclass)
    }
}

fn repair(self: @This(), eclass: EClass) void {
    for p_node, p_class in eclass.parents:
        self.hashcons.remove(p_node)
        p_node = self.canonicalize(p_node)
        self.hashcons[p_node] = self.find(p_class)

    new_parents = {}
    for p_node, p_class in eclass.parents:
        p_node = self.canonicalize(p_node)
        if p_node in new_parents:
            self.merge(p_class, new_parents[p_node])
        new_parents[p_node] = self.find(p_class)

    p_class.parents = new_parents.items()
}
