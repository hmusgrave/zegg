The paper is a bit convoluted to follow because they switch seamlessly between code and pseudocode, along with between types, instances, and unique identifiers. Plus, there are minor inconsistencies which interfere with locally building up a global understanding of the paper.

The plan is to copy-paste any algorithms/pseudocode/..., add type information, reify any inconsistencies, and then transliterate that to Zig.

def add(enode):
    enode = self.canonicalize(enode)
    if enode in self.hashcons:
        return self.hashcons[enode]
    else:
        eclass_id = self.new_singleton_eclass(enode)
        for child in enode.children:
            child.parents.add(enode, eclass_id)
        self.hashcons[enode] = eclass_id
        return eclass_id
    
def merge(id1, id2)
    if self.find(id1) == self.find(id2):
        return self.find(id1)
    new_id = self.union_find.union(id1, id2)
    # traditional egraph merge can be
    # emulated by calling rebuild right after
    # adding the eclass to the worklist
    self.worklist.add(new_id)
    return new_id

def canonicalize(enode)
    new_ch = [self.find(e) for e in enode.children]
    return mk_enode(enode.op, new_ch)

def find(eclass_id):
    return self.union_find.find(eclass_id)

def rebuild():
    while self.worklist.len() > 0:
        # empty the worklist into a local variable
        todo = take(self.worklist)
        # canonicalize and deduplicate the eclass refs
        # to save calls to repair
        todo = { self.find(eclass) for eclass in todo }
        for eclass in todo:
            self.repair(eclass)
    
def repair(eclass):
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
