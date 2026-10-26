-- Parcel cards of the post offices and parcel posts (registered by parcel_office_station.res.lua and
-- parcel_office_construction.res.lua): the window of the station of a post office, or of the construction of a parcel
-- post, shows the parcel stock like an industry window: the production rule with its cycle and the output stock. The
-- parcels per year follow from the productivity the game script sets (parcel_delivery/production.tl).

local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local content_card = ug_require "::/gui/main/content_card.tl" as ContentCard
local empty_construction_eow = ug_require "::/gui/entity_window/empty_construction/empty_construction_eow.script.tl" as EmptyConstructionEow
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil
local entity_window_util = ug_require "::/gui/entity_window/entity_window_util.tl" as EntityWindowUtil
local industry_react_util = ug_require "::/gui/entity_window/industry_react_util.tl" as IndustryReactUtil
local react = ug_require "::/gui/main/react.lua" as React
local station_group_eow = ug_require "::/gui/entity_window/station_group/station_group_eow.script.tl" as StationGroupEow
local warehouse_eow = ug_require "::/gui/entity_window/warehouse/warehouse_eow.script.tl" as WarehouseEow

local production = ug_require "/parcel_delivery/production.tl" as PdProduction

local RefreshInterval <const> = 1.0
--- parts of the resource names of the constructions with a parcel stock
local StockFiles <const> = { "parcel_office.con", "parcel_post.con", "parcel_drop.con", "parcel_drop_range_test.con" }
local DropFile <const> = "parcel_drop.con"

--- the content of the window of a construction without station or industry (empty_construction.tl)
local empty_construction = ug_require "::/gui/entity_window/empty_construction/empty_construction.tl" as Recipe<IEntityWindowParam>

local record PdOfficeEow
	StationParcelsPlugin : Recipe<StationGroupEow.StationGroupWidgetPluginParams>
	ConstructionParcelsPlugin : Recipe<EmptyConstructionEow.EmptyConstructionWidgetPluginParams>
	WarehouseParcelsPlugin : Recipe<WarehouseEow.WarehouseWidgetPluginParams>
	doReplaceFn : function(ReactReplacementApi)
end

local pd_office_eow : PdOfficeEow = {}

local function text(s : string) : TreeNodeId
	return builtin.TextView{ text = s }
end

--- the parcel stock list of a construction of a post office or parcel post, -1 if it is none
local function stockOfConstruction(constructionEntity : Engine.Entity) : Engine.Entity
	if constructionEntity == nil or constructionEntity < 0 then
		return -1
	end
	local construction = api.engine.getComponent(constructionEntity, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
	if construction == nil then
		return -1
	end
	local fileName = tostring(construction.fileName)
	local ours = false
	for _, part in ipairs(StockFiles) do
		if string.find(fileName, part, 1, true) ~= nil then
			ours = true
		end
	end
	if not ours then
		return -1
	end
	for _, sub in ipairs(construction.subconstructions or {}) do
		local stockList = api.engine.getComponent(sub, api.type.ComponentType.STOCK_LIST) as Engine.Component.StockList
		if stockList ~= nil and stockList.stocks ~= nil and #stockList.stocks > 0 then
			return sub
		end
	end
	return -1
end

--- the parcel stock list of the post office a station group belongs to, -1 if it is none
local function stockOfStationGroup(group : Engine.Entity) : Engine.Entity
	local sg = api.engine.getComponent(group, api.type.ComponentType.STATION_GROUP) as Engine.Component.StationGroup
	for _, station in ipairs(sg ~= nil and sg.stations or {}) do
		local stockList = stockOfConstruction(api.engine.system.streetConnectorSystem.getConstructionEntityForStation(station))
		if stockList >= 0 then
			return stockList
		end
	end
	return -1
end

local record StockParam
	stockList : Engine.Entity
end

--- the parcels per year at the productivity the game script set
local ProductionText = react.RegisterRecipe("PdProductionText", function(param : StockParam) : TreeNodeId
	local perYear = engine_react_util.useStepStateTimer(function() : number
		local stockList = api.engine.getComponent(param.stockList, api.type.ComponentType.STOCK_LIST) as Engine.Component.StockList
		local productivity = stockList ~= nil and stockList.modifiers ~= nil and stockList.modifiers.productivity or 0
		return math.floor(productivity * production.RuleCapacity + 0.5)
	end, RefreshInterval):old()
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			industry_react_util.ProductionRulesWidget{
				entity = param.stockList,
				isIndustry = false,
				maxLevel = false,
				failedToExpand = false,
			},
			text(string.format(_("parcel_delivery_office_per_year"), perYear)),
		},
	}
end)

local NoInput = react.RegisterRecipe("PdNoInput", function() : TreeNodeId
	return builtin.BoxLayout{ child = text(_("parcel_delivery_office_input")) }
end)

local NoOutput = react.RegisterRecipe("PdNoOutput", function() : TreeNodeId
	return builtin.BoxLayout{ child = text(_("parcel_delivery_office_output")) }
end)

