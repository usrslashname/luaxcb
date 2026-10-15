--[[
This module contains the classes which represent XCB data types.
]]

local expr_mod = require("xcbgen.expr")
local Alignment = require("xcbgen.align").Alignment
local AlignmentLog = require("xcbgen.align").AlignmentLog

local Type = {}
Type.__index = Type

-- Utility: join type-name tuple-like table into string (mirrors Type.type_name_to_str)
local function type_name_to_str(type_name)
    if type(type_name) == "string" then
        return type_name
    else
        return table.concat(type_name, ".")
    end
end

function Type.new(name)
    local self = setmetatable({}, Type)
    self.name = name
    self.size = nil
    self.nmemb = nil
    self.resolved = false

    -- Screw isinstance() emulation flags
    self.is_simple = false
    self.is_list = false
    self.is_expr = false
    self.is_container = false
    self.is_reply = false
    self.is_union = false
    self.is_pad = false
    self.is_eventstruct = false
    self.is_event = false
    self.is_switch = false
    self.is_case_or_bitcase = false
    self.is_bitcase = false
    self.is_case = false
    self.is_fd = false

    self.required_start_align = Alignment.new()
    self.max_align_pad = 1

    return self
end

function Type:resolve(module)
    error("abstract resolve method not overridden!")
end

function Type:out(name)
    error("abstract out method not overridden!")
end

function Type:fixed_size()
    error("abstract fixed_size method not overridden!")
end

function Type:make_member_of(module, complex_type, field_type, field_name, visible, wire, auto, enum, is_fd)
    local new_field = expr_mod.Field.new(self, field_type, field_name, visible, wire, auto, enum, is_fd)

    -- Dump _placeholder_byte if present
    for idx, field in ipairs(complex_type.fields) do
        if field == _placeholder_byte then
            complex_type.fields[idx] = new_field
            new_field.parent = complex_type
            return
        end
    end

    table.insert(complex_type.fields, new_field)
    new_field.parent = complex_type
end

function Type:make_fd_of(module, complex_type, fd_name)
    local new_fd = expr_mod.Field.new(self, module:get_type_name("INT32"), fd_name, true, false, false, nil, true)
    for idx, field in ipairs(complex_type.fields) do
        if field == _placeholder_byte then
            complex_type.fields[idx] = new_fd
            new_fd.parent = complex_type
            return
        end
    end
    table.insert(complex_type.fields, new_fd)
    new_fd.parent = complex_type
end

function Type:get_total_size()
    if self:fixed_size() then
        if self.nmemb == nil then
            return self.size
        else
            return self.size * self.nmemb
        end
    else
        return nil
    end
end

function Type:get_align_offset()
    if self.required_start_align == nil then
        return 0
    else
        return self.required_start_align.offset
    end
end

function Type:is_acceptable_start_align(start_align, callstack, log)
    return self:get_alignment_after(start_align, callstack, log) ~= nil
end

function Type:get_alignment_after(start_align, callstack, log)
    if self.required_start_align == nil or self.required_start_align:is_guaranteed_at(start_align) then
        return self:unchecked_get_alignment_after(start_align, callstack, log)
    else
        if log ~= nil then
            log:fail(start_align, "", self, callstack and (function() local t={}; for _,v in ipairs(callstack) do table.insert(t,v) end; return t end)() or {}, -- callstack copy
                "start_align is incompatible with required_start_align " .. tostring(self.required_start_align))
        end
        return nil
    end
end

function Type:unchecked_get_alignment_after(start_align, callstack, log)
    error("abstract unchecked_get_alignment_after method not overridden!")
end

-- Type tostring
function Type:__tostring()
    return type(self).__name or (getmetatable(self) and getmetatable(self).__name) or ("Type \"" .. type_name_to_str(self.name) .. "\"")
end

-- PrimitiveType
local PrimitiveType = {}
PrimitiveType.__index = PrimitiveType
setmetatable(PrimitiveType, { __index = Type })

function PrimitiveType.new(name, size)
    local self = Type.new(name)
    setmetatable(self, PrimitiveType)
    self.size = size
    self.nmemb = 1
    self.required_start_align = Alignment.for_primitive_type(size)
    return self
end

function PrimitiveType:unchecked_get_alignment_after(start_align, callstack, log)
    local my_callstack = {}
    if callstack then
        for _,v in ipairs(callstack) do table.insert(my_callstack, v) end
    end
    table.insert(my_callstack, self)

    local after_align = start_align:align_after_fixed_size(self.size)

    if log ~= nil then
        if after_align == nil then
            log:fail(start_align, "", self, my_callstack, "align after fixed size " .. tostring(self.size) .. " failed")
        else
            log:ok(start_align, "", self, my_callstack, after_align)
        end
    end

    return after_align
end

function PrimitiveType:fixed_size()
    return true
end

-- SimpleType
local SimpleType = {}
SimpleType.__index = SimpleType
setmetatable(SimpleType, { __index = PrimitiveType })

function SimpleType.new(name, size, xml_type)
    local self = PrimitiveType.new(name, size)
    setmetatable(self, SimpleType)
    self.is_simple = true
    self.xml_type = xml_type
    return self
end

function SimpleType:resolve(module)
    self.resolved = true
end

-- Out functions are language-specific in original; we don't set them here.

