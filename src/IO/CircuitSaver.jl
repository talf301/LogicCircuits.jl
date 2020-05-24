#####################
# Save lines
#####################

function save_lines(name::String, lines::CircuitFormatLines)
    open(name, "w") do f
        for line in lines
            println(f, line)
        end
    end
end

#####################
# decompile for nodes
#####################

"Decompile for sdd circuit, used during saving of circuits to file" 
decompile(n::StructLiteralNode, node2id, vtree2id)::UnweightedLiteralLine = 
    UnweightedLiteralLine(node2id[n], vtree2id[n.vtree], literal(n), false)

decompile(n::StructConstantNode, node2id, vtree2id)::AnonymousConstantLine = 
    AnonymousConstantLine(node2id[n], constant(n), false)

decompile(n::Struct⋁Node, node2id, vtree2id)::DecisionLine{SDDElement} = 
    DecisionLine(node2id[n], vtree2id[n.vtree], UInt32(num_children(n)), map(c -> make_element(c, node2id), children(n)))

make_element(n::Struct⋀Node, node2id) = 
    SDDElement(node2id[n.children[1]],  node2id[n.children[2]])

make_element(n::StructLogicalΔNode, node2id) = 
    error("Given circuit is not an SDD, its decision node elements are not conjunctions.")

# TODO: decompile for logical circuit to some file format

#####################
# build maping
#####################

function get_node2id(ln::AbstractVector{X}, T::Type)where X #<: T#::Dict{T, ID}
    node2id = Dict{T, ID}()
    outnodes = filter(n -> !(GateType(n) isa ⋀Gate), ln)
    sizehint!(node2id, length(outnodes))
    index = ID(0) # node id start from 0
    for n in outnodes
        node2id[n] = index
        index += ID(1)
    end
    node2id
end

function get_vtree2id(ln::PlainVtree):: Dict{PlainVtreeNode, ID}
    vtree2id = Dict{PlainVtreeNode, ID}()
    sizehint!(vtree2id, length(ln))
    index = ID(0) # vtree id start from 0

    for n in ln
        vtree2id[n] = index
        index += ID(1)
    end
    vtree2id
end

#####################
# saver for circuits
#####################

"Returns header for SDD file format"
function sdd_header()
    """
    c ids of sdd nodes start at 0
    c sdd nodes appear bottom-up, children before parents
    c
    c file syntax:
    c sdd count-of-sdd-nodes
    c F id-of-false-sdd-node
    c T id-of-true-sdd-node
    c L id-of-literal-sdd-node id-of-vtree literal
    c D id-of-decomposition-sdd-node id-of-vtree number-of-elements {id-of-prime id-of-sub}*
    c
    c File generated by Juice.jl
    c"""
end

function save_sdd_file(name::String, circuit::DecoratorΔ, vtree::PlainVtree)
    save_sdd_file(name, origin(circuit, StructLogicalΔNode), vtree)
end

"Save a SDD circuit to file"
function save_sdd_file(name::String, circuit::StructLogicalΔ, vtree::PlainVtree)
    #TODO no need to pass the vtree, we can infer it from origin?
    @assert endswith(name, ".sdd")
    node2id = get_node2id(circuit, StructLogicalΔNode)
    vtree2id = get_vtree2id(vtree)
    formatlines = Vector{CircuitFormatLine}()
    append!(formatlines, parse_sdd_file(IOBuffer(sdd_header())))
    push!(formatlines, SddHeaderLine(num_nodes(circuit)))
    for n in filter(n -> !(GateType(n) isa ⋀Gate), circuit)
        push!(formatlines, decompile(n, node2id, vtree2id))
    end
    save_lines(name, formatlines)
end

"Save a circuit to file"
save_circuit(name::String, circuit::StructLogicalΔ, vtree::PlainVtree) = save_sdd_file(name, circuit, vtree)

"Rank nodes in the same layer left to right"
function get_nodes_level(circuit::Δ)
    levels = Vector{Vector{ΔNode}}()
    current = Vector{ΔNode}()
    next = Vector{ΔNode}()

    push!(next, circuit[end])
    push!(levels, Base.copy(next))
    while !isempty(next)
        current, next = next, current
        while !isempty(current)
            n = popfirst!(current)
            if isinner(n)
                for c in children(n)
                    if !(c in next) push!(next, c); end
                end
            end
        end
        push!(levels, Base.copy(next))
    end

    return levels
end

function save_as_dot(root::LogicalΔNode, file::String)
    return save_as_dot(node2dag(root), file)
end

"Save logic circuit to .dot file"
function save_as_dot(circuit::LogicalΔ, file::String)
    node_cache = Dict{LogicalΔNode, Int64}()
    for (i, n) in enumerate(circuit)
        node_cache[n] = i
    end

    levels = get_nodes_level(circuit)

    f = open(file, "w")
    write(f,"digraph Circuit {\nsplines=false\nedge[arrowhead=\"none\",fontsize=6]\n")

    for level in levels
        if length(level) > 1
            write(f,"{rank=\"same\";newrank=\"true\";rankdir=\"LR\";")
            rank = ""
            foreach(x->rank*="$(node_cache[x])->",level)
            rank = rank[1:end-2]
            write(f, rank)
            write(f,"[style=invis]}\n")
        end
    end

    for n in reverse(circuit)
        if n isa ⋀Node
            write(f, "$(node_cache[n]) [label=\"*$(node_cache[n])\"]\n")
        elseif n isa ⋁Node
            write(f, "$(node_cache[n]) [label=\"+$(node_cache[n])\"]\n")
        elseif n isa LiteralNode && positive(n)
            write(f, "$(node_cache[n]) [label=\"+$(variable(n))\"]\n")
        elseif n isa LiteralNode && negative(n)
            write(f, "$(node_cache[n]) [label=\"-$(variable(n))\"]\n")
        elseif n isa FalseNode
            write(f, "$(node_cache[n]) [label=\"F\"]\n")
        elseif n isa TrueNode
            write(f, "$(node_cache[n]) [label=\"T\"]\n")
        else
            throw("unknown node type")
        end
    end

    for n in reverse(circuit)
        if n isa ⋀Node || n isa ⋁Node
            for c in n.children
                write(f, "$(node_cache[n]) -> $(node_cache[c])\n")
            end
        end
    end

    write(f, "}\n")
    flush(f)
    close(f)
end