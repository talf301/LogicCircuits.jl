export save_as_dot, save_circuit, save_as_sdd, save_as_tex, save_as_dot2tex

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
decompile(n::Union{SddLiteralNode,PlainStructLiteralNode}, node2id, vtree2id) = 
    UnweightedLiteralLine(node2id[n], vtree2id[n.vtree], literal(n), false)

decompile(n::Union{SddConstantNode,PlainStructConstantNode}, node2id, _) = 
    AnonymousConstantLine(node2id[n], constant(n), false)

decompile(n::Union{Sdd⋁Node,PlainStruct⋁Node}, node2id, vtree2id) = 
    DecisionLine(node2id[n], vtree2id[n.vtree], UInt32(num_children(n)), 
                 map(c -> make_element(c, node2id), children(n)))

make_element(n::Union{Sdd⋀Node,PlainStruct⋀Node}, node2id) = 
    SDDElement(node2id[children(n)[1]],  node2id[children(n)[2]])

make_element(_::StructLogicCircuit, _) = 
    error("Given circuit is not an SDD, its decision node elements are not conjunctions.")

# TODO: decompile for logical circuit to some file format

#####################
# build maping
#####################

function get_node2id(circuit::LogicCircuit) 
    node2id = Dict{LogicCircuit, ID}()
    outnodes = filter(n -> !is⋀gate(n), circuit)
    sizehint!(node2id, length(outnodes))
    index = ID(0) # node id start from 0
    for n in outnodes
        node2id[n] = index
        index += ID(1)
    end
    node2id
end

function get_vtree2id(vtree::Vtree):: Dict{Vtree, ID}
    vtree2id = Dict{Vtree, ID}()
    sizehint!(vtree2id, num_nodes(vtree))
    index = ID(0) # vtree id start from 0
    foreach(vtree) do n
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

"Save a SDD circuit to file"
function save_as_sdd(name::String, circuit, vtree)
    @assert endswith(name, ".sdd")
    node2id = get_node2id(circuit)
    vtree2id = get_vtree2id(vtree)
    formatlines = Vector{CircuitFormatLine}()
    append!(formatlines, parse_sdd_file(IOBuffer(sdd_header())))
    push!(formatlines, SddHeaderLine(num_nodes(circuit)))
    for n in filter(n -> !is⋀gate(n), circuit)
        push!(formatlines, decompile(n, node2id, vtree2id))
    end
    save_lines(name, formatlines)
end

"Save a circuit to file"
save_circuit(name::String, circuit, vtree) =
    save_as_sdd(name, circuit, vtree)

"Rank nodes in the same layer left to right"
function get_nodes_level(circuit::Node)
    levels = Vector{Vector{Node}}()
    current = Vector{Node}()
    next = Vector{Node}()

    push!(next, circuit)
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

"""Effectively returns the inverse of `get_nodes_level`, returning a dictionary where keys are the
nodes and values are their levels, and the highest level in the circuit."""
function get_level_nodes(circuit::LogicCircuit)::Tuple{Dict{LogicCircuit, Int}, Int}
    levels = Dict{LogicCircuit, Int}()
    current = Vector{Node}()
    next = Vector{Node}()

    push!(next, circuit)
    i = 1
    while !isempty(next)
        current, next = next, current
        while !isempty(current)
            n = popfirst!(current)
            if isinner(n)
                for c in children(n)
                    if c ∉ next
                        push!(next, c)
                        levels[c] = i
                    end
                end
            end
        end
        i += 1
    end

    return levels, i
end

"Save logic circuit to .dot file"
function save_as_dot(circuit::LogicCircuit, file::String)
    circuit_nodes = linearize(circuit)
    node_cache = Dict{LogicCircuit, Int64}()
    for (i, n) in enumerate(circuit_nodes)
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

    for n in reverse(circuit_nodes)
        if is⋀gate(n)
            write(f, "$(node_cache[n]) [label=\"*$(node_cache[n])\"]\n")
        elseif is⋁gate(n)
            write(f, "$(node_cache[n]) [label=\"+$(node_cache[n])\"]\n")
        elseif isliteralgate(n) && ispositive(n)
            write(f, "$(node_cache[n]) [label=\"+$(variable(n))\"]\n")
        elseif isliteralgate(n)  && isnegative(n)
            write(f, "$(node_cache[n]) [label=\"-$(variable(n))\"]\n")
        elseif isfalse(n)
            write(f, "$(node_cache[n]) [label=\"F\"]\n")
        elseif istrue(n)
            write(f, "$(node_cache[n]) [label=\"T\"]\n")
        else
            throw("unknown node type")
        end
    end

    for n in reverse(circuit_nodes)
        if isinnergate(n)
            for c in children(n)
                write(f, "$(node_cache[n]) -> $(node_cache[c])\n")
            end
        end
    end

    write(f, "}\n")
    flush(f)
    close(f)