-- Cardinal datatype globals (create after SimpleType defined)
local tcard8 = SimpleType.new({ "uint8_t" }, 1, "CARD8")
local tcard16 = SimpleType.new({ "uint16_t" }, 2, "CARD16")
local tcard32 = SimpleType.new({ "uint32_t" }, 4, "CARD32")
local tcard64 = SimpleType.new({ "uint64_t" }, 8, "CARD64")
local tint8 = SimpleType.new({ "int8_t" }, 1, "INT8")
local tint16 = SimpleType.new({ "int16_t" }, 2, "INT16")
local tint32 = SimpleType.new({ "int32_t" }, 4, "INT32")
local tint64 = SimpleType.new({ "int64_t" }, 8, "INT64")
local tchar = SimpleType.new({ "char" }, 1, "char")
local tfloat = SimpleType.new({ "float" }, 4, "float")
local tdouble = SimpleType.new({ "double" }, 8, "double")
local tbyte = SimpleType.new({ "uint8_t" }, 1, "BYTE")
local tbool = SimpleType.new({ "uint8_t" }, 1, "BOOL")
local tvoid = SimpleType.new({ "uint8_t" }, 1, "void")

-- FileDescriptor
local FileDescriptor = {}
FileDescriptor.__index = FileDescriptor
setmetatable(FileDescriptor, { __index = SimpleType })

function FileDescriptor.new()
    local self = SimpleType.new("int", 4, "fd")
    setmetatable(self, FileDescriptor)
    self.is_fd = true
    return self
end

function FileDescriptor:fixed_size()
    return true
end

-- Enum
local Enum = {}
Enum.__index = Enum
setmetatable(Enum, { __index = SimpleType })

function Enum.new(name, elt)
    local self = SimpleType.new(name, 4, "enum")
    setmetatable(self, Enum)
    self.values = {}
    self.bits = {}
    self.doc = nil

    for _, item in ipairs(elt.children or {}) do
        if item.tag == "doc" then
            self.doc = require("xcbgen.xtypes").Doc and require("xcbgen.xtypes").Doc.new(name, item) or nil
        end

        if # (item.children or {}) == 0 then
            table.insert(self.values, { item.attr and item.attr.name or item.name, "" })
        else
            local value = (item.children or {})[1]
            if value.tag == "value" then
                table.insert(self.values, { item.attr and item.attr.name or item.name, value.text })
            elseif value.tag == "bit" then
                table.insert(self.values, { item.attr and item.attr.name or item.name, string.format("%u", 1 << tonumber(value.text, 0)) })
                table.insert(self.bits, { item.attr and item.attr.name or item.name, value.text })
            end
        end
    end

    return self
end

function Enum:resolve(module)
    self.resolved = true
end

function Enum:fixed_size()
    return true
end

-- ListType
local ListType = {}
ListType.__index = ListType
setmetatable(ListType, { __index = Type })

function ListType.new(elt, member, ...)
    local parents = { ... }
    local self = Type.new(member.name)
    setmetatable(self, ListType)
    self.is_list = true
    self.member = member
    self.parents = parents
    local lenfield_name = false

    if elt.tag == "list" then
        local elts = elt.children or {}
        if #elts == 0 then
            self.expr = expr_mod.Expression.new(elt, self)
            -- determine if list in parent is request/event/reply/error
            local is_list_in_parent = self.parents[1] and (function() local t = self.parents[1].elt and self.parents[1].elt.tag; return t == "request" or t == "event" or t == "reply" or t == "error" end)() or false
            if not elts[1] and is_list_in_parent then
                self.expr = expr_mod.Expression.new(elt, self)
                self.expr.op = "calculate_len"
            else
                self.expr = expr_mod.Expression.new(elts[1] or elt, self)
            end
        else
            self.expr = expr_mod.Expression.new(elts[1], self)
        end
    end

    self.size = member.size
    if not member:fixed_size() then
        self.size = nil
    end
    self.nmemb = (self.expr and self.expr.nmemb) or nil
    self.required_start_align = self.member.required_start_align

    return self
end

function ListType:make_member_of(module, complex_type, field_type, field_name, visible, wire, auto, enum)
    if not self:fixed_size() then
        local lenfid = self.expr.lenfield_type
        local lenfield_name = self.expr.lenfield_name
        local lenwire = self.expr.lenwire
        local needlen = true

        for _, parent in ipairs(self.parents) do
            for _, field in ipairs(parent.fields or {}) do
                if field.field_name == lenfield_name then
                    needlen = false
                end
            end
        end

        if needlen then
            local typ = module:get_type(lenfid)
            local lenfield_type = module:get_type_name(lenfid)
            typ:make_member_of(module, complex_type, lenfield_type, lenfield_name, true, lenwire, false, enum)
        end
    end

    local wire = wire
    if self.member.is_fd then
        wire = false
    end

    Type.make_member_of(self, module, complex_type, field_type, field_name, visible, wire, auto, enum, self.member.is_fd)
end

function ListType:resolve(module)
    if self.resolved then return end
    self.member:resolve(module)
    self.expr:resolve(module, self.parents)

    if self.member:fixed_size() then
        self.size = self.member.size
    else
        self.size = nil
    end

    self.required_start_align = self.member.required_start_align

    if not self:fixed_size() then
        for _, parent in ipairs(self.parents) do
            for _, field in ipairs(parent.fields or {}) do
                if field.field_name == self.expr.lenfield_name and field.wire then
                    self.expr.lenfield = field
                    break
                end
            end
        end
    end

    self.resolved = true
end

function ListType:fixed_size()
    return self.member:fixed_size() and self.expr:fixed_size()
end

