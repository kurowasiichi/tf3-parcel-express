-- Cards of the intercity parcel sorting centers (registered by parcel_sorting_construction.res.lua): the window of a
-- sorting center is that of a construction without station or industry, and shows the cards of an industry window
-- (gui/entity_window/industry/industry_eow.script.tl) with the widgets of the base game: production, boosters (the
-- workers, with the table of the workplaces) and the input and output stocks.

local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local content_card = ug_require "::/gui/main/content_card.tl" as ContentCard
local empty_construction_eow = ug_require "::/gui/entity_window/empty_construction/empty_construction_eow.script.tl" as EmptyConstructionEow
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil
local entity_window_util = ug_require "::/gui/entity_window/entity_window_util.tl" as EntityWindowUtil
local industry_react_util = ug_require "::/gui/entity_window/industry_react_util.tl" as IndustryReactUtil
local react = ug_require "::/gui/main/react.lua" as React

local production = ug_require "/parcel_delivery/production.tl" as PdProduction

local RefreshInterval <const> = 1.0
--- part of the resource names of the sorting centers (parcel_sorting_export.con, parcel_sorting_import.con)
local SortingFile <const> = "parcel_sorting_"
local BoostersCardKey <const> = "parcelSortingBoosters"

local record PdSortingEow
	SortingPlugin : Recipe<EmptyConstructionEow.EmptyConstructionWidgetPluginParams>
end

local pd_sorting_eow : PdSortingEow = {}

local function text(s : string) : TreeNodeId
	return builtin.TextView{ text = s }
end

--- the stock list of a sorting center, -1 if the construction is none
local function stockOfSorting(constructionEntity : Engine.Entity) : Engine.Entity
	if constructionEntity == nil or constructionEntity < 0 then
		return -1
	end
	local construction = api.engine.getComponent(constructionEntity, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
	if construction == nil or string.find(tostring(construction.fileName), SortingFile, 1, true) == nil then
		return -1
	end
	for _, sub in ipairs(construction.subconstructions or {}) do
		if api.engine.getComponent(sub, api.type.ComponentType.STOCK_LIST) ~= nil then
			return sub
		end
	end
	return -1
end

local record StockParam
	stockList : Engine.Entity
end

--- the rule of the stock list and the parcels per year at its productivity (1, or the workers boost)
local ProductionContent = react.RegisterRecipe("PdSortingProduction", function(param : StockParam) : TreeNodeId
	local perYear = engine_react_util.useStepStateTimer(function() : number
		local stockList = api.engine.getComponent(param.stockList, api.type.ComponentType.STOCK_LIST) as Engine.Component.StockList
		local productivity = stockList ~= nil and stockList.modifiers ~= nil and stockList.modifiers.productivity or 1
		return math.floor(productivity * production.SortingRuleCapacity + 0.5)
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
			text(string.format(_("parcel_delivery_sorting_per_year"), perYear)),
		},
	}
end)

--- the workers row of the boosters card, as in the industry window (IndustryBoosters)
local WorkersBooster = react.RegisterRecipe("PdSortingWorkersBooster", function(param : StockParam) : TreeNodeId
	local boosted = engine_react_util.useStepStateTimer(function() : boolean
		return industry_react_util.isPersonCapacityBoosted(param.stockList) == true
	end, RefreshInterval):old()
	return builtin.BoxLayout{
		child = builtin.Component{
			meta = {
				class = "booster-widget",
			},
			layout = builtin.TableLayout{
				rows = { industry_react_util.WorkplacesBoosterRow{ entity = param.stockList, boosted = boosted } },
				columnWeights = { -1, 50, -1, 10 },
			},
		},
	}
end)

local InputInfo = react.RegisterRecipe("PdSortingInputInfo", function() : TreeNodeId
	return builtin.BoxLayout{ child = text(_("parcel_delivery_sorting_input")) }
end)

local OutputInfo = react.RegisterRecipe("PdSortingOutputInfo", function() : TreeNodeId
	return builtin.BoxLayout{ child = text(_("parcel_delivery_sorting_output")) }
end)

local function sortingCards(stockList : Engine.Entity, params : EmptyConstructionEow.EmptyConstructionWidgetPluginParams) : TreeNodeId
	if stockList == nil or stockList < 0 then
		return builtin.BoxLayout{ children = {} }
	end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			content_card.ContentCard{
				title = _("Production"),
				initialCalloutTextPermanent = "",
				recipeAndParamPermanent = content_card.makeRecipeAndParam(ProductionContent, { stockList = stockList }),
				gameCtx = params.gameCtx,
				showOnRightSide = params.showCalloutOnRightSide,
			},
			content_card.ContentCard{
				title = _(nGetText("Booster", "Boosters", 1)),
				initialCalloutTextPermanent = "",
				recipeAndParamPermanent = content_card.makeRecipeAndParam(WorkersBooster, { stockList = stockList }),
				initialCalloutTextCollapsible = "",
				recipeAndParamCollapsible = content_card.makeRecipeAndParam(entity_window_util.WorkersTable,
					{ personCapacityEntityId = stockList }),
				setCollapsibleExpanded = function(v : boolean) params.setCollapsibleExpanded(BoostersCardKey, v) end,
				collapsibleExpanded = params.getCollapsibleExpanded(BoostersCardKey),
				gameCtx = params.gameCtx,
				showOnRightSide = params.showCalloutOnRightSide,
			},
			entity_window_util.CombinedStockGroupedCounts{
				initialCalloutTextInputPermanent = "",
				initialCalloutTextInputCollapsible = "",
				recipeAndParamInputCollapsible = content_card.makeRecipe0(InputInfo),
				initialCalloutTextOutputPermanent = "",
				initialCalloutTextOutputCollapsible = "",
				recipeAndParamOutputCollapsible = content_card.makeRecipe0(OutputInfo),
				cardKey = "parcelSortingStock",
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

pd_sorting_eow.SortingPlugin = react.RegisterPluginRecipe(empty_construction_eow.EmptyConstructionEowExtensionPoint, "PdSortingPlugin", function(params : EmptyConstructionEow.EmptyConstructionWidgetPluginParams) : TreeNodeId
	local stockList = engine_react_util.useStepStateTimer(function() : Engine.Entity
		local ok, result = pcall(stockOfSorting, params.entityId)
		return ok and result as Engine.Entity or -1
	end, RefreshInterval):old()
	return sortingCards(stockList, params)
end)

return pd_sorting_eow
