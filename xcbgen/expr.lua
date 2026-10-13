--[[
This module contains helper classes for structure fields and length expressions.
]]
local Field = {}
Field.__index = Field

function Field.new(type_obj, field_type, field_name, visible, wire, auto, enum, isfd)
    return setmetatable({
        type = type_obj,
        field_type = field_type,
        field_name = field_name,
        enum = enum,
        visible = visible,
        wire = wire,
        auto = auto,
        isfd = isfd or false,
        parent = nil
    }, Field)
end

function Field:__tostring()
    local s = "Field"
    if self.field_name == nil then
        if self.field_type ~= nil then
            s = s .. " with type " .. tostring(self.type)
        end
    else
        s = s .. ' "' .. self.field_name .. '"'
    end
    if self.parent ~= nil then
        s = s .. " in " .. tostring(self.parent)
    end
    return s
end

local Expression = {}
Expression.__index = Expression

-- Constructor
function Expression.new(elt, parent)
    local self = setmetatable({}, Expression)
    self.parent = parent

    self.nmemb = nil

    self.lenfield_name = nil
    self.lenfield_type = nil
    self.lenfield_parent = nil
    self.lenfield = nil
    self.lenwire = false
    self.bitfield = false

    self.op = nil
    self.lhs = nil
    self.rhs = nil

    self.contains_listelement_ref = false

    -- helpers to access elt fields (safe)
    local tag = elt.tag
    local attr = elt.attr or {}
    local children = elt.children or {}

    if tag == 'list' then
        -- List going into a request (no explicit length field)
        local name = attr.name or elt.text
        if name then
            self.lenfield_name = name .. '_len'
        else
            self.lenfield_name = nil
        end
        self.lenfield_type = 'CARD32'

    elseif tag == 'fieldref' then
        -- Standard list with fieldref (text holds the field name)
        self.lenfield_name = elt.text

    elseif tag == 'paramref' then
        self.lenfield_name = elt.text
        self.lenfield_type = attr.type

    elseif tag == 'op' then
        self.op = attr and attr.op
        -- expect two children
        if #children >= 1 then
            self.lhs = Expression.new(children[1], parent)
        end
        if #children >= 2 then
            self.rhs = Expression.new(children[2], parent)
        end
        -- try to inherit lenfield_name from lhs or rhs
        self.lenfield_name = (self.lhs and self.lhs.lenfield_name) or nil
        if self.lenfield_name == nil then
            self.lenfield_name = (self.rhs and self.rhs.lenfield_name) or nil
        end

    elseif tag == 'unop' then
        self.op = attr and attr.op
        if #children >= 1 then
            self.rhs = Expression.new(children[1], parent)
            self.lenfield_name = self.rhs.lenfield_name
        end

    elseif tag == 'value' then
        -- constant expression; support decimal and 0x hex notation
        if elt.text then
            local v = tonumber(elt.text)
            self.nmemb = v
        end

    elseif tag == 'popcount' then
        self.op = 'popcount'
        if #children >= 1 then
            self.rhs = Expression.new(children[1], parent)
            self.lenfield_name = self.rhs.lenfield_name
        end

    elseif tag == 'enumref' then
        -- store as pair { ref, text }
        self.op = 'enumref'
        self.lenfield_name = { attr.ref, elt.text }

    elseif tag == 'sumof' then
        self.op = 'sumof'
        self.lenfield_name = attr.ref
        if #children >= 1 then
            -- nested expression evaluated for each list element
            self.rhs = Expression.new(children[1], parent)
        end

    elseif tag == 'listelement-ref' then
        self.op = 'listelement-ref'
        self.contains_listelement_ref = true

    else
        error(("Expression: undefined tag '%s'"):format(tostring(tag)))
    end

    return self
end

-- Returns true if the expression is a fixed constant
function Expression:fixed_size()
    return self.nmemb ~= nil
end

function Expression:get_value()
    return self.nmemb
end

-- If the expression value is guaranteed to be a multiple of some integer,
-- return that integer, otherwise return 1.
function Expression:get_multiple()
    local multiple = 1
    if self.op == '*' then
        if self.lhs and self.lhs:fixed_size() then
            multiple = multiple * (self.lhs:get_value() or 1)
        end
        if self.rhs and self.rhs:fixed_size() then
            multiple = multiple * (self.rhs:get_value() or 1)
        end
    end
    return multiple
end

-- Walk sub-expressions and propagate contains_listelement_ref
function Expression:recursive_resolve_tasks(module, parents)
    for _, subexpr in ipairs({ self.lhs, self.rhs }) do
        if subexpr ~= nil then
            subexpr:recursive_resolve_tasks(module, parents)
            if subexpr.contains_listelement_ref then
                self.contains_listelement_ref = true
            end
        end
    end
end

-- Resolve names/types that require knowledge of the module and parent chain.
-- `module` is expected to provide get_type(name) etc. `parents` is an array of parent type objects.
function Expression:resolve(module, parents)
    if self.op == 'enumref' and type(self.lenfield_name) == 'table' then
        -- lenfield_name was stored as { ref, text }
        local ref = self.lenfield_name[1]
        local text = self.lenfield_name[2]
        if ref then
            self.lenfield_type = module:get_type(ref)
        end
        self.lenfield_name = text
    elseif self.op == 'sumof' then
        -- need to find the field with lenfield_name among parents (search backwards)
        if self.lenfield_name then
            for i = #parents, 1, -1 do
                local p = parents[i]
                -- build a name -> field lookup
                local fields_map = {}
                if p.fields then
                    for _, f in ipairs(p.fields) do
                        fields_map[f.field_name] = f
                    end
                end
                local f = fields_map[self.lenfield_name]
                if f then
                    if p.is_case_or_bitcase then
                        -- switch is the ancestor: choose last element of p.parents
                        if p.parents and #p.parents > 0 then
                            self.lenfield_parent = p.parents[#p.parents]
                        else
                            self.lenfield_parent = nil
                        end
                    else
                        self.lenfield_parent = p
                    end
                    self.lenfield_type = f.field_type
                    self.lenfield = f
                    break
                end
            end
        end
    end

    -- Recurse into subexpressions
    self:recursive_resolve_tasks(module, parents)
end

return {
    Expression = Expression
}
