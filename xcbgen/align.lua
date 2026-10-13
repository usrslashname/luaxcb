-- Helper function to calculate Greatest Common Divisor (GCD)
local function gcd(a, b)
    while b ~= 0 do
        a, b = b, a % b
    end
    return math.abs(a)
end

-- Helper function to check if array profiles match (replaces Python's zip/all)
local function is_subset(ok_stack, fail_stack)
    if #ok_stack > #fail_stack then return false end
    for i = 1, #ok_stack do
        if tostring(ok_stack[i]) ~= tostring(fail_stack[i]) then
            return false
        end
    end
    return true
end

-------------------------------------------------------------------------------
-- Alignment Class
-------------------------------------------------------------------------------
local Alignment = {}
Alignment.__index = Alignment

function Alignment.new(align, offset)
    local self = setmetatable({}, Alignment)
    self.align = align or 4
    self.offset = (offset or 0) % self.align
    return self
end

function Alignment:__eq(other)
    return self.align == other.align and self.offset == other.offset
end

function Alignment:__tostring()
    return string.format("(align=%d, offset=%d)", self.align, self.offset)
end

function Alignment.for_primitive_type(size)
    if size % 8 == 0 then
        return Alignment.new(8, 0)
    elseif size % 4 == 0 then
        return Alignment.new(4, 0)
    elseif size % 2 == 0 then
        return Alignment.new(2, 0)
    else
        return Alignment.new(1, 0)
    end
end

function Alignment:align_after_fixed_size(size)
    local new_offset = (self.offset + size) % self.align
    return Alignment.new(self.align, new_offset)
end

function Alignment:is_guaranteed_at(external_align)
    if self.align == 1 and self.offset == 0 then
        return true
    end

    if not external_align then
        return false
    end

    if external_align.align < self.align then
        return false
    end

    if external_align.align % self.align ~= 0 then
        return false
    end

    if external_align.offset % self.align ~= self.offset then
        return false
    end

    return true
end

function Alignment:combine_with(other)
    local new_align = gcd(self.align, other.align)
    local new_offset_candidate1 = self.offset % new_align
    local new_offset_candidate2 = other.offset % new_align

    if new_offset_candidate1 == new_offset_candidate2 then
        local new_offset = new_offset_candidate1
        return Alignment.new(new_align, new_offset)
    else
        local offset_diff = math.abs(new_offset_candidate2 - new_offset_candidate1)
        new_align = gcd(new_align, offset_diff)
        new_offset_candidate1 = self.offset % new_align
        new_offset_candidate2 = other.offset % new_align
        assert(new_offset_candidate1 == new_offset_candidate2, "Offsets must match after reduction")
        local new_offset = new_offset_candidate1
        return Alignment.new(new_align, new_offset)
    end
end

-------------------------------------------------------------------------------
-- AlignmentLog Class
-------------------------------------------------------------------------------
local AlignmentLog = {}
AlignmentLog.__index = AlignmentLog

function AlignmentLog.new()
    local self = setmetatable({}, AlignmentLog)
    self.ok_list = {}
    self.fail_list = {}
    self.verbosity = 1
    return self
end

function AlignmentLog:callstack_to_str(indent, callstack)
    local result = string.format("\t%scallstack: [\n", indent)
    for _, stack_elem in ipairs(callstack) do
        result = result .. string.format("\t  %s%s\n", indent, tostring(stack_elem))
    end
    result = result .. string.format("\t%s]\n", indent)
    return result
end

function AlignmentLog:ok_callstack_is_relevant(ok_callstack)
    if self.verbosity >= 2 then
        return true
    end

    if #ok_callstack == 0 then
        return true
    end

    for _, fail_entry in ipairs(self.fail_list) do
        local fail_callstack = fail_entry.callstack
        if is_subset(ok_callstack, fail_callstack) then
            return true
        end
    end

    return false
end

function AlignmentLog:__tostring()
    local result = ""

    -- Output the OK-list
    for _, entry in ipairs(self.ok_list) do
        local stacksize = #entry.callstack
        local indent = string.rep('  ', stacksize)
        if self:ok_callstack_is_relevant(entry.callstack) then
            if not entry.field_name or entry.field_name == "" then
                result = result .. string.format("    %sok: %s:\n\t%sbefore: %s, after: %s\n",
                    indent, tostring(entry.type_obj), indent, tostring(entry.align_before), tostring(entry.align_after))
            else
                result = result .. string.format("    %sok: field \"%s\" in %s:\n\t%sbefore: %s, after: %s\n",
                    indent, tostring(entry.field_name), tostring(entry.type_obj),
                    indent, tostring(entry.align_before), tostring(entry.align_after))
            end
            if self.verbosity >= 1 then
                result = result .. self:callstack_to_str(indent, entry.callstack)
            end
        end
    end

    -- Output the fail-list
    for _, entry in ipairs(self.fail_list) do
        local stacksize = #entry.callstack
        local indent = string.rep('  ', stacksize)
        if not entry.field_name or entry.field_name == "" then
            result = result .. string.format("    %sfail: align %s is incompatible with\n\t%s%s\n\t%sReason: %s\n",
                indent, tostring(entry.align_before), indent, tostring(entry.type_obj), indent, entry.reason)
        else
            result = result .. string.format("    %sfail: align %s is incompatible with\n\t%sfield \"%s\" in %s\n\t%sReason: %s\n",
                indent, tostring(entry.align_before), indent, tostring(entry.field_name), tostring(entry.type_obj), indent, entry.reason)
        end

        if self.verbosity >= 1 then
            result = result .. self:callstack_to_str(indent, entry.callstack)
        end
    end

    return result
end

function AlignmentLog:ok(align_before, field_name, type_obj, callstack, align_after)
    table.insert(self.ok_list, {
        align_before = align_before,
        field_name = field_name,
        type_obj = type_obj,
        callstack = callstack,
        align_after = align_after
    })
end

function AlignmentLog:fail(align_before, field_name, type_obj, callstack, reason)
    table.insert(self.fail_list, {
        align_before = align_before,
        field_name = field_name,
        type_obj = type_obj,
        callstack = callstack,
        reason = reason
    })
end

function AlignmentLog:append(other)
    for _, entry in ipairs(other.ok_list) do
        table.insert(self.ok_list, entry)
    end
    for _, entry in ipairs(other.fail_list) do
        table.insert(self.fail_list, entry)
    end
end

function AlignmentLog:ok_count()
    return #self.ok_list
end

return {
    Alignment = Alignment,
    AlignmentLog = AlignmentLog
}
