"""
Module with general utilities and missing standard library features that could be useful in any Julia project
"""
module Utils
using StatsFuns
import StatsFuns.logsumexp

export copy_with_eltype, issomething, flatmap, map_something, ntimes, some_vector,
assign, accumulate_val, accumulate_prod, accumulate_prod_normalized, assign_prod,
assign_prod_normalized, prod_fast, count_conjunction, sum_weighted_product, 
order_asc, to_long_mi, @no_error, disjoint, typejoin, lower_element_type, map_values, groupby, logsumexp,
unzip, @printlog, uniform


import Base.@time
import Base.print
import Base.println

# various utilities

"""
Is the argument not `nothing`?
"""
issomething(x) = !isnothing(x)

@inline map_something(f,v) = (v == nothing) ? nothing : f(v)

ntimes(f,n) = (for i in 1:n-1; f(); end; f())

@inline order_asc(x, y) = x > y ? (y, x) : (x , y)

function to_long_mi(m::Matrix{Float64}, min_int, max_int)::Matrix{Int64}
    δmi = maximum(m) - minimum(m)
    δint = max_int - min_int
    return @. round(Int64, m * δint / δmi + min_int)
end

macro no_error(ex)
    quote
        try
            $(esc(ex))
            true
        catch
            false
        end
    end
end

function disjoint(set1::AbstractSet, sets::AbstractSet...)::Bool
    seen = set1
    for set in sets
        if !isempty(intersect(seen,set))
            return false
        else
            seen = union(seen, set)
        end
    end
    return true
end

"Marginalize out dimensions `dims` from log-probability tensor"
function logsumexp(A::AbstractArray, dims)
    return dropdims(mapslices(StatsFuns.logsumexp, A, dims=dims), dims=dims)
end

macro unzip(x) 
    quote
        local a, b = zip($(esc(x))...)
        a = collect(a)
        b = collect(b)
        a, b
    end
end

#####################
# array parametric type helpers
#####################

"""
Copy the array while changing the element type
"""
copy_with_eltype(input, Eltype) = copyto!(similar(input, Eltype), input)

import Base.typejoin

"Get the most specific type parameter possible for an array"
typejoin(array) = mapreduce(e -> typeof(e), typejoin, array)

"Specialize the type parameter of an array to be most specific"
lower_element_type(array) = copy_with_eltype(array, typejoin(array))


#####################
# logging helpers
#####################

# overwrite @time and println, write to log file and stdout at the same time
using Suppressor:@capture_out

macro redirect_to_files(expr, outfile, errfile)
    quote
        open($outfile, "w") do out
            open($errfile, "w") do err
                redirect_stdout(out) do
                    redirect_stderr(err) do
                        $(esc(expr))
                    end
                end
            end
        end
    end
end
macro printlog(filename = "./temp.log")
    @eval begin
            close(open($filename, "w"))

            macro time(ex)
                quote
                    local stats = Base.gc_num()
                    local elapsedtime = Base.time_ns()
                    local val = $(esc(ex))
                    elapsedtime = Base.time_ns() - elapsedtime
                    local diff = Base.GC_Diff(Base.gc_num(), stats)
                    local str = @capture_out begin
                        Base.time_print(elapsedtime, diff.allocd, diff.total_time, Base.gc_alloc_count(diff))
                        Base.println()
                    end
                    local f = open($$(filename), "a+")
                    write(f, str)
                    close(f)
                    val
                end
            end

            function print(args...)
                str = @capture_out begin Base.print(stdout, args...) end
                f = open($filename, "a+")
                write(f, str)
                write(stdout, str)
                close(f)
                nothing
            end

            function println(args...)
                str = @capture_out begin Base.println(stdout, args...) end
                f = open($filename, "a+")
                write(f, str)
                write(stdout, str)
                close(f)
                nothing
            end

        end
end


#####################
# probability semantics and other initializers for various data types
#####################

@inline always(::Type{T}, dims::Int...) where T<:Number = ones(T, dims...)
@inline always(::Type{T}, dims::Int...) where T<:Bool = trues(dims...)

@inline never(::Type{T}, dims::Int...) where T<:Number = zeros(T, dims...)
@inline never(::Type{T}, dims::Int...) where T<:Bool = falses(dims...)

@inline some_vector(::Type{T}, dims::Int...) where T<:Number = Vector{T}(undef, dims...)
@inline some_vector(::Type{T}, dims::Int...) where T<:Bool = BitArray(undef, dims...)

@inline uniform(dims::Int...) = ones(Float64, dims...) ./ prod(dims)

#####################
# functional programming
#####################

# Your regular flatmap
# if you want the return array to have the right element type, provide an init with the desired type. Otherwise it may become Array{Any}
@inline flatmap(f, arr::AbstractVector, init=[]) = mapreduce(f, append!, arr; init=init)

function map_values(f::Function, dict::AbstractDict{K}, vtype::Type)::AbstractDict{K,vtype} where K
    mapped_dict = Dict{K,vtype}()
    for key in keys(dict)
        mapped_dict[key] = f(dict[key])
    end
    mapped_dict
end

function groupby(f::Function, list)
    groups = Dict()
    for v in list
        push!(get!(groups, f(v), []), v)
    end
    groups
end

function index_dict(x::AbstractVector{E})::Dict{E,Int} where E
    Dict(x[k] => k for k in eachindex(x))
end

#TODO create a struct that embeds an array and a index_dict result and acts like a Vector

#####################
# compute kernels
#####################

include("Kernels.jl")

end #module
