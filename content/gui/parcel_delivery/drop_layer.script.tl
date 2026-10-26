-- Layer shown while a parcel drop box is placed (configureLayerScript of parcel_drop.con.lua): the default layer of the
-- constructions (heightmap contours, construction_desc_layers.script.tl) with the cargo catchment areas of all stations,
-- as the infrastructure layer shows them (layers/layer_infrastructure.tl, areas "Cargo"). It shows where the parcel
-- delivery points and post offices reach a drop box.

local default_layers = ug_require "::/gui/construction/construction_desc_layers.script.tl" as table

local record PdDropLayer
	configureDropLayerFn : function(captureParams : table, layerConfig : LayerConfig) : LayerConfig
end

local pd_drop_layer : PdDropLayer = {}

function pd_drop_layer.configureDropLayerFn(captureParams : table, layerConfig : LayerConfig) : LayerConfig
	local configureDefault = default_layers.configureDefaultLayerFn as function(table, LayerConfig) : LayerConfig
	if configureDefault ~= nil then
		layerConfig = configureDefault(captureParams, layerConfig)
	end
	local settings = api.type.LayerConfig.CatchmentAreaDisplaySettings.new()
	settings.innerAlpha = 0.4
	settings.borderAlpha = 1.0
	settings.godrayAlpha = 1.0
	local catchment = api.type.LayerConfig.CatchmentAreaRenderableConfig.new()
	catchment.isVisible = true
	catchment.displaySettings = settings
	catchment.entity = -1
	catchment.addGodrays = true
	catchment.cargo = true
	catchment.person = false
	catchment.maintenance = false
	layerConfig.catchmentAreaRenderableConfig = catchment
	return layerConfig
end

return pd_drop_layer
