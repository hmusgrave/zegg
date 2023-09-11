The paper is a bit convoluted to follow because they switch seamlessly between code and pseudocode, along with between types, instances, and unique identifiers. Plus, there are minor inconsistencies which interfere with locally building up a global understanding of the paper.

The plan is to copy-paste any algorithms/pseudocode/..., add type information, reify any inconsistencies, and then transliterate that to Zig.

TODO: This is growing terrible fast. There's already an inconsistency in which methods use EClassId vs EClass, so to turn this into actual code there's probably a way to translate between them for free? I'm going to try again by fully reading the paper, writing down type signatures for the things the paper suggests I would want, and building things up that way. New doc is paper.md.

CI: EClassId

C: EClass

Q: EnodeOpType

E: Enode
    children: List[C]
    op: Q

worklist: List[CI]

UnionFind:
    union(CI, CI) -> CI
    find(CI) -> C

hashcons:
    Dict[E, CI]

mk_enode(Q, List[C]) -> ?

def add(enode: E) -> CI:
    enode = self.canonicalize(enode)
    if enode in self.hashcons:
        return self.hashcons[enode]
    else:
        eclass_id = self.new_singleton_eclass(enode)
        for child in enode.children:
            child.parents.add(enode, eclass_id)
        self.hashcons[enode] = eclass_id
        return eclass_id
    
def merge(id1: CI, id2: CI) -> CI:
    if self.find(id1) == self.find(id2):
        return self.find(id1)
    new_id: CI = self.union_find.union(id1, id2)
    self.worklist.add(new_id)
    return new_id

def canonicalize(enode: E)
    new_ch: List[C] = [self.find(e) for e in enode.children]
    return mk_enode(enode.op, new_ch)

def find(eclass_id: CI) -> C:
    return self.union_find.find(eclass_id)

def rebuild():
    while worklist.nonempty():
        todo: List[CI] = self.worklist.clone()
        todo: Set[C] = { self.find(eclass_id) for eclass_id in todo }
        for eclass in todo:
            self.repair(eclass)
    
def repair(eclass: C):
    # update the hashcons so it always points
    # canonical enodes to canonical eclasses
    for (p_node, p_eclass) in eclass.parents:
        self.hashcons.remove(p_node)
        p_node = self.canonicalize(p_node)
        self.hashcons[p_node] = self.find(p_eclass)
    
    # deduplicate the parents, noting that equal
    # parents get merged and put on the worklist
    new_parents = {}
    for (p_node, p_eclass) in eclass.parents:
        p_node = self.canonicalize(p_node)
        if p_node in new_parents:
            self.merge(p_eclass, new_parents[p_node])
        new_parents[p_node] = self.find(p_eclass)
    eclass.parents = new_parents
