--[[
This module contains the namespace class and the singleton module class.
]]

local lom = require("lxp.lom")
local matcher = require("xcbgen.matcher")
local error_mod = require("xcbgen.error")
local xtypes = require("xcbgen.xtypes")

local function dirname(path)
    local i = path:match(".*[/\\]")
    if i then
        return path:sub(1, i-1)
    end
    return "."
end

local function basename(path)
    local i = path:match(".*[/\\]")
    if i then
        return path:sub(i+1)
    end
    return path
end

local Namespace = {}
Namespace.__index = Namespace

function Namespace.new(filename)
    local self = setmetatable({}, Namespace)

    self.path = filename
    self.dir = dirname(filename)
    self.file = basename(filename)

    -- Use lxp.lom like ElementTree.parse(...).getroot()
    local root = lom.parsefile(filename)
    self.root = root

    self.header = (root.attr and root.attr.header) or ""
    self.ns = self.header .. ":"

    self.events = {}

    -- Extension metadata
    if root.attr and root.attr["extension-xname"] then
        self.is_ext = true
        self.major_version = root.attr["major-version"]
        self.minor_version = root.attr["minor-version"]
        self.ext_xname = root.attr["extension-xname"]
        self.ext_name = root.attr["extension-name"]
        self.prefix = { "xcb", self.ext_name }
    else
        self.is_ext = false
        self.ext_name = ""
        self.prefix = { "xcb" }
    end

    return self
end

function Namespace.add_event(self, id, name, item)
    self.events[id] = { name, item }
end

function Namespace.get_event_by_opcode(self, opcode, is_ge_event)
    for id, pair in pairs(self.events) do
        local name, event = pair[1], pair[2]
        if event.is_ge_event == is_ge_event then
            local opcode_specific_name = event:get_name_for_opcode(opcode)
            if opcode_specific_name ~= nil then
                return opcode_specific_name, event
            end
        end
    end
    return nil
end

local Module = {}
Module.__index = Module

function Module.new(filename, output)
    local self = setmetatable({}, Module)

    self.namespace = Namespace.new(filename)
    self.output = output

    self.imports = {}
    self.direct_imports = {}
    self.import_level = 0
    self.types = {}
    self.events = {}
    self.errors = {}
    self.all = {}
    self.namespaces = {}
    self.namespaces[self.namespace.ext_name] = self.namespace

    -- register builtins
    self:add_type("CARD8", "", { "uint8_t" }, xtypes.tcard8)
    self:add_type("CARD16", "", { "uint16_t" }, xtypes.tcard16)
    self:add_type("CARD32", "", { "uint32_t" }, xtypes.tcard32)
    self:add_type("CARD64", "", { "uint64_t" }, xtypes.tcard64)
    self:add_type("INT8", "", { "int8_t" }, xtypes.tint8)
    self:add_type("INT16", "", { "int16_t" }, xtypes.tint16)
    self:add_type("INT32", "", { "int32_t" }, xtypes.tint32)
    self:add_type("INT64", "", { "int64_t" }, xtypes.tint64)
    self:add_type("BYTE", "", { "uint8_t" }, xtypes.tbyte)
    self:add_type("BOOL", "", { "uint8_t" }, xtypes.tbool)
    self:add_type("char", "", { "char" }, xtypes.tchar)
    self:add_type("float", "", { "float" }, xtypes.tfloat)
    self:add_type("double", "", { "double" }, xtypes.tdouble)
    self:add_type("void", "", { "void" }, xtypes.tvoid)

    return self
end

function Module.register(self)
    matcher.execute(self, self.namespace)
end

function Module.resolve(self)
    self:add_events_to_namespaces()
    for _, item in ipairs(self.all) do
        local name, obj = item[1], item[2]
        self.pads = 0
        obj:resolve(self)
    end
end

function Module.generate(self)
    self.output.open()
    for _, item in ipairs(self.all) do
        local name, obj = item[1], item[2]
        obj:out(name)
    end
    self.output.close()
end

function Module.add_import(self, name, namespace)
    if self.import_level == 0 then
        table.insert(self.direct_imports, { name, namespace.header })
    end
    table.insert(self.imports, { name, namespace.header })
    self.namespaces[namespace.ext_name] = namespace
end

function Module.has_import(self, name)
    for _, pair in ipairs(self.imports) do
        if pair[1] == name then
            return true end
    end
    return false
end

function Module.add_type(self, id, ns, name, item)
    local key = ns .. id
    if self.types[key] ~= nil then
        return
    end
    self.types[key] = { name, item }

    -- if type name is in the current namespace prefix
    local prefix_name = table.concat(name, ".")
    if prefix_name:sub(1, 4) == "xcb." then
        table.insert(self.all, { name, item })
    end
end

function Module.get_type_impl(self, id, idx)
    -- 1 = name, 2 = item
    local key = id
    if self.types[key] ~= nil then
        return self.types[key][idx]
    end

    local ns_key = self.namespace.ns .. id
    if self.types[ns_key] ~= nil then
        return self.types[ns_key][idx]
    end

    for k, v in pairs(self.types) do
        local right = k:match(":(.*)$")
        if right and right == id then
            return v[idx]
        end
    end

    error(("Type %s not found"):format(tostring(id)))
end

function Module.get_type(self, id)
    return self.get_type_impl(self, id, 2)
end

function Module.get_type_name(self, id)
    return self.get_type_impl(self, id, 1)
end

function Module.get_namespace(self, ext_name)
    return self.namespaces[ext_name]
end

function Module.add_request(self, id, name, item)
    local prefix_name = table.concat(name, ".")
    if prefix_name:sub(1, 4) == "xcb." then
        table.insert(self.all, { name, item })
    end
end

function Module.add_event(self, id, name, item)
    self.events[id] = { name, item }
    local prefix_name = table.concat(name, ".")
    if prefix_name:sub(1, 4) == "xcb." then
        table.insert(self.all, { name, item })
    end
end

function Module.add_events_to_namespaces(self)
    for id, pair in pairs(self.events) do
        local name, item = pair[1], pair[2]
        local namespace_name = ""
        if name[1] == "xcb" and #name > 1 then
            namespace_name = name[#name-1] or ""
        end
        local namespace = self.namespaces[namespace_name]
        if namespace ~= nil then
            namespace:add_event(id, name, item)
        end
    end
end

function Module.get_event(self, id)
    return self.events[id][2]
end

function Module.add_error(self, id, name, item)
    self.errors[id] = { name, item }
    local prefix_name = table.concat(name, ".")
    if prefix_name:sub(1, 4) == "xcb." then
        table.insert(self.all, { name, item })
    end
end

function Module.get_error(self, id)
    return self.errors[id][2]
end

return {
    Namespace = Namespace,
    Module = Module,
}
