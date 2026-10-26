-- Construction of the parcel drop warehouse (parcel_drop_warehouse.con.lua), a trial: the warehouse of the base game
-- (warehouses/warehouse.script.lua, a stations reach it without any street) with the parcel stock and rule of the drop
-- boxes (parcel_delivery/production.tl), placed without collision (skipCollision). It shows whether skipCollision keeps
-- the stations from reaching a construction: the drop box with it was reached by none, the warehouse without it is.
--
-- The base script builds the stocks of the warehouse in a hook run after the modules (terminateConstructionHook): the
-- parcel stock is added to the warehouse subconstruction after it, and the resource names of the base script made
-- absolute (they are resolved in this mod otherwise).

local util = ug_require "::/scripts/util.tl" as Util
local production = ug_require "/parcel_delivery/production.tl" as PdProduction

local BaseUpdate <const> = "::/warehouses/warehouse.script@updateFn"
local WarehouseDir <const> = "::/warehouses/"
--- the goods warehouse module of the base game in the first slot of the warehouse template (EncodeSlotId of
--- warehouse.script.lua for x = 0, y = 3, warehouse_large)
local InitialSlot <const> = 10 * (250000 * (3 + 250) + (0 + 250)) + 0
local InitialModule <const> = "::/warehouses/wh_goods.module"

--- resource names of the base script made absolute: "/x" becomes "::/x", "x" becomes "::/warehouses/x"
local function absolutize(t : table, seen : {table : boolean})
	if seen[t] then
		return
	end
	seen[t] = true
	for key, value in pairs(t) do
		if type(value) == "string" then
			local s = value as string
			local resource = string.find(s, "%.mdl$") ~= nil or string.find(s, "%.gtex$") ~= nil or string.find(s, "%.mtl$") ~= nil
			if resource and string.sub(s, 1, 2) ~= "::" and string.find(s, "::", 1, true) == nil then
				t[key] = string.sub(s, 1, 1) == "/" and ("::" .. s) or (WarehouseDir .. s)
			end
		elseif type(value) == "table" then
			absolutize(value as table, seen)
		end
	end
end

local script = {}

function script.createTemplateFn(_captureParams : table, _params : table) : table
	return { [InitialSlot] = InitialModule }
end

function script.updateFn(captureParams : table, params : table) : table
	local base = util.useFn(BaseUpdate) as function(table, table) : table
	local result = base(captureParams, params)
	if result == nil then
		return result
	end
	local hook = result.terminateConstructionHook as function()
	result.terminateConstructionHook = function()
		if hook ~= nil then
			hook()
		end
		local ok, err = pcall(function() : boolean
			local sub = (result.subconstructions as {table})[1]
			local stocks = (sub.stocks or {}) as {table}
			for _, stock in ipairs(production.stocks()) do
				table.insert(stocks, stock)
			end
			sub.stocks = stocks
			-- the input vector of a rule counts the input stocks, the warehouse has none
			local rules = (sub.rules or {}) as {table}
			for _, rule in ipairs(production.rules()) do
				table.insert(rules, rule)
			end
			sub.rules = rules
			local metadata = (sub.metadata or {}) as table
			metadata[production.DropMetadata] = true
			sub.metadata = metadata
			absolutize(result, {})
			return true
		end)
		if not ok then
			print("[parcel_delivery] drop warehouse: adding the parcel stock failed: " .. tostring(err))
		end
	end
	absolutize(result, {})
	return result
end

return script
