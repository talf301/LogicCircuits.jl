
abstract type FormatLine end

"""
A line in the vtree file format
"""
abstract type VtreeFormatLine <: FormatLine end

const VtreeFormatLines = AbstractVector{<:VtreeFormatLine}

struct VtreeCommentLine{T<:AbstractString} <: VtreeFormatLine
    comment::T
end

struct VtreeHeaderLine <: VtreeFormatLine end

struct VtreeInnerLine <: VtreeFormatLine
    node_id::UInt32
    left_id::UInt32
    right_id::UInt32
end

struct VtreeLeafLine <: VtreeFormatLine
    node_id::UInt32
    variable::Var
end

# TODO: parameterize by Vtree type, and PlainVtree as default
function compile_vtree_format_lines(lines::VtreeFormatLines, 
                                    ::Type{V}=PlainVtree)::V where V<:Vtree 
    compile_vtree_format_lines_m(lines, V)[1]
end

# TODO: parameterize by Vtree type, and PlainVtree as default
function compile_vtree_format_lines_m(lines::VtreeFormatLines, 
                                      ::Type{V}=PlainVtree) where  V<:Vtree 

    # map from index to PlainVtree for input
    id2node = Dict{UInt32, V}()
    root = nothing

    compile(::Union{VtreeHeaderLine,VtreeCommentLine}) = () # do nothing

    compile(ln::VtreeLeafLine) = begin
        n = V(ln.variable)
        id2node[ln.node_id] = n
        root = n
    end

    compile(ln::VtreeInnerLine) = begin
        left_node = id2node[ln.left_id]
        right_node = id2node[ln.right_id]
        n = V(left_node,right_node)
        id2node[ln.node_id] = n
        root = n
    end

    foreach(compile, lines)
    root, id2node
end