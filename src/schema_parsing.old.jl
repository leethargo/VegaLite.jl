####################################################################
#  JSON schema parsing
####################################################################

using JSON

abstract SpecDef

type ObjDef <: SpecDef
  desc::String
  props::Dict{String, SpecDef}
  addprops::SpecDef
  required::Set{String}
end

type NumberDef <: SpecDef
  desc::String
end

type IntDef <: SpecDef
  desc::String
end

type StringDef <: SpecDef
  desc::String
  enum::Set{String}
end

type BoolDef <: SpecDef
  desc::String
end

type ArrayDef <: SpecDef
  desc::String
  items::SpecDef
end

type UnionDef <: SpecDef
  desc::String
  items::Vector
end

type RefDef <: SpecDef
  desc::String
  ref::String
end

type VoidDef <: SpecDef
  desc::String
end

type AnyDef <: SpecDef
  desc::String
end


function elemtype(typ::String)
  typ=="number"  && return NumberDef("")
  typ=="boolean" && return BoolDef("")
  typ=="integer" && return IntDef("")
  typ=="string"  && return StringDef("", Set{String}())
  error("unknown elementary type $typ")
end

UnionDef(spec::Dict)  = UnionDef(get(spec, "description", ""),
                                 elemtype.(spec["type"]))

NumberDef(spec::Dict) = NumberDef(get(spec, "description", ""))

IntDef(spec::Dict)    = IntDef(get(spec, "description", ""))

StringDef(spec::Dict) = StringDef(get(spec, "description", ""),
                                  Set{String}(get(spec, "enum", String[])))

BoolDef(spec::Dict)   = BoolDef(get(spec, "description", ""))

RefDef(spec::Dict)    = RefDef(get(spec, "description", ""),
                               split(spec["\$ref"], "/")[3])

ArrayDef(spec::Dict)  = ArrayDef(get(spec, "description", ""),
                                 toDef(spec["items"]))


#####################################################

# import Base.==
#
# function ==(a::ObjDef, b::ObjDef)
#   a.desc == b.desc || return false
#   Set(keys(a.props)) == Set(keys(b.props)) || return false
#   all( a.props[k] == b.props[k] for k in keys(a.props) ) || return false
#   a.addprops == b.addprops || return false
#   a.required == b.required
# end
#
# function ==(a::NumberDef, b::NumberDef)
#   a.desc == b.desc || return false
# end
#
# function ==(a::IntDef, b::IntDef)
#   a.desc == b.desc || return false
# end
#
# function ==(a::StringDef, b::StringDef)
#   a.desc == b.desc || return false
#   a.enum == b.enum
# end
#
# function ==(a::BoolDef, b::BoolDef)
#   a.desc == b.desc || return false
# end
#
# function ==(a::ArrayDef, b::ArrayDef)
#   a.desc == b.desc || return false
#   a.items == b.items
# end
#
# function ==(a::UnionDef, b::UnionDef)
#   a.desc == b.desc || return false
#   all( p -> p[1]==p[2], zip(a.items, b.items)) #TODO make order independent
# end
#
# function ==(a::RefDef, b::RefDef)
#   a.desc == b.desc || return false
#   a.ref == b.ref
# end
#
# function ==(a::VoidDef, b::VoidDef)
#   a.desc == b.desc || return false
#   true
# end
#


###########  Schema parsing  ##############

function toDef(spec::Dict)
  if haskey(spec, "type")
    typ = spec["type"]

    isa(typ, Vector) && return UnionDef(spec)

    if isa(typ, String)
      typ=="null"    && return VoidDef("")
      typ=="number"  && return NumberDef(spec)
      typ=="boolean" && return BoolDef(spec)
      typ=="integer" && return IntDef(spec)
      typ=="string"  && return StringDef(spec)
      typ=="array"  && return ArrayDef(spec)

      if typ == "object"
        ret = ObjDef(get(spec, "description", ""),
                     Dict{String, SpecDef}(),
                     VoidDef(""),
                     Set{String}(get(spec, "required", String[])))

        if haskey(spec, "properties")
          for (k,v) in spec["properties"]
            ret.props[k] = toDef(v)
          end
        end

        if haskey(spec, "required")
          ret.required = Set(spec["required"])
        end

        if haskey(spec, "additionalProperties") && isa(spec["additionalProperties"], Dict)
          ret.addprops = toDef(spec["additionalProperties"])
        end

        return ret
      end

      error("unknown type $typ")
    end

    error("type $typ is neither an array nor a string")

  elseif haskey(spec, "\$ref")
    return RefDef(spec)

  elseif haskey(spec, "anyOf")
    return UnionDef(get(spec, "description", ""),
                    toDef.(spec["anyOf"]))

  elseif length(spec) == 0
    return AnyDef("")

  else
    # warn("not a ref, 'AnyOf' and no type")
    return AnyDef("")
  end
end

defs = Dict{String, SpecDef}()

fn = joinpath(dirname(@__FILE__), "../deps/lib/", "v2.json")
spc = JSON.parsefile(fn)
for (k,v) in spc["definitions"]
  defs[k] = toDef(v)
end

# and now the definition of the root plot function
haskey(defs, "plot") && error("def 'plot' already defined")
defs["plot"] = toDef(spc)




###########  SpecDef tree creation (for function creation)  ##############

lookinto!(s::SpecDef, parent::SpecDef, prop="*") = deftree[s] = [(prop, parent)]

function lookinto!(s::RefDef, parent::SpecDef, prop="*")
  reals = defs[s.ref]
  if haskey(deftree,reals) # refdef already seen
    push!(deftree[reals], (prop, parent))
    return
  end
  deftree[reals] = [(prop, parent)]
  lookinto!(reals, parent, prop)
end

function lookinto!(s::ArrayDef, parent::SpecDef, prop="*")
  deftree[s] = [(prop, parent)]
  isa(s.items, UnionDef) && lookinto!(s.items, parent, prop)
end

function lookinto!(s::ObjDef, parent::SpecDef, prop="*")
  deftree[s] = [(prop, parent)]
  for (k,v) in s.props
    lookinto!(v, s, k)
  end
end

function lookinto!(s::UnionDef, parent::SpecDef, prop="*")
  deftree[s] = [(prop, parent)]
  for v in s.items
    lookinto!(v, s)
  end
end

deftree = Dict{SpecDef, Vector{Tuple{String, SpecDef}}}()
lookinto!(defs["plot"], VoidDef(""), "plot")

# length(deftree)