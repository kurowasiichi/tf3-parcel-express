-- The parcel stocks, shared by the constructions (parcel_office, parcel_post), the game script and the GUI: an output
-- stock of parcels with a rule like the output of a raw industry, so the game produces the parcels itself and gives them
-- their destinations. The rule produces RuleCapacity parcels per year at productivity 1 (the industry window: a cycle
-- takes year / capacity / boost); the game script sets the productivity of the stock list from the residents in the
-- range (makeStockListSetModifiersCmd, like the workers boost of the industries).
--
-- Tried and dropped: putting the parcels into the stock with makeStockSetCargoAmountCmd (it recreates the parcels in
-- the stock, and they lose their destinations), and an input stock of parcels handed in (parcel_input.cargo) with a rule
-- turning them into parcels (the rule did not convert them).

local production : PdProduction = {}

production.ParcelCargo = "parcel_delivery::/cargos/parcel/parcel.cargo"
--- the cargo class of the parcels only (cargos/classes/parcel.cargoclass.lua), handled by the delivery points
production.ParcelClass = "PARCEL"
--- the stock id of the parcels
production.OutputStock = 0
production.Capacity = 200
--- parcels per year at productivity 1
production.RuleCapacity = 100
--- instance metadata key of the parcel drop boxes (they are not on the street network, so not in the street connector
--- system)
production.DropMetadata = "parcel_delivery_drop"

--- The intercity parcel sorting centers (parcel_sorting.script.tl): an input stock and an output stock with a rule
--- turning one into the other, like the stocks of an industry (industries/industryutil.lua). The export center takes the
--- parcels of the towns (the cargo routing sends them there like to the input of an industry) and gives intercity
--- parcels, the import center the other way round. The rule converts SortingRuleCapacity parcels per year at
--- productivity 1; like an industry, a sorting center has workplaces, and with enough workers the productivity is
--- SortingBoostFactor (the industry_workers script of the base game reads it from the construction, set by
--- parcel_sorting.script.tl).
production.IntercityCargo = "parcel_delivery::/cargos/parcel/parcel_intercity.cargo"
--- instance metadata key of the sorting centers
production.SortingMetadata = "parcel_delivery_sorting"
--- the stock ids of the sorting centers
production.SortingInputStock = 0
production.SortingOutputStock = 1
production.SortingInputCapacity = 800
production.SortingOutputCapacity = 800
production.SortingRuleCapacity = 400
--- the workplaces (those of a small factory of the base game) and the productivity with enough workers: 2.5, shown as
--- +150% in the boosters card (it shows the factor minus 1), 1000 parcels per year
production.SortingWorkers = 20
production.SortingBoostFactor = 2.5

function production.stocks() : {table}
	return {
		{
			type = "OUTPUT_STOCK",
			cargoType = production.ParcelCargo,
			capacity = production.Capacity,
			decayRateFactor = 0,
		},
	}
end

function production.rules() : {table}
	local output : {string : integer} = { [production.ParcelCargo] = 1 }
	local rule : table = {
		input = { {} },
		output = output,
		capacity = production.RuleCapacity,
	}
	return { rule }
end

--- the cargo taken and the cargo given by a sorting center: parcels into intercity parcels for export, the other way
--- round for import
local function sortingCargos(export : boolean) : string, string
	if export then
		return production.ParcelCargo, production.IntercityCargo
	end
	return production.IntercityCargo, production.ParcelCargo
end

function production.sortingStocks(export : boolean) : {table}
	local input, output = sortingCargos(export)
	return {
		{
			type = "INPUT_STOCK",
			cargoType = input,
			capacity = production.SortingInputCapacity,
			decayRateFactor = 0,
		},
		{
			type = "OUTPUT_STOCK",
			cargoType = output,
			capacity = production.SortingOutputCapacity,
			decayRateFactor = 0,
		},
	}
end

function production.sortingRules(export : boolean) : {table}
	local _, cargo = sortingCargos(export)
	local output : {string : integer} = { [cargo] = 1 }
	-- one unit of the input stock (the input vector counts the input stocks) into one unit of the output
	local rule : table = {
		input = { { 1 } },
		output = output,
		capacity = production.SortingRuleCapacity,
	}
	return { rule }
end

return production
