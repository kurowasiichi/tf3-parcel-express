-- Construction of the intercity parcel sorting centers (parcel_sorting_export.con.lua, parcel_sorting_import.con.lua):
-- the goods warehouse of the base game (warehouses/warehouse.script.lua with one goods module) without its warehouse,
-- with the stocks and the rule of a sorting center (parcel_delivery/production.tl) and the workplaces of an industry. It
-- is built next to a train station or an airport: the stations whose catchment covers it load and unload its stocks,
-- like those of an industry.
--
-- - export: takes the parcels of the town and gives intercity parcels
-- - import: takes the intercity parcels and gives parcels for the residential districts
--
-- The warehouse is built here as the construction script builds it for the player (scripts/construction/
-- construction.script.tl, constructWithModules): the update of the warehouse, the goods module in its first slot, then
-- the hook of the warehouse. Only the parts the game reads are returned: no slots (no modules can be added), no
-- warehouse and no storage stock. The stock models of the goods module show the stocks of the sorting center. The
-- resource names of the base scripts are made absolute (they are resolved in this mod otherwise).

local util = ug_require "::/scripts/util.tl" as Util
local production = ug_require "/parcel_delivery/production.tl" as PdProduction

local BaseUpdate <const> = "::/warehouses/warehouse.script@updateFn"
local GoodsModuleUpdate <const> = "::/warehouses/modules.script@goods.updateFn"
local BaseDir <const> = "::/warehouses/"
--- the goods module in the first slot of the warehouse template (EncodeSlotId of warehouse.script.lua for x = 0,
--- y = 3, warehouse_large), and the metadata of wh_goods.module the warehouse reads
local ModuleSlot <const> = 10 * (250000 * (3 + 250) + (0 + 250)) + 0
local ModuleMetadata <const> = { type = "goods", emissionConfig = { noise = 20, pollution = 50 } }
local ImportKind <const> = "import"
local Cost <const> = 180000
local MaintenanceCost <const> = 30000

local record Params
	--- "export" or "import" (the construction file gives it)
	kind : string
end

local type ModuleUpdateFn = function(table, table, table, string, integer, any, table)

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
				t[key] = string.sub(s, 1, 1) == "/" and ("::" .. s) or (BaseDir .. s)
			end
		elseif type(value) == "table" then
			absolutize(value as table, seen)
		end
	end
end

--- the stock models of the goods module: the load indicators of its storage stock (added by the hook of the warehouse)
local function loadIndicators(sub : table) : {integer}
	for _, stock in ipairs((sub.stocks or {}) as {table}) do
		if stock.loadIndicators ~= nil and stock.tag ~= nil then
			return stock.loadIndicators as {integer}
		end
	end
	return {}
end

local script = {}

function script.createTemplateFn(_captureParams : table, _params : table) : table
	return {}
end

function script.updateFn(captureParams : Params, params : table) : table
	local moduleParams : table = {}
	for key, value in pairs(params) do
		moduleParams[key] = value
	end
	moduleParams.seed = tonumber(params.seed) or 0
	moduleParams.modules = { [ModuleSlot] = { metadata = ModuleMetadata } }

	local base = util.useFn(BaseUpdate) as function(table, table) : table
	local warehouse = base({}, moduleParams)
	if warehouse == nil then
		return warehouse
	end
	local goods = util.useFn(GoodsModuleUpdate) as ModuleUpdateFn
	goods({}, warehouse, nil, "__module_" .. tostring(ModuleSlot), ModuleSlot, nil, moduleParams)
	local hook = warehouse.terminateConstructionHook as function()
	if hook ~= nil then
		hook()
	end

	local export = captureParams == nil or captureParams.kind ~= ImportKind
	local sub = (warehouse.subconstructions as {table})[1]
	-- the stock models of the module: the first half shows the input stock, the second half the output stock
	local indicators = loadIndicators(sub)
	local half = math.floor(#indicators / 2)
	local stocks = production.sortingStocks(export)
	stocks[1].loadIndicators = { table.unpack(indicators, 1, half) }
	stocks[2].loadIndicators = { table.unpack(indicators, half + 1) }
	sub.warehouse = nil
	sub.stocks = stocks
	sub.rules = production.sortingRules(export)
	-- the workplaces of an industry (industries/industryutil.lua): the workers come by the lines
	sub.personCapacity = {
		type = "INDUSTRIAL",
		capacity = production.SortingWorkers,
		destinationWeight = 2.0,
		disallowedMoveModes = { "WALK", "DRIVE" },
	}
	local metadata = (sub.metadata or {}) as table
	-- the game script and the window find the sorting centers by this key (forEachConstructionWithMetadata)
	metadata[production.SortingMetadata] = true
	sub.metadata = metadata

	local result : table = {
		subconstructions = { sub },
		snapPoint = warehouse.snapPoint,
		cost = Cost,
		maintenanceCost = MaintenanceCost,
		-- the boost of the workers (industry_productivity_util.tl, getPersonCapacityPotentialBoost): fixed, not random
		metadata = { workersBoostFactor = production.SortingBoostFactor },
	}
	absolutize(result, {})
	return result
end

return script
