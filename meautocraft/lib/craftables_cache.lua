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

    if type(dn) == "string" and dn ~= "" then
        -- strip the weird GTCEu prefix if present
        dn = dn:gsub("^material%.gtceu%.", "")

        -- turn energetic_alloy -> Energetic Alloy
        dn = dn:gsub("_", " ")

        -- Title-case words
        dn = dn:gsub("(%a)([%w']*)", function(a, b)
            return a:upper() .. b
        end)

        -- Keep your bracket cleanup (optional; harmless)
        if dn:startswith("   [") and dn:endswith("]") then
            dn = string.sub(dn, 5, -2)
        end

        return dn
    end

    -- fallback if displayName missing
    local key = self:name()
    key = key:gsub("^material%.gtceu%.", "")
    key = key:gsub("^[%w_]+:", "")
    key = key:gsub("_", " ")
    key = key:gsub("(%a)([%w']*)", function(a, b)
        return a:upper() .. b
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
