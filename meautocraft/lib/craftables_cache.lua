local cc_expect = require "cc.expect"
local field = cc_expect.field

local SETTINGS = require "lib.SETTINGS"
local ioutils = require "lib.ioutils"

require "lib.string_functions"

---@class Craftable
---@field item table The raw Minecraft item table
---@field is_fluid boolean
local Craftable = {}
local Craftable_mt = { __metatable = {}, __index = Craftable }

---@param params { item: table, is_fluid: boolean }
function Craftable:new(params)
    local o = setmetatable({}, Craftable_mt)
    o.item = params.item
    o.is_fluid = field(params, "is_fluid", "boolean")
    return o
end

local function normalize_amount(raw)
    -- AP ≤ 0.7.45 used `amount`
    -- AP ≥ 0.7.46 uses `count`
    if type(raw.amount) ~= "number" then
        if type(raw.count) == "number" then
            raw.amount = raw.count
        else
            raw.amount = 0
        end
    end
end


---@return string
function Craftable:name()
    return field(self.item, "name", "string")
end

---@return string
function Craftable:display_name()
    local dn = self.item.displayName

    -- Use displayName only if it looks human (has spaces, etc.)
    -- If it's a translation key / internal id like "material.gtceu.vibrant_alloy_plate",
    -- treat it as "not a real display name" and prettify.
    if type(dn) == "string" and dn ~= "" then
        local looks_like_key =
            (dn:find(" ") == nil) and (dn:find("%.") ~= nil or dn:find(":") ~= nil or dn:find("_") ~= nil)

        if not looks_like_key then
            if dn:startswith("   [") and dn:endswith("]") then
                dn = string.sub(dn, 5, -2)
            end
            return dn
        end
    end

    -- Fallback: prettify internal names/keys
    local key = self:name()
    if type(dn) == "string" and dn ~= "" then
        key = dn -- if displayName exists but is a key, prettify that instead
    end

    -- Strip namespace-ish prefixes:
    key = key:gsub("^[%w_]+:", "")   -- remove "modid:"
    key = key:gsub("^.*%.", "")      -- keep only after last '.' (material.gtceu.x -> x)

    -- Make it readable
    key = key:gsub("_", " ")
    key = key:gsub("(%a)([%w']*)", function(a, b)
        return string.upper(a) .. b
    end)

    return key
end



---@return { [string]: Craftable}
local function load()
    local raw = ioutils.read_file(SETTINGS.craftables_cache_path())
    if not raw then
        return {}
    end

    local data = textutils.unserialize(raw)
    if not data then
        ioutils.panic("Failed to parse craftables cache")
        return {} -- Never reached, just here to satisfy type checker (we don't have a `never` return type)
    end

    for _, craftable in pairs(data) do
        setmetatable(craftable, Craftable_mt)
    end

    return data
end

---@return { [string]: Craftable }
local function update(me_bridge)
    local data = {}

    for _, raw in ipairs(me_bridge.listCraftableItems() or {}) do
        normalize_amount(raw)
        data[field(raw, "name", "string")] = Craftable:new {
            item = raw,
            is_fluid = false
        }
    end

    for _, raw in ipairs(me_bridge.listCraftableFluid() or {}) do
        normalize_amount(raw)
        data[field(raw, "name", "string")] = Craftable:new {
            item = raw,
            is_fluid = true
        }
    end

    local path = SETTINGS.craftables_cache_path()
    local content = textutils.serialize(data, { allow_repetitions = true })
    if not ioutils.write_file(path, content) then
        ioutils.panic("Failed to write craftables cache to " .. path)
        return {}
    end

    return data
end


---@return { [string]: Craftable } | nil
local function get(me_bridge)
    local data = load()
    if not data then
        data = update(me_bridge)
    end
    return data
end

---@param craftables { [string]: Craftable }
---@return { [string]: Craftable }
local function pivot_by_display_name(craftables)
    local by_display_name = {}
    for _, craftable in pairs(craftables) do
        if by_display_name[craftable:display_name()] then
            printError("Duplicate craftable displayName in ME: " ..
                craftable:display_name() ..
                " (" .. craftable:name() .. ", " .. by_display_name[craftable:display_name()]:name() .. ")")
            printError("Using " .. craftable:name())
        end
        by_display_name[craftable:display_name()] = craftable
    end
    return by_display_name
end

return {
    get = get,
    pivot_by_display_name = pivot_by_display_name,
    update = update,
    Craftable = Craftable
}
