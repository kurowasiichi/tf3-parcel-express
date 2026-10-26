-- Parcels card of the line window (registered by parcel_line.res.lua): for every stop of the line, the parcels waiting
-- there for the line. The game keeps the parcels in the stocks of the post offices and parcel posts (like the output of
-- an industry), not at the stations, so the line window of the base game shows none. A parcel waits for the line at a
-- stop when its stock is in the catchment of the stop and its destination in the catchment of another stop of the line.
-- A parcel that several lines can take counts for each of them, like the passengers at a stop served by several lines.

local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local content_card = ug_require "::/gui/main/content_card.tl" as ContentCard
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil
local line_eow = ug_require "::/gui/entity_window/line/line_eow.script.tl" as LineEow
local react = ug_require "::/gui/main/react.lua" as React

local production = ug_require "/parcel_delivery/production.tl" as PdProduction

local RefreshInterval <const> = 1.0
--- parts of the resource names of the constructions with a parcel stock
local StockFiles <const> = { "parcel_office.con", "parcel_post.con", "parcel_drop.con" }

local record PdLineEow
	ParcelLinePlugin : Recipe<LineEow.LineWidgetPluginParams>
end

local pd_line_eow : PdLineEow = {}

local record StopParcels
	name : string
	waiting : integer
end

local record LineParcels
	--- whether a stop of the line covers a parcel stock
	served : boolean
	stops : {StopParcels}
	total : integer
end

local function text(s : string) : TreeNodeId
	return builtin.TextView{ text = s }
end

local function parcelCargoId() : CargoTypeId
	local id = api.res.cargoTypeRep.find(production.ParcelCargo)
	return id ~= nil and id or -1
end

--- whether a stock list entity is the parcel stock of a post office or parcel post
local function isParcelStock(entity : Engine.Entity) : boolean
	local constructionEntity = api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction(entity)
	if constructionEntity == nil or constructionEntity < 0 then
		return false
	end
	local construction = api.engine.getComponent(constructionEntity, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
	local fileName = construction ~= nil and tostring(construction.fileName) or ""
	for _, part in ipairs(StockFiles) do
		if string.find(fileName, part, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local function stopName(stationGroup : Engine.Entity, index : integer) : string
	local name = api.engine.getComponent(stationGroup, api.type.ComponentType.NAME) as Engine.Component.Name
	if name ~= nil and name.name ~= nil and name.name ~= "" then
		return name.name
	end
	return string.format(_("parcel_delivery_line_stop"), index)
end

local function lineParcels(lineEntity : Engine.Entity) : LineParcels
	local result : LineParcels = { served = false, stops = {}, total = 0 }
	local parcel = parcelCargoId()
	local line = api.engine.getComponent(lineEntity, api.type.ComponentType.LINE) as Engine.Component.Line
	if parcel < 0 or line == nil or line.stops == nil then
		return result
	end
	-- the catchables of every stop (all stations of its station group)
	local stopCatchables : {{Engine.Entity : boolean}} = {}
	for i, stop in ipairs(line.stops) do
		local set : {Engine.Entity : boolean} = {}
		local group = api.engine.getComponent(stop.stationGroup, api.type.ComponentType.STATION_GROUP) as Engine.Component.StationGroup
		for _, station in ipairs(group ~= nil and group.stations or {}) do
			for _, entity in ipairs(api.engine.system.catchmentAreaSystem.getStationCatchables(station, true) or {}) do
				set[entity] = true
			end
		end
		stopCatchables[i] = set
	end
	for i, stop in ipairs(line.stops) do
		local waiting = 0
		for entity in pairs(stopCatchables[i]) do
			if isParcelStock(entity) then
				result.served = true
				for _, item in ipairs(api.engine.system.simEntityAtStockSystem.getStockEntities(entity, 0) or {}) do
					local cargo = api.engine.getComponent(item[2], api.type.ComponentType.SIM_CARGO) as Engine.Component.SimCargo
					local target = cargo ~= nil and cargo.cargoType == parcel and cargo.targetOrPickupEntity or -1
					if target ~= nil and target >= 0 and not stopCatchables[i][target] then
						for j = 1, #line.stops do
							if j ~= i and stopCatchables[j][target] then
								waiting = waiting + 1
								break
							end
						end
					end
				end
			end
		end
		result.stops[i] = { name = stopName(stop.stationGroup, i), waiting = waiting }
		result.total = result.total + waiting
	end
	return result
end

local function sameParcels(a : LineParcels, b : LineParcels) : boolean
	if a == nil or b == nil or a.served ~= b.served or a.total ~= b.total or #a.stops ~= #b.stops then
		return false
	end
	for i = 1, #a.stops do
		if a.stops[i].name ~= b.stops[i].name or a.stops[i].waiting ~= b.stops[i].waiting then
			return false
		end
	end
	return true
end

local record LineParam
	lineEntity : Engine.Entity
end

local ParcelStops = react.RegisterRecipe("PdParcelStops", function(param : LineParam) : TreeNodeId
	local parcels = engine_react_util.useStepStateTimer(function() : LineParcels
		local ok, result = pcall(lineParcels, param.lineEntity)
		return ok and result as LineParcels or { served = false, stops = {}, total = 0 }
	end, RefreshInterval, sameParcels):old()

	local children : {TreeNodeId} = {}
	for i, stop in ipairs(parcels.stops) do
		children[#children + 1] = text(string.format(_("parcel_delivery_line_stop_waiting"), i, stop.name, stop.waiting))
	end
	children[#children + 1] = text(string.format(_("parcel_delivery_line_total"), parcels.total))
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = children,
	}
end)

pd_line_eow.ParcelLinePlugin = react.RegisterPluginRecipe(line_eow.LineEowExtensionPoint, "PdParcelLinePlugin", function(params : LineEow.LineWidgetPluginParams) : TreeNodeId
	-- the card only for lines with a stop at a parcel stock
	local served = engine_react_util.useStepStateTimer(function() : boolean
		local ok, result = pcall(lineParcels, params.entityId)
		return ok and (result as LineParcels).served or false
	end, RefreshInterval):old()

	if not served then
		return builtin.BoxLayout{ children = {} }
	end
	return builtin.BoxLayout{
		child = content_card.ContentCard{
			title = _("parcel_delivery_line_title"),
			initialCalloutTextPermanent = "",
			recipeAndParamPermanent = content_card.makeRecipeAndParam(ParcelStops, { lineEntity = params.entityId }),
			gameCtx = params.gameCtx,
			showOnRightSide = params.showCalloutOnRightSide,
		},
	}
end)

return pd_line_eow