end

"""Save logic circuit as a LaTeX TikZ .tex file using the dot2tex engine.

Argument `V` is a label map for each vertex; `E` is a label map for each edge; `⋀_style`,
`⋁_style`, `lit_style`, `⊤_style`, and `⊥_style` are styles for each node type; `edge_turn` is how
far down should edges "bend"; `node_xsep` and `node_ysep` are x and y-axis separation sizes for
terminal nodes.

Note: `save_as_tex` does not work well on large circuits, and the resulting LaTeX file should serve
as a first sketch in (serious) need for adjustments.
"""
function save_as_dot2tex(circuit::LogicCircuit, file::String,
                     V::Dict{LogicCircuit, Any} = Dict{LogicCircuit, Any}(),
                     E::Dict{Tuple{LogicCircuit, Int}, Any} = Dict{Tuple{LogicCircuit, Int}, Any}(),
                     ⋀_style::String = "and gate,fill=blue!50!red!30",
                     ⋁_style::String = "or gate,fill=blue!50!green!30",
                     ⊤_style::String = "", ⊥_style::String = "", lit_style::String = "",
                     edge_turn::Float64 = 0.25, ortho_splines::Bool = true,
                     node_xsep::Float64 = 1.0, node_ysep::Float64 = 1.25)
    preamble = """
    \\documentclass{standalone}

    \\usepackage{mathtools}
    \\usepackage{amssymb}
    \\usepackage{amsfonts}
    \\usepackage{tikz}
    \\usepackage{xcolor}
    \\usepackage{dot2texi}
    \\usetikzlibrary{shapes,arrows,positioning,fit,circuits.logic.US}

    \\begin{document}

    \\begin{tikzpicture}[>=latex',circuit logic US,every circuit symbol/.style={thick,point up}]
        \\tikzstyle{and} = [$(⋀_style)]
        \\tikzstyle{or} = [$(⋁_style)]
        \\tikzstyle{top} = [$(⊤_style)]
        \\tikzstyle{bot} = [$(⊥_style)]
        \\tikzstyle{lit} = [$(lit_style)]
        \\begin{dot2tex}[dot,tikz,codeonly,styleonly,options=-s -tmath]
            digraph G {
                graph [pad="0.75", ranksep="0.25", nodesep="0.25"];
                node [label=""];
                $(ortho_splines ? "edge [style=\"invis\"];" : "")
    """
    postamble = """
    \\end{tikzpicture}
    \\end{document}
    """

    nodes = linearize(circuit)
    cache = Dict{LogicCircuit, Int}()
    for (i, n) in enumerate(nodes) cache[n] = i end
    L = get_nodes_level(circuit)

    function label(v::LogicCircuit)::String
        if haskey(V, v)
            return string(V[v])
        elseif isleaf(v)
            if isliteralgate(v)
                l = literal(v)
                return l < 0 ? "\$\\neg $(-l)\$" : "\$$l\$"
            end
            return istrue(v) ? "\$\\top\$" : "\$\\bot\$"
        end
        return ""
    end
    label(v::LogicCircuit, c::Int)::String = (e = (v, c); haskey(E, e) ? string(E[e]) : "")
    compute_xsep(m::Int, i::Int, sep::Float64)::String = string(sep*(i-1-((m-1)/2)))
    compute_edge_turn(m::Int, i::Int)::String = string(-edge_turn*(0.75*m-abs((m+1)/2 - i)))
    draw_edge(pid::Int, cid::Int, c::Int, m::Int, l::String)::String =
        "    \\draw (n$pid.input $c) -- ++(0,$(compute_edge_turn(m, c))) -| $l (n$cid);\n"
    leaf_type(t::LogicCircuit)::String = istrue(t) ? "top" : isfalse(t) ? "bot" : "lit"
    leaf_tikz(id::Int, pid::Int, m::Int, c::Int, label::String)::String =
        "    \\node (n$id) at (\$(n$pid.input $c) + ($(compute_xsep(m, c, node_xsep/2)),-$(node_ysep/2))\$) {$label};\n"

    f = open(file, "w")
    write(f, preamble)

    # Define nodes, except leaves which are treated as a special case.
    for N in Iterators.reverse(nodes)
        if isinner(N)
            write(f, "            n$(cache[N]) [style=\"$(is⋀gate(N) ? "and" : "or"),inputs=$('n'^num_children(N))\", label=\"$(label(N))\"];\n")
        end
    end

    # Write ranks.
    for l in L
        if length(l) > 1
            write(f, "            {rank=\"same\";newrank=\"true\";rankdir=\"LR\";")
            rank = ""
            foreach(x -> rank *= "n$(cache[x])->", l)
            rank = rank[1:end-2]
            write(f, rank)
            write(f, "[style=\"invis\"]}\n")
        end
    end

    # Draw "invisible" edges top-down to force layout.
    for N in Iterators.reverse(nodes)
        if isleaf(N) continue end
        for C in children(N)
            write(f, "            n$(cache[N]) -> n$(cache[C]);\n")
        end
    end

    write(f, "        }\n    \\end{dot2tex}\n")

    # Draw actual edges and terminal nodes.
    if ortho_splines
        for N in Iterators.reverse(nodes)
            if isleaf(N) continue end
            N_id = cache[N]
            m = num_children(N)
            for (i, C) in enumerate(children(N))
                C_id = cache[C]
                if isleaf(C) write(f, leaf_tikz(C_id, N_id, m, i, label(C))) end
                l = label(N, i)
                write(f, draw_edge(N_id, C_id, i, m, isempty(l) ? "" : "node {\\small $l}"))
            end
        end
    end

    write(f, postamble)
    flush(f)
    close(f)