--- the production card and (unless the window shows the stock itself, like the warehouse window of the drop boxes) the
--- stock card
local function parcelCards(stockList : Engine.Entity, params : EowExtensionUtil.IEowWidgetsExtensionParams, withStock : boolean) : TreeNodeId
	if stockList == nil or stockList < 0 then
		return builtin.BoxLayout{ children = {} }
	end
	local production_card = content_card.ContentCard{
		title = _("parcel_delivery_office_production"),
		initialCalloutTextPermanent = "",
		recipeAndParamPermanent = content_card.makeRecipeAndParam(ProductionText, { stockList = stockList }),
		gameCtx = params.gameCtx,
		showOnRightSide = params.showCalloutOnRightSide,
	}
	if not withStock then
		return builtin.BoxLayout{ child = production_card }
	end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			production_card,
			entity_window_util.CombinedStockGroupedCounts{
				initialCalloutTextInputPermanent = "",
				-- the stock widget needs the expanded parts (entity_window_util.tl indexes them unconditionally)
				initialCalloutTextInputCollapsible = "",
				recipeAndParamInputCollapsible = content_card.makeRecipe0(NoInput),
				initialCalloutTextOutputPermanent = "",
				initialCalloutTextOutputCollapsible = "",
				recipeAndParamOutputCollapsible = content_card.makeRecipe0(NoOutput),
				cardKey = "parcelDeliveryStock",
				setCollapsibleExpanded = params.setCollapsibleExpanded,
				getCollapsibleExpanded = params.getCollapsibleExpanded,
				gameCtx = params.gameCtx,
				showOnRightSide = params.showCalloutOnRightSide,
				showSimplifiedOnly = false,
				entityId = stockList,
			},
		},
	}
end

pd_office_eow.StationParcelsPlugin = react.RegisterPluginRecipe(station_group_eow.StationGroupEowExtensionPoint, "PdStationParcelsPlugin", function(params : StationGroupEow.StationGroupWidgetPluginParams) : TreeNodeId
	local stockList = engine_react_util.useStepStateTimer(function() : Engine.Entity
		local ok, result = pcall(stockOfStationGroup, params.entityId)
		return ok and result as Engine.Entity or -1
	end, RefreshInterval):old()
	return parcelCards(stockList, params, true)
end)

pd_office_eow.ConstructionParcelsPlugin = react.RegisterPluginRecipe(empty_construction_eow.EmptyConstructionEowExtensionPoint, "PdConstructionParcelsPlugin", function(params : EmptyConstructionEow.EmptyConstructionWidgetPluginParams) : TreeNodeId
	local stockList = engine_react_util.useStepStateTimer(function() : Engine.Entity
		local ok, result = pcall(stockOfConstruction, params.entityId)
		return ok and result as Engine.Entity or -1
	end, RefreshInterval):old()
	return parcelCards(stockList, params, true)
end)

--- The parcel drop boxes are built by the warehouse script of the base game (parcel_drop.script.tl), so their window
--- is that of a warehouse; its entity is the warehouse, its subconstruction or the construction.
local function stockOfWarehouse(entity : Engine.Entity) : Engine.Entity
	if api.engine.getComponent(entity, api.type.ComponentType.CONSTRUCTION) ~= nil then
		return stockOfConstruction(entity)
	end
	local warehouse = api.engine.getComponent(entity, api.type.ComponentType.WAREHOUSE) as Engine.Component.Warehouse
	if warehouse ~= nil and warehouse.construction ~= nil and warehouse.construction >= 0 then
		return stockOfConstruction(warehouse.construction)
	end
	return stockOfConstruction(api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction(entity))
end

pd_office_eow.WarehouseParcelsPlugin = react.RegisterPluginRecipe(warehouse_eow.WarehouseEowExtensionPoint, "PdWarehouseParcelsPlugin", function(params : WarehouseEow.WarehouseWidgetPluginParams) : TreeNodeId
	local stockList = engine_react_util.useStepStateTimer(function() : Engine.Entity
		local ok, result = pcall(stockOfWarehouse, params.entityId)
		return ok and result as Engine.Entity or -1
	end, RefreshInterval):old()
	return parcelCards(stockList, params, false)
end)

--- whether a construction is a parcel drop box
local function isDropBox(constructionEntity : Engine.Entity) : boolean
	local construction = constructionEntity ~= nil and constructionEntity >= 0
		and api.engine.getComponent(constructionEntity, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction or nil
	return construction ~= nil and string.find(tostring(construction.fileName), DropFile, 1, true) ~= nil
end

--- The window of a parcel drop box without the close-up view of the construction: empty_construction.tl leaves it out
--- in simple windows, so the drop boxes get a simple window; the other constructions are unchanged.
local EmptyConstructionContent = react.RegisterRecipe("PdEmptyConstructionContent", function(params : IEntityWindowParam) : TreeNodeId
	if not params.simple and isDropBox(params.keyEntity) then
		local shown : table = {}
		for k, v in pairs(params as table) do
			shown[k] = v
		end
		shown.simple = true
		-- the root of a recipe must be a layout
		return builtin.BoxLayout{ child = react.CallOriginalRecipe(empty_construction, shown as IEntityWindowParam) }
	end
	return builtin.BoxLayout{ child = react.CallOriginalRecipe(empty_construction, params) }
end)

function pd_office_eow.doReplaceFn(replacementApi : ReactReplacementApi)
	replacementApi.ReplaceRecipe(empty_construction, EmptyConstructionContent)
	log.message("[parcel_delivery] window of the parcel drop boxes without close-up view")
end

return pd_office_eow
