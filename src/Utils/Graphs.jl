
#####################
# Nodes and Graphs
#####################

abstract type Node end
abstract type DagNode <: Node end
abstract type TreeNode <: DagNode end

const DiGraph = AbstractVector{<:Node}
const Dag = AbstractVector{<:DagNode}
const Tree = AbstractVector{<:TreeNode}

#####################
# traits
#####################

"""
A trait hierarchy denoting types of nodes
`NodeType` defines an orthogonal type hierarchy of node types, so we can dispatch on node type regardless of the graph type.
See @ref{https://docs.julialang.org/en/v1/manual/methods/#Trait-based-dispatch-1}
"""

abstract type NodeType end

struct Leaf <: NodeType end
struct Inner <: NodeType end

@inline NodeType(instance::Node) = NodeType(typeof(instance))

#####################
# methods
#####################

"Get the children of a given inner node"
@inline children(n::Node)::Vector{<:Node} = children(NodeType(n), n)
@inline children(::Inner, n::Node)::Vector{<:Node} = error("Each inner node should implement a `children` method; one is missing for $(typeof(n))")

"Does the node have children?"
@inline has_children(n::Node)::Bool = has_children(NodeType(n), n)
@inline has_children(::Inner, n::Node)::Bool = !isempty(children(n))
@inline has_children(::Leaf, n::Node)::Bool = false

"Get the number of children of a given inner node"
@inline num_children(n::Node)::Int = num_children(NodeType(n), n)
@inline num_children(::Inner, n::Node)::Int = length(children(n))
@inline num_children(::Leaf, n::Node)::Int = 0

"Number of nodes in the graph"
num_nodes(c::DiGraph) = length(c)

"Number of edges in the graph"
num_edges(c::DiGraph) = sum(n -> num_children(n), c)

"Get the list of inner nodes in a given graph"
inodes(c::DiGraph) = filter(n -> NodeType(n) isa Inner, c)

"Get the list of leaf nodes in a given graph"
leafnodes(c::DiGraph) = filter(n -> NodeType(n) isa Leaf, c)

"Give count of types and fan-ins of inner nodes in the graph"
function inode_stats(c::DiGraph)
    groups = groupby(e -> (typeof(e),num_children(e)), inodes(c))
    map_values(v -> length(v), groups, Int)
end

"Give count of types of leaf nodes in the graph"
function leaf_stats(c::DiGraph)
    groups = groupby(e -> typeof(e), leafnodes(c))
    map_values(v -> length(v), groups, Int)
end

"Give count of types and fan-ins of all nodes in the graph"
node_stats(c::DiGraph) = merge(leaf_stats(c), inode_stats(c))

# When you suspect there is a bug but execution halts, it may be because of 
# pretty printing a huge recursive graph structure. 
# To safeguard against that case, we set a default show:
Base.show(io::IO, c::Node) = print(io, "$(typeof(c))($(hash(c))))")


"""
Compute the number of nodes in of a tree-unfolding of the DAG. 
"""
function tree_num_nodes(dag::Dag)::BigInt
    size = Dict{DagNode,BigInt}()
    for node in dag
        if has_children(node)
            size[node] = one(BigInt) + sum(c -> size[c], children(node))
        else
            size[node] = one(BigInt)
        end
    end
    size[dag[end]]
end

"Rebuild a DAG's linear bottom-up order from a new root node"
function root(root::DagNode)::Dag
    seen = Set{DagNode}()
    dag = Vector{DagNode}()
    see(n::DagNode) = see(NodeType(n),n)
    function see(::Leaf, n::DagNode)
        if n ∉ seen
            push!(seen,n)
            push!(dag,n)
        end
    end
    function see(::Inner, n::DagNode)
        if n ∉ seen
            for child in children(n)
                see(child)
            end
            push!(seen,n)
            push!(dag,n)
        end
    end
    see(root)
    lower_element_type(dag) # specialize the dag node type
end