function ListType:unchecked_get_alignment_after(start_align, callstack, log)
    local my_callstack = {}
    if callstack then for _,v in ipairs(callstack) do table.insert(my_callstack, v) end end
    table.insert(my_callstack, self)

    if start_align == nil then
        if log ~= nil then log:fail(start_align, "", self, my_callstack, "start_align is None") end
        return nil
    end

    if self.expr:fixed_size() then
        local num_elements = self.nmemb
        local prev_alignment = nil
        local alignment = start_align
        while num_elements > 0 do
            if alignment == nil then
                if log ~= nil then
                    log:fail(start_align, "", self, my_callstack,
                        ("fixed size list with size %d after %d iterations, at transition from alignment \"%s\"")
                        :format(self.nmemb, (self.nmemb - num_elements), tostring(prev_alignment)))
                end
                return nil
            end
            prev_alignment = alignment
            alignment = self.member:get_alignment_after(prev_alignment, my_callstack, log)
            num_elements = num_elements - 1
        end
        if log ~= nil then log:ok(start_align, "", self, my_callstack, alignment) end
        return alignment
    else
        local multiple = self.expr:get_multiple()
        assert(multiple > 0)

        local alignment = start_align
        while true do
            local prev_multiple_alignment = alignment
            local prev_alignment = alignment
            local after_alignment = nil
            for multiple_count = 0, multiple - 1 do
                after_alignment = self.member:get_alignment_after(prev_alignment, my_callstack, log)
                if after_alignment == nil then
                    if log ~= nil then
                        log:fail(start_align, "", self, my_callstack, "variable size list at transition from alignment \"" .. tostring(prev_alignment) .. "\"")
                    end
                    return nil
                end
                prev_alignment = after_alignment
            end

            alignment = prev_multiple_alignment:combine_with(after_alignment)

            if alignment == prev_multiple_alignment then
                if log ~= nil then log:ok(start_align, "", self, my_callstack, alignment) end
                return alignment
            end
        end
    end
end

-- ExprType (exprfield)
local ExprType = {}
ExprType.__index = ExprType
setmetatable(ExprType, { __index = PrimitiveType })

function ExprType.new(elt, member, ...)
    local parents = { ... }
    local self = PrimitiveType.new(member.name, member.size)
    setmetatable(self, ExprType)
    self.is_expr = true
    self.member = member
    self.parents = parents
    self.expr = expr_mod.Expression.new((elt.children and elt.children[1]) and elt.children[1] or nil, self)
    return self
end

function ExprType:resolve(module)
    if self.resolved then return end
    self.member:resolve(module)
    self.resolved = true
end

-- PadType
local PadType = {}
PadType.__index = PadType
setmetatable(PadType, { __index = Type })

function PadType.new(elt)
    local self = Type.new(tcard8.name)
    setmetatable(self, PadType)
    self.is_pad = true
    self.size = 1
    self.nmemb = 1
    self.align = 1
    self.serialize = false
    if elt ~= nil then
        self.nmemb = tonumber((elt.attr and elt.attr.bytes) or "1", 0)
        self.align = tonumber((elt.attr and elt.attr.align) or "1", 0)
        self.serialize = (((elt.attr and elt.attr.serialize) or "false"):lower() == "true")
    end
    -- pads don't require alignment at their start
    self.required_start_align = Alignment.new(1, 0)
    return self
end

function PadType:resolve(module)
    self.resolved = true
end

function PadType:fixed_size()
    return self.align <= 1
end

function PadType:unchecked_get_alignment_after(start_align, callstack, log)
    if self.align <= 1 then
        local after_align = start_align:align_after_fixed_size(self:get_total_size())
        if log ~= nil then
            if after_align == nil then
                log:fail(start_align, "", self, callstack, "align after fixed size pad of size " .. tostring(self.size) .. " failed")
            else
                log:ok(start_align, "", self, callstack, after_align)
            end
        end
        return after_align
    end

    -- align-pad: align > 1 and size == 1 and nmemb == 1
    assert(self.align > 1)
    assert(self.size == 1)
    assert(self.nmemb == 1)
    local after_align
    if start_align.offset == 0 and self.align <= start_align.align and (start_align.align % self.align == 0) then
        after_align = start_align
    else
        after_align = Alignment.new(self.align, 0)
    end

    if log ~= nil then
        log:ok(start_align, "", self, callstack, after_align)
    end
    return after_align
end

-- ComplexType
local ComplexType = {}
ComplexType.__index = ComplexType
setmetatable(ComplexType, { __index = Type })

function ComplexType.new(name, elt)
    local self = Type.new(name)
    setmetatable(self, ComplexType)
    self.is_container = true
    self.elt = elt
    self.fields = {}
    self.nmemb = 1
    self.size = 0
    self.lenfield_parent = { self }
    self.length_expr = nil

    -- get required_start_align
    local required_start_align_element = nil
    if elt then
        for _, child in ipairs(elt.children or {}) do
            if child.tag == "required_start_align" then
                required_start_align_element = child
                break
            end
        end
    end

    if required_start_align_element == nil then
        self.required_start_align = nil
    else
        local align = tonumber((required_start_align_element.attr and required_start_align_element.attr.align) or "4", 0)
        local offset = tonumber((required_start_align_element.attr and required_start_align_element.attr.offset) or "0", 0)
        self.required_start_align = Alignment.new(align, offset)
    end

    return self
end

