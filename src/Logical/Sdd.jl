#############
# SddMgr
#############

"Root of the SDD manager node hierarchy"
abstract type SddMgrNode <: VtreeNode end

const SddMgr = AbstractVector{<:SddMgrNode}

#############
# SddMgrNode
#############

"Root of the SDD circuit node hierarchy"
abstract type SddNode{V<:SddMgrNode} <: StructLogicalΔNode{V} end

"A SDD logical leaf node"
abstract type SddLeafNode{V} <: SddNode{V} end

"A SDD logical inner node"
abstract type SddInnerNode{V} <: SddNode{V} end

"A SDD logical literal leaf node, representing the positive or negative literal of its variable"
mutable struct SddLiteralNode{V} <: SddLeafNode{V}
    literal::Lit
    vtree::V
end

"""
A structured logical constant leaf node, representing true or false.
These are the only structured nodes that don't have an associated vtree node (cf. SDD file format)
"""
abstract type SddConstantNode{V} <: SddInnerNode{V} end
struct SddTrueNode{V} <: SddConstantNode{V} end
struct SddFalseNode{V} <: SddConstantNode{V} end

"A structured logical conjunction node"
struct Sdd⋀Node{V} <: SddInnerNode{V}
    prime::SddNode{<:V}
    sub::SddNode{<:V}
    vtree::V
end

"A structured logical disjunction node"
mutable struct Sdd⋁Node{V} <: SddInnerNode{V}
    children::Vector{<:Sdd⋀Node{<:V}}
    vtree::V
    negation::Sdd⋁Node{V}
    Sdd⋁Node{V}(ch,v) where V = new(ch,v) # leave negation uninitialized
    Sdd⋁Node{V}(ch,v,neg) where V = new(ch,v,neg)
end

SddHasVtree = Union{Sdd⋁Node,Sdd⋀Node,SddLiteralNode}

"A structured logical circuit represented as a bottom-up linear order of nodes"
const Sdd{V} = AbstractVector{<:SddNode{<:V}} where {V <: SddMgrNode}

Base.eltype(::Type{Sdd}) = SddNode

#####################
# traits
#####################

@inline GateType(::Type{<:SddLiteralNode}) = LiteralLeaf()
@inline GateType(::Type{<:SddConstantNode}) = ConstantLeaf()
@inline GateType(::Type{<:Sdd⋀Node}) = ⋀()
@inline GateType(::Type{<:Sdd⋁Node}) = ⋁()

#####################
# methods
#####################

@inline literal(n::SddLiteralNode)::Lit = n.literal
@inline constant(::SddTrueNode)::Bool = true
@inline constant(::SddFalseNode)::Bool = false
@inline children(n::Sdd⋀Node) = [n.prime,n.sub]
@inline children(n::Sdd⋁Node) = n.children

@inline vtree(n::SddHasVtree) = n.vtree

# alias some SDD terminology: primes and subs
@inline prime(n::Sdd⋀Node)::SddNode = n.prime
@inline sub(n::Sdd⋀Node)::SddNode = n.sub


Base.show(io::IO, c::SddTrueNode) = print(io, "⊤")
Base.show(io::IO, c::SddFalseNode) = print(io, "⊥")
Base.show(io::IO, c::SddLiteralNode) = print(io, literal(c))
Base.show(io::IO, c::Sdd⋀Node) = begin
    recshow(c::Union{SddConstantNode,SddLiteralNode}) = "$c"
    recshow(c::Sdd⋁Node) = "D$(hash(c))"
    print(io, "($(recshow(prime(c))),$(recshow(sub(c))))")
end
Base.show(io::IO, c::Sdd⋁Node) = begin
    elems = ["$e" for e in children(c)]
    print(io, "[$(join(elems,','))]")
end
