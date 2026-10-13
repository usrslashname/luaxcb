--[[
XML parser.  One function for each top-level element in the schema.

Most functions just declare a new object and add it to the module.
For typedefs, eventcopies, xidtypes, and other aliases though,
we do not create a new type object, we just record the existing one under a new name.
]]

local lom = require("lxp.lom")
local path = require("path")   -- optionally provide a path.join implementation; if not available, we use concatenation
local state = require("xcbgen.state")
local xtypes = require("xcbgen.xtypes")

local matcher = {}

-- Convert a lxp.lom node into the { tag, text, attr, children } shape
local function normalize_lom_node(node)
    if not node then return nil end
    -- LOM returns text nodes as strings inside node; treat node.text and node.children uniformly
    local out = {
        tag = node.name,
        attr = node.attr or {},
        text = nil,
        children = {}
    }

    if node.text and type(node.text) == "string" then
        out.text = node.text
    end

    -- LOM represents mixed content as node[1], node[2], ...; node.children may also be used
    local child_list = node.children or {}
    -- if node itself exposes array-like children (some lom implementations put children directly at numeric keys)
    for i = 1, #node do
        table.insert(child_list, node[i])
    end

    for _, child in ipairs(child_list) do
        if type(child) == "table" and child.name then
            table.insert(out.children, normalize_lom_node(child))
        elseif type(child) == "string" then
            -- concatenate text nodes
            if out.text then
                out.text = out.text .. child
            else
                out.text = child
            end
        end
    end

    return out
end

-- Helper: concatenate namespace.prefix (array-like) with id, returning a new table
local function concat_prefix(prefix, id)
    local name = {}
    for i = 1, #prefix do name[i] = prefix[i] end
    name[#name + 1] = id
    return name
end

-- import node
function matcher.import_(node, module, namespace)
    module.import_level = (module.import_level or 0) + 1

    -- Build filename. If you have a path.join facility, prefer that.
    local filename = node.text
    local new_file
    if path and path.join then
        new_file = path.join(namespace.dir, filename .. ".xml")
    else
        new_file = namespace.dir .. "/" .. filename .. ".xml"
    end

    -- Create new Namespace and recurse
    local new_namespace = state.Namespace.new(new_file)
    matcher.execute(module, new_namespace)

    module.import_level = module.import_level - 1

    -- Record the import if not present already
    if not module:has_import(node.text) then
        module:add_import(node.text, new_namespace)
    end
end

-- typedef
function matcher.typedef(node, module, namespace)
    local id = node.attr and node.attr.newname or node.newname
    local name = concat_prefix(namespace.prefix, id)
    local oldname = node.attr and node.attr.oldname or node.oldname
    local typ = module:get_type(oldname)
    module:add_type(id, namespace.ns, name, typ)
end

-- xidtype
function matcher.xidtype(node, module, namespace)
    local id = node.attr and node.attr.name or node.name
    local name = concat_prefix(namespace.prefix, id)
    local typ = module:get_type("CARD32")
    module:add_type(id, namespace.ns, name, typ)
end

-- xidunion
function matcher.xidunion(node, module, namespace)
    local id = node.attr and node.attr.name or node.name
    local name = concat_prefix(namespace.prefix, id)
    local typ = module:get_type("CARD32")
    module:add_type(id, namespace.ns, name, typ)
end

-- enum
function matcher.enum(node, module, namespace)
    local id = node.attr and node.attr.name or node.name
    local name = concat_prefix(namespace.prefix, id)
    local typ = xtypes.Enum(name, node)
    module:add_type(id, namespace.ns, name, typ)
end

-- struct
function matcher.struct(node, module, namespace)
    local id = node.attr and node.attr.name or node.name
    local name = concat_prefix(namespace.prefix, id)
    local typ = xtypes.Struct(name, node)
    module:add_type(id, namespace.ns, name, typ)
end

-- eventstruct
function matcher.eventstruct(node, module, namespace)
    local id = node.attr and node.attr.name or node.name
    local name = concat_prefix(namespace.prefix, id)
    local typ = xtypes.EventStruct(name, node)
    module:add_type(id, namespace.ns, name, typ)
end

-- union
function matcher.union(node, module, namespace)
    local id = node.attr and node.attr.name or node.name
    local name = concat_prefix(namespace.prefix, id)
    local typ = xtypes.Union(name, node)
    module:add_type(id, namespace.ns, name, typ)
end

-- request
function matcher.request(node, module, namespace)
    local id = node.attr and node.attr.name or node.name
    local name = concat_prefix(namespace.prefix, id)
    local typ = xtypes.Request(name, node)
    module:add_request(id, name, typ)
end

-- event
function matcher.event(node, module, namespace)
    local id = node.attr and node.attr.name or node.name
    local name = concat_prefix(namespace.prefix, id)
    local event = xtypes.Event(name, node)
    local number = tonumber((node.attr and node.attr.number) or node.number)
    event:add_opcode(number, name, true)
    module:add_event(id, name, event)
end

-- eventcopy
function matcher.eventcopy(node, module, namespace)
    local id = node.attr and node.attr.name or node.name
    local name = concat_prefix(namespace.prefix, id)
    local ref = node.attr and node.attr.ref or node.ref
    local event = module:get_event(ref)
    local number = tonumber((node.attr and node.attr.number) or node.number)
    event:add_opcode(number, name, false)
    module:add_event(id, name, event)
end

-- error
function matcher.error(node, module, namespace)
    local id = node.attr and node.attr.name or node.name
    local name = concat_prefix(namespace.prefix, id)
    local err = xtypes.Error(name, node)
    local number = tonumber((node.attr and node.attr.number) or node.number)
    err:add_opcode(number, name, true)
    module:add_error(id, name, err)
end

-- errorcopy
function matcher.errorcopy(node, module, namespace)
    local id = node.attr and node.attr.name or node.name
    local name = concat_prefix(namespace.prefix, id)
    local ref = node.attr and node.attr.ref or node.ref
    local err = module:get_error(ref)
    local number = tonumber((node.attr and node.attr.number) or node.number)
    err:add_opcode(number, name, false)
    module:add_error(id, name, err)
end

-- table mapping tag names to handler functions
matcher.funcs = {
    ["import"]   = matcher.import_,
    typedef      = matcher.typedef,
    xidtype      = matcher.xidtype,
    xidunion     = matcher.xidunion,
    enum         = matcher.enum,
    struct       = matcher.struct,
    eventstruct  = matcher.eventstruct,
    union        = matcher.union,
    request      = matcher.request,
    event        = matcher.event,
    eventcopy    = matcher.eventcopy,
    error        = matcher.error,
    errorcopy    = matcher.errorcopy
}

-- Execute: iterate over namespace.root children and dispatch
function matcher.execute(module, namespace)
    -- Normalize a lxp.lom root node if present
    if namespace.root and namespace.root.name then
        -- if Namespace.new already parsed file with lom.parsefile, normalize it now
        namespace.root = normalize_lom_node(namespace.root)
    end

    local children = namespace.root.children or {}
    for i = 1, #children do
        local elt = children[i]
        local fn = matcher.funcs[elt.tag]
        if fn then
            fn(elt, module, namespace)
        else
            -- Unknown tag: ignore or warn (optional)
            -- print(("matcher.execute: unknown tag %s"):format(tostring(elt.tag)))
        end
    end
end

return matcher