function ComplexType:resolve(module)
    if self.resolved then return end

    for _, child in ipairs(self.elt.children or {}) do
        local enum = nil
        local field_name, fkey, typ, visible
        if child.tag == "pad" then
            field_name = "pad" .. tostring(module.pads or 0)
            fkey = "CARD8"
            typ = PadType.new(child)
            module.pads = (module.pads or 0) + 1
            visible = false
        elseif child.tag == "field" then
            field_name = child.attr and child.attr.name
            enum = child.attr and child.attr.enum
            fkey = child.attr and child.attr.type
            typ = module:get_type(fkey)
            visible = true
        elseif child.tag == "exprfield" then
            field_name = child.attr and child.attr.name
            fkey = child.attr and child.attr.type
            typ = (require("xcbgen.xtypes")).ExprType and (require("xcbgen.xtypes")).ExprType.new(child, module:get_type(fkey), table.unpack(self.lenfield_parent)) or ExprType.new(child, module:get_type(fkey), table.unpack(self.lenfield_parent))
            visible = false
        elseif child.tag == "list" then
            field_name = child.attr and child.attr.name
            fkey = child.attr and child.attr.type
            local ftype
            if fkey == "fd" then
                ftype = FileDescriptor.new()
                fkey = "INT32"
            else
                ftype = module:get_type(fkey)
            end
            typ = ListType.new(child, ftype, table.unpack(self.lenfield_parent))
            visible = true
        elseif child.tag == "switch" then
            field_name = child.attr and child.attr.name
            local field_type = {}
            for i = 1, #self.name do field_type[i] = self.name[i] end
            table.insert(field_type, field_name)
            typ = (require("xcbgen.xtypes")).SwitchType and (require("xcbgen.xtypes")).SwitchType.new(field_type, child, table.unpack(self.lenfield_parent)) or nil
            visible = true
            -- make_member_of and resolve then continue
            if typ then
                typ:make_member_of(module, self, field_type, field_name, visible, true, false)
                typ:resolve(module)
            end
            goto continue_field_loop
        elseif child.tag == "fd" then
            local fd_name = child.attr and child.attr.name
            local t = module:get_type("INT32")
            t:make_fd_of(module, self, fd_name)
            goto continue_field_loop
        elseif child.tag == "length" then
            self.length_expr = expr_mod.Expression.new((child.children and child.children[1]) and child.children[1] or nil, self)
            goto continue_field_loop
        else
            -- Hit this on Reply etc.
            goto continue_field_loop
        end

        ::continue_field_loop::
        if typ ~= nil and (child.tag ~= "switch" and child.tag ~= "fd" and child.tag ~= "length") then
            local field_type = module:get_type_name(fkey)
            typ:make_member_of(module, self, field_type, field_name, visible, true, false, enum)
            typ:resolve(module)

            if typ.max_align_pad and typ.max_align_pad > self.max_align_pad then
                self.max_align_pad = typ.max_align_pad
            end
        end
    end

    self:check_implicit_fixed_size_part_aligns()
    self:calc_size()
    self:calc_or_check_required_start_align()

    self.resolved = true
end

function ComplexType:calc_size()
    self.size = 0
    for _, m in ipairs(self.fields) do
        if not m.wire then goto continue_calc_size end
        if m.type:fixed_size() then
            self.size = self.size + (m.type:get_total_size() or 0)
        else
            self.size = nil
            break
        end
        ::continue_calc_size::
    end
end

function ComplexType:calc_or_check_required_start_align()
    if self.required_start_align == nil then
        local log = AlignmentLog.new()
        local callstack = {}
        self.required_start_align = self:calc_minimally_required_start_align(callstack, log)
        if self.required_start_align == nil then
            print(("ERROR: could not calc required_start_align of %s\nDetails:\n%s"):format(tostring(self), tostring(log)))
        else
            if self.required_start_align.offset ~= 0 then
                print(("WARNING: %s\n\thas start-align with non-zero offset: %s\n\tsuggest to add explicit definition with:\n\t\t<required_start_align align=\"%d\" offset=\"%d\" />\n\tor to fix the xml so that zero offset is ok\n")
                    :format(tostring(self), tostring(self.required_start_align), self.required_start_align.align, self.required_start_align.offset))
            end
        end
    else
        local log = AlignmentLog.new()
        local callstack = {}
        if not self:is_possible_start_align(self.required_start_align, callstack, log) then
            print(("ERROR: required_start_align %s of %s causes problems\nDetails:\n%s"):format(tostring(self.required_start_align), tostring(self), tostring(log)))
        end
    end
end

function ComplexType:calc_minimally_required_start_align(callstack, log)
    local best_log = nil
    local best_failed_align = nil
    for _, align in ipairs({1,2,4,8}) do
        for offset = 0, align-1 do
            local align_candidate = Alignment.new(align, offset)
            local my_log = AlignmentLog.new()
            if self:is_possible_start_align(align_candidate, callstack, my_log) then
                log:append(my_log)
                return align_candidate
            else
                local my_ok_count = my_log:ok_count()
                if best_log == nil or my_ok_count > best_log:ok_count() or (my_ok_count == best_log:ok_count() and align_candidate.align > (best_failed_align and best_failed_align.align or 0) and align_candidate.align ~= 8) then
                    best_log = my_log
                    best_failed_align = align_candidate
                end
            end
        end
    end

    log:append(best_log)
    return nil
end

function ComplexType:is_possible_start_align(align, callstack, log)
    if align == nil then return false end
    if (self.max_align_pad > align.align) or (align.align % self.max_align_pad ~= 0) then
        return false
    end
    return self:get_alignment_after(align, callstack, log) ~= nil
end

function ComplexType:fixed_size()
    for _, m in ipairs(self.fields) do
        if not m.type:fixed_size() then return false end
    end
    return true
end

function ComplexType:check_implicit_fixed_size_part_aligns()
    local size = 0
    for _, field in ipairs(self.fields) do
        if not field.wire then goto continue_check end
        if not field.type:fixed_size() then
            break
        end
        local required_field_align = field.type.required_start_align
        if required_field_align == nil then
            error(("field \"%s\" in \"%s\" has not required_start_align"):format(tostring(field.field_name), tostring(self.name)))
        end
        local mis_align = (size + required_field_align.offset) % required_field_align.align
        if mis_align ~= 0 then
            local padsize = required_field_align.align - mis_align
            error(("C-compiler would insert implicit alignpad of size %d before field \"%s\" in \"%s\""):format(padsize, field.field_name, type_name_to_str(self.name)))
        end
        size = size + (field.type:get_total_size() or 0)
        ::continue_check::
    end