end

"""Save logic circuit as a LaTeX TikZ .tex file.
Argument `V` is a label map for each vertex, `E` is a label map for each edge, `⋀_style` is the
TikZ conjunction node style to use, `⋁_style` is the TikZ disjunction node style to use,
`node_ysep` is the y-axis separation distance for nodes, `node_xsep` for the x-axis, `edge_turn` is
how far down should edges "bend", `verbose` if set to true prints comments to the LaTeX file for
better readability.

Note: `save_as_tex` does not work well on large circuits, and the resulting LaTeX file should serve
as a first sketch in (serious) need for adjustments.
"""
function save_as_tex(circuit::LogicCircuit, file::String,
                     V::Dict{LogicCircuit, Any} = Dict{LogicCircuit, Any}(),
                     E::Dict{Tuple{LogicCircuit, Int}, Any} = Dict{Tuple{LogicCircuit, Int}, Any}(),
                     ⋀_style::String = "and gate,fill=blue!50!red!30",
                     ⋁_style::String = "or gate,fill=blue!50!green!30",
                     node_ysep::Float64 = 1.25, node_xsep::Float64 = 1.0, edge_turn::Float64 = 0.25,
                     verbose::Bool = false)
    preamble = """
    \\documentclass{standalone}

    \\usepackage{mathtools}
    \\usepackage{amssymb}
    \\usepackage{amsfonts}
    \\usepackage{tikz}
    \\usepackage{xcolor}
    \\usetikzlibrary{shapes,arrows,positioning,fit,circuits.logic.US}

    \\newcommand{\\andNode}[4]{\\node[style={thick},#4,$(⋀_style)] (#1) at #2 {\\rotatebox{-90}{#3}}}
    \\newcommand{\\orNode}[4]{\\node[style={thick},#4,$(⋁_style)] (#1) at #2 {\\rotatebox{-90}{#3}}}

    \\begin{document}

    \\begin{tikzpicture}[circuit logic US,every circuit symbol/.style={thick,point up}]
    """
    postamble = """
    \\end{tikzpicture}
    \\end{document}
    """

    nodes = linearize(circuit)
    cache = Dict{LogicCircuit, Int}()
    for (i, n) in enumerate(nodes) cache[n] = i end
    L, max_level = get_level_nodes(circuit)

    function label(v::LogicCircuit)::String
        if haskey(V, v)
            return string(V[v])
        elseif isleaf(v)
            if isliteralgate(v)
                l = literal(v)
                return l < 0 ? "\$\\neg $(-l)\$" : "\$$l\$"
            end
            return istrue(v) ? "\$\\top\$" : "\$\\bot\$"
        end
        return ""
    end
    label(v::LogicCircuit, c::Int)::String = (e = (v, c); haskey(E, e) ? string(E[e]) : "")

    compute_xsep(m::Int, i::Int, sep::Float64, l::Int)::String = string(((max_level-l)*sep)*(i-1-((m-1)/2)))
    compute_edge_turn(m::Int, i::Int)::String = string(-edge_turn*(0.75*m-abs((m+1)/2 - i)))

    # Draws a TikZ root logical node. Arguments are: node type `t`, number of children `n`,
    # node ID `id`, and node label.
    root_tikz(t::String, n::Int, id::Int, label::String)::String =
        "  \\$(t)Node{n$id}{(0,0)}{$label}{inputs=$('n'^n)};\n"

    # Draws a TikZ inner logical node. Arguments are: node type `t`, number of children `n`, node
    # ID `id`, parent node ID `pid`, number of siblings `m`, child index `c`, node level `l`, and
    # node label.
    inner_tikz(t::String, n::Int, id::Int, pid::Int, m::Int, c::Int, l::Int, label::String)::String =
        "  \\$(t)Node{n$id}{(\$(n$pid.input $c) + ($(compute_xsep(m, c, node_xsep, l)),-$node_ysep)\$)}{$label}{inputs=$('n'^n)};\n"

    # Draws a TikZ leaf node. Arguments are: node ID `id`, parent node ID `pid`, number of siblings
    # `n`, child index `c`, and a terminal label.
    leaf_tikz(id::Int, pid::Int, m::Int, c::Int, label::String)::String =
        "  \\node (n$id) at (\$(n$pid.input $c) + ($(compute_xsep(m, c, node_xsep/2, max_level-1)),-$(node_ysep/2))\$) {$label};\n"

    # Draws a TikZ edge. Arguments are: outgoing edge node ID `pid`, incoming edge node ID `cid`,
    # number of "sibling" edges `m`, child index `c`, and edge label.
    edge_tikz(pid::Int, cid::Int, m::Int, c::Int, label::String)::String =
        (l = isempty(label) ? "" : "node {\\small $label}";
         "  \\draw (n$pid.input $c) -- ++(0,$(compute_edge_turn(m, c))) -| $l (n$cid);\n")

    inner_rep(N::LogicCircuit)::String = is⋀gate(N) ? "and" : "or"

    f = open(file, "w")

    write(f, preamble)

    Q = LogicCircuit[circuit]
    U = Dict{LogicCircuit, Bool}(circuit => true)
    first = true
    while !isempty(Q)
        N = popfirst!(Q)
        N_id = cache[N]
        m = num_children(N)
        if first
            verbose && write(f, "  % Root of circuit with ID: $N_id\n")
            write(f, root_tikz(inner_rep(N), m, N_id, label(N)))
            first = false
        end
        for (i, C) in enumerate(children(N))
            if haskey(U, C) continue end
            C_id = cache[C]
            if isleaf(C)
                verbose && write(f, "  % Leaf node with ID: $C_id, child of $N_id\n")
                write(f, leaf_tikz(C_id, N_id, m, i, label(C)))
            else
                t = inner_rep(C)
                verbose && write(f, "  % Inner node ($t gate) with ID: $C_id, child of $N_id\n")
                write(f, inner_tikz(t, num_children(C), C_id, N_id, m, i, L[C], label(C)))
                push!(Q, C); U[C] = true
            end
            verbose && write(f, "  % Edge from $N_id to $C_id\n")
            write(f, edge_tikz(N_id, C_id, m, i, label(N, i)))
        end
    end

    write(f, postamble)
    flush(f)
    close(f)
end