end

function ComplexType:unchecked_get_alignment_after(start_align, callstack, log)
    local my_align = start_align
    if my_align == nil then return nil end

    for _, field in ipairs(self.fields) do
        if not field.wire then goto continue_unchecked end
        local my_callstack = {}
        if callstack then for _,v in ipairs(callstack) do table.insert(my_callstack, v) end end
        table.insert(my_callstack, self)
        table.insert(my_callstack, field)

        local prev_align = my_align
        my_align = field.type:get_alignment_after(my_align, my_callstack, log)
        if my_align == nil then
            if log ~= nil then
                log:fail(prev_align, field.field_name, self, my_callstack, "alignment is incompatible with this field")
            end
            return nil
        else
            if log ~= nil then
                log:ok(prev_align, field.field_name, self, my_callstack, my_align)
            end
        end
        ::continue_unchecked::
    end

    if log ~= nil then
        local my_callstack = {}
        if callstack then for _,v in ipairs(callstack) do table.insert(my_callstack, v) end end
        table.insert(my_callstack, self)
        log:ok(start_align, "", self, my_callstack, my_align)
    end
    return my_align
end

-- SwitchType
local SwitchType = {}
SwitchType.__index = SwitchType
setmetatable(SwitchType, { __index = ComplexType })

function SwitchType.new(name, elt, ...)
    local parents = { ... }
    local self = ComplexType.new(name, elt)
    setmetatable(self, SwitchType)
    self.parents = parents
    self.lenfield_parent = {}
    for _,p in ipairs(parents) do table.insert(self.lenfield_parent, p) end
    table.insert(self.lenfield_parent, self)
    self.bitcases = {}
    self.is_switch = true
    local elts = elt.children or {}
    self.expr = expr_mod.Expression.new(elts[1] or elt, self)
    return self
end

function SwitchType:resolve(module)
    if self.resolved then return end
    local parents = {}
    for _, p in ipairs(self.parents) do table.insert(parents, p) end
    table.insert(parents, self)

    for index, child in ipairs(self.elt.children or {}) do
        if child.tag == "bitcase" or child.tag == "case" then
            local field_name = child.attr and child.attr.name
            local field_type
            if field_name == nil then
                field_type = {}
                for i = 1, #self.name do field_type[i] = self.name[i] end
                table.insert(field_type, ("%s%d"):format(child.tag, index))
            else
                field_type = {}
                for i = 1, #self.name do field_type[i] = self.name[i] end
                table.insert(field_type, field_name)
            end

            local type_obj
            if child.tag == "bitcase" then
                type_obj = BitcaseType.new(index, field_type, child, table.unpack(parents))
            else
                type_obj = CaseType.new(index, field_type, child, table.unpack(parents))
            end

            if field_name == nil then type_obj.has_name = false end
            local visible = true

            type_obj:make_member_of(module, self, field_type, field_name, visible, true, false)
            type_obj:resolve(module)

            local inserted = false
            for _, new_field in ipairs(type_obj.fields) do
                local placed = false
                for idx, field in ipairs(self.fields) do
                    if field == _placeholder_byte then
                        self.fields[idx] = new_field
                        placed = true
                        break
                    end
                end
                if not placed then
                    table.insert(self.fields, new_field)
                end
            end
        end
    end

    self:calc_size()
    self:calc_or_check_required_start_align()
    self.resolved = true
end

function SwitchType:make_member_of(module, complex_type, field_type, field_name, visible, wire, auto, enum)
    if not self:fixed_size() then
        local lenfid = self.expr.lenfield_type
        local lenfield_name = self.expr.lenfield_name
        local lenwire = self.expr.lenwire
        local needlen = true

        for _, parent in ipairs(self.parents) do
            for _, field in ipairs(parent.fields or {}) do
                if field.field_name == lenfield_name then
                    needlen = false
                end
            end
        end

        if needlen then
            local typ = module:get_type(lenfid)
            local lenfield_type = module:get_type_name(lenfid)
            typ:make_member_of(module, complex_type, lenfield_type, lenfield_name, true, lenwire, false, enum)
        end
    end

    Type.make_member_of(self, module, complex_type, field_type, field_name, visible, wire, auto, enum)
end

function SwitchType:calc_size() end

function SwitchType:fixed_size()
    return false
end

function SwitchType:check_implicit_fixed_size_part_aligns() return end

function SwitchType:unchecked_get_alignment_after(start_align, callstack, log)
    local case_fields = {}
    for _, field in ipairs(self.bitcases or {}) do
        if field.type.is_case then
            table.insert(case_fields, field)
        end
    end

    if #case_fields == 0 then
        case_fields = { nil }
    end

    local my_callstack = {}
    if callstack then for _,v in ipairs(callstack) do table.insert(my_callstack, v) end end
    table.insert(my_callstack, self)

    local total_align = nil
    local first = true
    for _, case_field in ipairs(case_fields) do
        local my2_callstack = {}
        for _,v in ipairs(my_callstack) do table.insert(my2_callstack, v) end
        if case_field ~= nil then table.insert(my2_callstack, case_field) end

        local case_align = self:get_align_for_selected_case_field(case_field, start_align, my2_callstack, log)
        if case_align == nil then
            if log ~= nil then
                if case_field == nil then
                    log:fail(start_align, "", self, my2_callstack, "alignment without cases (only bitcases) failed")
                else
                    log:fail(start_align, "", self, my2_callstack .. { case_field }, "alignment for selected case " .. tostring(case_field.field_name) .. " failed")
                end
            end
            return nil
        end

        if first then
            total_align = case_align
            first = false
        else
            total_align = total_align:combine_with(case_align)
        end

        if log ~= nil then
            if case_field == nil then
                log:ok(start_align, "without cases (only arbitrary bitcases)", self, my2_callstack, case_align)
            else
                log:ok(start_align, "case " .. tostring(case_field.field_name) .. " and arbitrary bitcases", self, my2_callstack, case_align)
            end
        end
    end

    if log ~= nil then
        log:ok(start_align, "", self, my_callstack, total_align)
    end

    return total_align
end

function SwitchType:get_align_for_selected_case_field(case_field, start_align, callstack, log)
    local total_align = start_align
    for _, field in ipairs(self.bitcases or {}) do
        local my_callstack = {}
        for _,v in ipairs(callstack) do table.insert(my_callstack, v) end
        table.insert(my_callstack, field)

        if not field.wire then goto continue_case_field end
        if field == case_field then
            local after_field_align = field.type:get_alignment_after(total_align, my_callstack, log)
            if log ~= nil then
                if after_field_align == nil then
                    log:fail(total_align, field.field_name, field.type, my_callstack, "invalid aligment for this case branch")
                else
                    log:ok(total_align, field.field_name, field.type, my_callstack, after_field_align)
                end
            end
            total_align = after_field_align
        elseif field.type.is_bitcase then
            local after_field_align = field.type:get_alignment_after(total_align, my_callstack, log)
            if after_field_align == nil then
                if log ~= nil then
                    log:fail(total_align, field.field_name, field.type, my_callstack, "invalid aligment for this bitcase branch")
                end
                total_align = nil
            else
                if log ~= nil then
                    log:ok(total_align, field.field_name, field.type, my_callstack, after_field_align)
                end
                total_align = total_align:combine_with(after_field_align)
            end
        else
            -- ignore other fields
        end

        if total_align == nil then break end
        ::continue_case_field::
    end
    return total_align
end

-- CaseOrBitcaseType
local CaseOrBitcaseType = {}
CaseOrBitcaseType.__index = CaseOrBitcaseType
setmetatable(CaseOrBitcaseType, { __index = ComplexType })

function CaseOrBitcaseType.new(index, name, elt, ...)
    -- parse enumref children first
    local elts = elt.children or {}
    local self = ComplexType.new(name, elt)
    setmetatable(self, CaseOrBitcaseType)
    self.expr = {}
    for i = #elts, 1, -1 do
        local sub_elt = elts[i]
        if sub_elt.tag == "enumref" then
            table.insert(self.expr, expr_mod.Expression.new(sub_elt, self))
            -- Python removed the enumref from elt; skip mutating elt here
        end
    end
    self.has_name = true
    self.index = 1
    self.lenfield_parent = { ...( ) } -- placeholder replaced below
    -- In original Python, lenfield_parent = list(parent) + [self]
    self.parents = {...}
    self.is_case_or_bitcase = true
    -- fix lenfield_parent properly
    self.lenfield_parent = {}
    for _,p in ipairs(self.parents) do table.insert(self.lenfield_parent, p) end
    table.insert(self.lenfield_parent, self)
    return self
end

function CaseOrBitcaseType:make_member_of(module, switch_type, field_type, field_name, visible, wire, auto, enum)
    local new_field = expr_mod.Field.new(self, field_type, field_name, visible, wire, auto, enum)
    -- Dump _placeholder_byte if any bitcases are added.
    for idx, field in ipairs(switch_type.bitcases) do
        if field == _placeholder_byte then
            switch_type.bitcases[idx] = new_field
            new_field.parent = switch_type
            return
        end
    end
    table.insert(switch_type.bitcases, new_field)
    new_field.parent = switch_type
end

function CaseOrBitcaseType:resolve(module)
    if self.resolved then return end
    for _, e in ipairs(self.expr or {}) do
        e:resolve(module, (function() local p = {}; for _,x in ipairs(self.parents) do table.insert(p, x) end; return p end)())
    end
    -- Resolve the bitcase expression
    ComplexType.resolve(self, module)
    self:calc_or_check_required_start_align()
end

-- BitcaseType
local BitcaseType = {}
BitcaseType.__index = BitcaseType
setmetatable(BitcaseType, { __index = CaseOrBitcaseType })

function BitcaseType.new(index, name, elt, ...)
    local self = CaseOrBitcaseType.new(index, name, elt, ...)
    setmetatable(self, BitcaseType)
    self.is_bitcase = true
    return self
end

-- CaseType
local CaseType = {}
CaseType.__index = CaseType
setmetatable(CaseType, { __index = CaseOrBitcaseType })

function CaseType.new(index, name, elt, ...)
    local self = CaseOrBitcaseType.new(index, name, elt, ...)
    setmetatable(self, CaseType)
    self.is_case = true
    return self
end

-- Reply
local Reply = {}
Reply.__index = Reply
setmetatable(Reply, { __index = ComplexType })

function Reply.new(name, elt)
    local self = ComplexType.new(name, elt)
    setmetatable(self, Reply)
    self.is_reply = true
    self.doc = nil
    if self.required_start_align == nil then
        self.required_start_align = Alignment.new(4,0)
    end
    for _, child in ipairs(elt.children or {}) do
        if child.tag == "doc" then
            self.doc = require("xcbgen.xtypes").Doc and require("xcbgen.xtypes").Doc.new(name, child) or nil
        end
    end
    return self
end

function Reply:resolve(module)
    if self.resolved then return end
    module.pads = 0
    table.insert(self.fields, expr_mod.Field.new(tcard8, tcard8.name, "response_type", false, true, true))
    table.insert(self.fields, _placeholder_byte)
    table.insert(self.fields, expr_mod.Field.new(tcard16, tcard16.name, "sequence", false, true, true))
    table.insert(self.fields, expr_mod.Field.new(tcard32, tcard32.name, "length", false, true, true))
    ComplexType.resolve(self, module)
end

-- Request
local Request = {}
Request.__index = Request
setmetatable(Request, { __index = ComplexType })

function Request.new(name, elt)
    local self = ComplexType.new(name, elt)
    setmetatable(self, Request)
    self.reply = nil
    self.doc = nil
    self.opcode = elt.attr and elt.attr.opcode
    if self.required_start_align == nil then
        self.required_start_align = Alignment.new(4,0)
    end
    for _, child in ipairs(elt.children or {}) do
        if child.tag == "reply" then
            self.reply = Reply.new(name, child)
        elseif child.tag == "doc" then
            self.doc = require("xcbgen.xtypes").Doc and require("xcbgen.xtypes").Doc.new(name, child) or nil
        end
    end
    return self
end

function Request:resolve(module)
    if self.resolved then return end
    if module.namespace.is_ext then
        table.insert(self.fields, expr_mod.Field.new(tcard8, tcard8.name, "major_opcode", false, true, true))
        table.insert(self.fields, expr_mod.Field.new(tcard8, tcard8.name, "minor_opcode", false, true, true))
        table.insert(self.fields, expr_mod.Field.new(tcard16, tcard16.name, "length", false, true, true))
        ComplexType.resolve(self, module)
    else
        table.insert(self.fields, expr_mod.Field.new(tcard8, tcard8.name, "major_opcode", false, true, true))
        table.insert(self.fields, _placeholder_byte)
        table.insert(self.fields, expr_mod.Field.new(tcard16, tcard16.name, "length", false, true, true))
        ComplexType.resolve(self, module)
    end

    if self.reply then
        self.reply:resolve(module)
    end
end

-- EventStructAllowedRule
local EventStructAllowedRule = {}
EventStructAllowedRule.__index = EventStructAllowedRule

function EventStructAllowedRule.new(parent, elt)
    local self = setmetatable({}, EventStructAllowedRule)
    self.elt = elt
    self.extension = elt.attr and elt.attr.extension
    self.ge_events = (elt.attr and elt.attr.xge) == "true"
    self.min_opcode = tonumber(elt.attr and elt.attr["opcode-min"])
    self.max_opcode = tonumber(elt.attr and elt.attr["opcode-max"])
    return self
end

function EventStructAllowedRule:resolve(parent, module)
    local extension_namespace = module:get_namespace(self.extension)
    if extension_namespace == nil then
        error(("EventStructAllowedRule.resolve: cannot find extension \"%s\""):format(self.extension))
        return
    end

    for opcode = self.min_opcode, self.max_opcode do
        local name_and_event = extension_namespace:get_event_by_opcode(opcode, self.ge_events)
        if name_and_event == nil then
            if self.ge_events then
                error(("EventStructAllowedRule.resolve: cannot find xge-event with opcode %d in extension %s"):format(opcode, self.extension))
            else
                error(("EventStructAllowedRule.resolve: cannot find oldstyle-event with opcode %d in extension %s"):format(opcode, self.extension))
            end
            return
        end

        local name, event = name_and_event[1], name_and_event[2]
        parent:add_event(module, self.extension, opcode, name, event)
    end
end

-- EventStruct (Union)
local EventStruct = {}
EventStruct.__index = EventStruct
setmetatable(EventStruct, { __index = (function() return require("xcbgen.xtypes").Union or ComplexType end)() })

function EventStruct.new(name, elt)
    -- We want Union.new behaviour; Union is defined later; use ComplexType.new and set flag
    local self = ComplexType.new(name, elt)
    setmetatable(self, EventStruct)
    self.is_eventstruct = true
    self.events = {}
    self.allowedRules = {}
    self.contains_ge_events = false
    for _, item in ipairs(elt.children or {}) do
        if item.tag == "allowed" then
            local allowedRule = EventStructAllowedRule.new(self, item)
            table.insert(self.allowedRules, allowedRule)
            if allowedRule.ge_events then self.contains_ge_events = true end
        end
    end
    return self
end

function EventStruct:resolve(module)
    if self.resolved then return end
    for _, allowedRule in ipairs(self.allowedRules) do
        allowedRule:resolve(self, module)
    end
    -- Use Union.resolve (Union defined later). We will call ComplexType.resolve here hoping Union behavior not needed strictly.
    ComplexType.resolve(self, module)
    self.resolved = true
end

function EventStruct:add_event(module, extension, opcode, name, event_type)
    table.insert(self.events, { extension, opcode, name, event_type })
    event_type:make_member_of(module, self, name, name[#name], true, true, false)
    event_type:resolve(module)
end

function EventStruct:fixed_size()
    local is_fixed_size = true
    for _, tuple in ipairs(self.events) do
        local event = tuple[4]
        if not event:fixed_size() then is_fixed_size = false end
    end
    return is_fixed_size
end

-- Event (ComplexType)
local Event = {}
Event.__index = Event
setmetatable(Event, { __index = ComplexType })

function Event.new(name, elt)
    local self = ComplexType.new(name, elt)
    setmetatable(self, Event)
    if self.required_start_align == nil then
        self.required_start_align = Alignment.new(4,0)
    end
    self.opcodes = {}
    self.has_seq = not ((elt.attr and elt.attr["no-sequence-number"]) and true or false)
    self.is_ge_event = (elt.attr and elt.attr.xge) and true or false
    self.is_event = true
    self.doc = nil
    for _, item in ipairs(elt.children or {}) do
        if item.tag == "doc" then
            self.doc = require("xcbgen.xtypes").Doc and require("xcbgen.xtypes").Doc.new(name, item) or nil
        end
    end
    return self
end

function Event:add_opcode(opcode, name, main)
    self.opcodes[name] = opcode
    if main then
        self.name = name
    end
end

function Event:get_name_for_opcode(opcode)
    for name, my_opcode in pairs(self.opcodes) do
        if tonumber(my_opcode) == opcode then
            return name
        end
    end
    return nil
end

function Event:resolve(module)
    local function add_event_header()
        table.insert(self.fields, expr_mod.Field.new(tcard8, tcard8.name, "response_type", false, true, true))
        if self.has_seq then
            table.insert(self.fields, _placeholder_byte)
            table.insert(self.fields, expr_mod.Field.new(tcard16, tcard16.name, "sequence", false, true, true))
        end
    end

    local function add_ge_event_header()
        table.insert(self.fields, expr_mod.Field.new(tcard8, tcard8.name, "response_type", false, true, true))
        table.insert(self.fields, expr_mod.Field.new(tcard8, tcard8.name, "extension", false, true, true))
        table.insert(self.fields, expr_mod.Field.new(tcard16, tcard16.name, "sequence", false, true, true))
        table.insert(self.fields, expr_mod.Field.new(tcard32, tcard32.name, "length", false, true, true))
        table.insert(self.fields, expr_mod.Field.new(tcard16, tcard16.name, "event_type", false, true, true))
    end

    if self.resolved then return end

    if self.is_ge_event then
        add_ge_event_header()
    else
        add_event_header()
    end

    ComplexType.resolve(self, module)
end

-- Error (ComplexType)
local Error = {}
Error.__index = Error
setmetatable(Error, { __index = ComplexType })

function Error.new(name, elt)
    local self = ComplexType.new(name, elt)
    setmetatable(self, Error)
    self.opcodes = {}
    if self.required_start_align == nil then
        self.required_start_align = Alignment.new(4,0)
    end

    -- Invent missing parts if the XML omitted them
    local count_children = # (self.elt.children or {})
    if count_children < 1 then
        table.insert(self.elt.children, 1, { tag = "field", attr = { type = "CARD32", name = "bad_value" }, children = {} })
    end
    if count_children < 2 then
        table.insert(self.elt.children, 2, { tag = "field", attr = { type = "CARD16", name = "minor_opcode" }, children = {} })
    end
    if count_children < 3 then
        table.insert(self.elt.children, 3, { tag = "field", attr = { type = "CARD8", name = "major_opcode" }, children = {} })
    end

    return self
end

function Error:add_opcode(opcode, name, main)
    self.opcodes[name] = opcode
    if main then self.name = name end
end

function Error:resolve(module)
    if self.resolved then return end
    table.insert(self.fields, expr_mod.Field.new(tcard8, tcard8.name, "response_type", false, true, true))
    table.insert(self.fields, expr_mod.Field.new(tcard8, tcard8.name, "error_code", false, true, true))
    table.insert(self.fields, expr_mod.Field.new(tcard16, tcard16.name, "sequence", false, true, true))
    ComplexType.resolve(self, module)
end

-- Doc
local Doc = {}
Doc.__index = Doc

function Doc.new(name, elt)
    local self = setmetatable({}, Doc)
    self.name = name
    self.description = nil
    self.brief = "BRIEF DESCRIPTION MISSING"
    self.fields = {}
    self.errors = {}
    self.see = {}
    self.example = nil

    for _, child in ipairs(elt.children or {}) do
        local text = child.text or ""
        if child.tag == "description" then
            self.description = (text and text:match("^%s*(.-)%s*$")) or nil
        elseif child.tag == "brief" then
            self.brief = (text and text:match("^%s*(.-)%s*$")) or self.brief
        elseif child.tag == "field" then
            if child.attr and child.attr.name then
                self.fields[child.attr.name] = text:match("^%s*(.-)%s*$") or ""
            end
        elseif child.tag == "error" then
            if child.attr and child.attr.type then
                self.errors[child.attr.type] = text:match("^%s*(.-)%s*$") or ""
            end
        elseif child.tag == "see" then
            if child.attr and child.attr.name then
                self.see[child.attr.name] = child.attr.type
            end
        elseif child.tag == "example" then
            self.example = text:match("^%s*(.-)%s*$") or nil
        end
    end

    return self
end

-- _placeholder_byte (Field)
_placeholder_byte = expr_mod.Field.new(PadType.new(nil), tcard8.name, "pad0", false, true, false)

-- Export table
local M = {
    Type = Type,
    PrimitiveType = PrimitiveType,
    SimpleType = SimpleType,
    FileDescriptor = FileDescriptor,
    Enum = Enum,
    ListType = ListType,
    ExprType = ExprType,
    PadType = PadType,
    ComplexType = ComplexType,
    SwitchType = SwitchType,
    CaseOrBitcaseType = CaseOrBitcaseType,
    BitcaseType = BitcaseType,
    CaseType = CaseType,
    Reply = Reply,
    Request = Request,
    EventStructAllowedRule = EventStructAllowedRule,
    EventStruct = EventStruct,
    Event = Event,
    Error = Error,
    Doc = Doc,

    -- builtins
    tcard8 = tcard8,
    tcard16 = tcard16,
    tcard32 = tcard32,
    tcard64 = tcard64,
    tint8 = tint8,
    tint16 = tint16,
    tint32 = tint32,
    tint64 = tint64,
    tchar = tchar,
    tfloat = tfloat,
    tdouble = tdouble,
    tbyte = tbyte,
    tbool = tbool,
    tvoid = tvoid,
}

return M
