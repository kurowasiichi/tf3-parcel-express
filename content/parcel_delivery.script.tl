-- Prototype of the parcel delivery:
-- - parcels are added to the residential cargo needs of every town (makeTownUpdateCargoNeedsCmd)
-- - the parcel posts (parcel_post.con.lua) are mailboxes on the sidewalk with an output stock, connected to the street
--   by a very short entrance street: a stock is only in a station catchment when its construction is on the network
--   (street stops cannot hold stocks, a construction without a street is not reached). The stock is filled from the
--   residents around the post; box vans load the parcels at a parcel mailbox stop (parcel_box.con.lua) or any cargo stop
--   covering the post, the cargo routing of the game takes them to the residential districts.
-- The log shows what the prototype has to verify.
--
-- The update runs on several threads with separate Lua states: everything that must survive between calls is kept in
-- the game script state, not in module level variables.

local production = ug_require "/parcel_delivery/production.tl" as PdProduction
local pd_debug = ug_require "/parcel_delivery/debug.tl" as PdDebug

local StateVersion <const> = 2
local ParcelCargo <const> = production.ParcelCargo
--- the rate of the business parcels is averaged over this many days (for the log)
local BusinessAverageDays <const> = 30
--- The productivity of a stock list is only set again when it changes by more than this fraction. A mailbox without
--- parcels (no residents and businesses counted, e.g. before its towns are scanned) keeps productivity 1, the 100 parcels
--- per year a stock starts with; with parcels it gets their productivity. The rule takes year / capacity / productivity
--- for a parcel, and the game fixes this time when the parcel before is made: a parcel made at a very low productivity
--- puts the next one far ahead, whatever the productivity is set to afterwards (the former minimum of 0.001 put it 10
--- years ahead and the drop box stopped). At 0 the rule would produce as fast as it can.
local ProductivityTolerance <const> = 0.05
local DefaultProductivity <const> = 1
--- A rule is stuck when its next parcel is further ahead than this many times the time of a parcel at the productivity
--- of now, and more than StuckMinYearShare of a year ahead (a parcel made at a far lower productivity): its drop box is
--- built again (the rule starts anew).
local StuckFactor <const> = 3
local StuckMinYearShare <const> = 1 / 12
--- parts of the resource names of the parcel posts and of the hidden sources of the previous prototype
local PostFile <const> = "parcel_post.con"
local OldSourceFile <const> = "parcel_source.con"
local OfficeFile <const> = "parcel_office.con"
local DropFile <const> = "parcel_drop.con"
local DropWarehouseFile <const> = "parcel_drop_warehouse.con"
local DropRangeTestFile <const> = "parcel_drop_range_test.con"
--- the farthest distance (m) of a drop box from a street (farther ones are removed), and the samples per street edge
local MaxStreetDistance <const> = 12
local StreetSamples <const> = 20
--- the radius (m) of the search for the street edges near a drop box (streetDistance)
local NearStreetSearchRadius <const> = 50
--- The drop boxes of the parcel delivery points (parcel_box.con, the stops): the file of the drop box, the distance (m)
--- within which a drop box belongs to a delivery point, the tries to build one, and its place on the sidewalk (inside
--- the outer edge of the street by DropBoxInset, at least MinDropBoxOffset from the center).
-- ("parcel_box": the one-sided parcel_box.con and the two-sided parcel_box_twosided.con)
local BoxFile <const> = "parcel_box"
local TwoSidedFile <const> = "parcel_box_twosided"
local DropConFile <const> = "parcel_delivery::/parcel_delivery/parcel_drop.con"
local PairDistance <const> = 12
--- drop boxes whose distances to a delivery point differ by less than this (m) stand in the same place
local SamePlaceDistance <const> = 1
local MaxDropBoxAttempts <const> = 2
local DropBoxBuildVersion <const> = 3
--- the drop box stands this far (m) along the street from the stacked boxes of its stop
local DropBoxShift <const> = 2
local DropBoxInset <const> = 1.0
local MinDropBoxOffset <const> = 3.0
--- game time (ms) between two passes
local PassIntervalMs <const> = 2000
--- The town needs, the mailboxes, the delivery points and the boost of the sorting centers are looked up every n-th
--- pass, each on a pass of its own (ScanTurns), so they do not all fall on the same pass. The town buildings are looked
--- at town by town, every town once in TownScanPasses passes (30 s of game time), a part of them on every pass.
local ScanEveryPasses <const> = 5
local TownScanPasses <const> = 15
--- the pass (remainder of the pass count by ScanEveryPasses) of each of the tasks looked up every ScanEveryPasses passes
local record ScanTurns
	townNeeds : integer
	mailboxes : integer
	deliveryPoints : integer
	sortingBoost : integer
	reachable : integer
	--- the check for stuck rules of the drop boxes (in the production pass)
	stuckRules : integer
end
local ScanTurn <const> : ScanTurns = { townNeeds = 0, mailboxes = 1, deliveryPoints = 2, sortingBoost = 3, reachable = 4,
	stuckRules = 3 }
--- a summary is logged every n-th pass
local LogEveryPasses <const> = 30
--- town buildings within this distance (m) of a parcel post count for it: the options of the mod parameter (mod.json),
--- the same as the catchment radius of the post offices (mod.script.tl)
local RadiusParam <const> = "parcel_delivery_radius"
local RadiusSteps <const> : {number} = { 160, 200, 240, 320 }
local DefaultRadiusIndex <const> = 1
--- parcels per resident and calendar day at 1x: 50 parcels per 100 residents and year (40 was tried and too few)
local ParcelsPerResidentPerDay <const> = 0.5 / 365
--- the mod parameter of the production: 1-based index of the multiplier (mod.json), the options of it and of the
--- business rate, and the default (1x)
local ParcelModId <const> = "parcel_delivery"
local RateParam <const> = "parcel_delivery_rate"
local RateSteps <const> : {number} = { 0.5, 1, 1.5, 2 }
local DefaultRateIndex <const> = 2
--- the mod parameter of the parcels of the commercial and industrial buildings: 1 off, 2 on
local BusinessParam <const> = "parcel_delivery_business"
--- parcels per unit of cargo supplied to (consumed by) a commercial or industrial building at 1x, and the mod parameter
--- of its multiplier (RateSteps)
local ParcelsPerSuppliedUnit <const> = 0.5
local BusinessRateParam <const> = "parcel_delivery_business_rate"
--- calendar day length used when the game speed gives none
local FallbackMillisPerDay <const> = 2000

-- performance metrics ------------------------------------------------------------------------------------------------

-- The time the update takes, written to the log as a "perf" line every PerfLogMs of game time, to compare the
-- optimizations (tools\perf.ps1 sums the lines up). Kept per Lua state: each update thread has its own, the line names
-- it. The time is that of os.clock (on Windows the elapsed time); without it only the counts are logged.
local clock : function() : number = os ~= nil and os.clock or nil
local PerfLogMs <const> = 60000
local perfLuaState = string.match(tostring({}), "(%x+)$") or "?"

--- game time (ms) of the last pass this Lua state saw, -1 before the first (runUpdate); kept per Lua state, only to
--- skip reading the state between passes
local lastPassSeen = -1

local record Perf
	--- game time (ms) and os.clock at the start of the period, -1 before the first update
	since : integer
	sinceClock : number
	--- update calls in the period
	frames : integer
	--- by part: runs, total time (s), longest time (s)
	parts : {string : {number}}
	--- by name: the last value
	counts : {string : integer}
end

local perf : Perf = { since = -1, sinceClock = 0, frames = 0, parts = {}, counts = {} }

local function perfAdd(part : string, t : number)
	local entry = perf.parts[part]
	if entry == nil then
		entry = { 0, 0, 0 }
		perf.parts[part] = entry
	end
	entry[1] = entry[1] + 1
	entry[2] = entry[2] + t
	entry[3] = math.max(entry[3], t)
end

--- runs fn and adds its time to the part
local function timed(part : string, fn : function())
	if clock == nil then
		fn()
		return
	end
	local t0 = clock()
	fn()
	perfAdd(part, clock() - t0)
end

local function perfCount(name : string, n : integer)
	perf.counts[name] = n
end

--- writes the line of the period ending at the game time now and starts the next one
local function perfLog(now : integer)
	local elapsed = clock ~= nil and clock() - perf.sinceClock or 0
	local update = perf.parts["update"]
	local parts : {string} = {}
	for part, entry in pairs(perf.parts) do
		parts[#parts + 1] = string.format("%s=%dx/%.3fms/%.3fms", part, math.floor(entry[1]), entry[2] / math.max(1, entry[1]) * 1000,
			entry[3] * 1000)
	end
	table.sort(parts)
	local counts : {string} = {}
	for name, n in pairs(perf.counts) do
		counts[#counts + 1] = string.format("%s=%d", name, n)
	end
	table.sort(counts)
	log.message(string.format("[parcel_delivery] perf lua=%s game=%ds real=%.1fs frames=%d total=%.1fms share=%.3f%% | %s | %s",
		perfLuaState, math.floor((now - perf.since) / 1000), elapsed, perf.frames, update ~= nil and update[2] * 1000 or 0,
		update ~= nil and elapsed > 0 and update[2] / elapsed * 100 or 0,
		clock ~= nil and table.concat(parts, " ") or "no clock", table.concat(counts, " ")))
	perf.since = now
	perf.sinceClock = clock ~= nil and clock() or 0
	perf.frames = 0
	perf.parts = {}
end

--- a message for the log, written only with the debug switch (parcel_delivery/debug.tl); errors and the perf lines use
--- log.message
local function info(message : string)
	if pd_debug.Enabled then
		log.message(message)
	end
end

local function newState() : PdState
	return { version = StateVersion, boxes = {}, lastTime = -1, passes = 0, consumedUntil = -1 }
end

local function world() : Engine.Entity
	return api.engine.util.getWorld()
end

local function gameTimeMs() : integer
	local t = api.engine.getComponent(world(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
	return t.gameTime
end

local function millisPerDay() : number
	local speed = api.engine.getComponent(world(), api.type.ComponentType.GAME_SPEED) as Engine.Component.GameSpeed
	if speed == nil or speed.millisPerDay == nil or speed.millisPerDay <= 0 or speed.speedup == nil or speed.speedup <= 0 then
		return FallbackMillisPerDay
	end
	return speed.millisPerDay * speed.speedup
end

local function parcelCargoId() : CargoTypeId
	local id = api.res.cargoTypeRep.find(ParcelCargo)
	if id ~= nil and id >= 0 then
		return id
	end
	-- the resource name of a mod cargo may differ, look for the file name
	for cargoId, name in pairs(api.res.cargoTypeRep.getAll()) do
		if string.find(name, "parcel.cargo", 1, true) ~= nil then
			return cargoId
		end
	end
	return -1
end

--- the person capacity of a town building, nil if it has none
local function personCapacityOf(personCapacity : Engine.Entity) : Engine.Component.PersonCapacity
	if personCapacity == nil or personCapacity < 0 then
		return nil
	end
	return api.engine.getComponent(personCapacity, api.type.ComponentType.PERSON_CAPACITY) as Engine.Component.PersonCapacity
end

local function isResidential(personCapacity : Engine.Entity) : boolean, integer
	local pc = personCapacityOf(personCapacity)
	if pc == nil or pc.type ~= api.type["enum"].LandUseType.RESIDENTIAL then
		return false, 0
	end
	return true, pc.capacity or 0
end

local function positionOf(constructionEntity : Engine.Entity) : Vec3f
	if constructionEntity == nil or constructionEntity < 0 then
		return nil
	end
	local construction = api.engine.getComponent(constructionEntity, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
	return construction ~= nil and construction.transf:getTransl() or nil
end

-- town needs ---------------------------------------------------------------------------------------------------------

--- adds the parcels to the residential needs of every town (the needs of the three districts are kept)
local function ensureResidentialNeeds(parcel : CargoTypeId)
	api.engine.forEachEntityWithComponent(function(townEntity : Engine.Entity)
		local town = api.engine.getComponent(townEntity, api.type.ComponentType.TOWN) as Engine.Component.Town
		if town == nil or town.cargoNeeds == nil then
			return
		end
		local needs : {{CargoTypeId}} = { {}, {}, {} }
		local hasParcels = false
		for district = 1, 3 do
			for _, cargoAndFactor in ipairs(town.cargoNeeds[district] or {}) do
				local cargo = cargoAndFactor[1]
				table.insert(needs[district], cargo)
				if district == 1 and cargo == parcel then
					hasParcels = true
				end
			end
		end
		if not hasParcels then
			table.insert(needs[1], parcel)
			api.cmd.sendCommand(api.cmd.makeTownUpdateCargoNeedsCmd(townEntity, needs, true))
			info("[parcel_delivery] town " .. tostring(townEntity) .. ": parcels added to the residential needs")
		end
	end, api.type.ComponentType.TOWN)
end

-- parcel posts -------------------------------------------------------------------------------------------------------

local function removeConstruction(constructionEntity : Engine.Entity)
	local proposal = api.type.SimpleProposal.new()
	proposal.constructionsToRemove = { constructionEntity }
	api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(proposal, nil, true, false))
end

--- The parcel posts are the constructions of parcel_post.con (looped over by file name; stock lists cannot be looped
--- over). The hidden sources of the previous prototype (parcel_source.con, not on the network) are removed.
local function updatePosts(s : PdState, parcel : CargoTypeId) : string
	local found : {Engine.Entity : boolean} = {}
	local function visit(constructionEntity : Engine.Entity)
		if found[constructionEntity] then
			return
		end
		local construction = api.engine.getComponent(constructionEntity, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
		local fileName = construction ~= nil and tostring(construction.fileName) or ""
		-- the hidden sources and the parcel posts of earlier versions are removed
		if string.find(fileName, OldSourceFile, 1, true) ~= nil or string.find(fileName, PostFile, 1, true) ~= nil
				or string.find(fileName, DropWarehouseFile, 1, true) ~= nil or string.find(fileName, DropRangeTestFile, 1, true) ~= nil then
			removeConstruction(constructionEntity)
			info("[parcel_delivery] retired construction " .. fileName .. " " .. tostring(constructionEntity) .. " removed")
			return
		end
		local isDrop = string.find(fileName, DropFile, 1, true) ~= nil
		if string.find(fileName, OfficeFile, 1, true) == nil and not isDrop then
			return
		end
		-- the stock list with a parcel stock (in the drop warehouse it follows the stocks of the warehouse)
		local stockList : Engine.Entity = -1
		for _, sub in ipairs(construction.subconstructions or {}) do
			local sl = api.engine.getComponent(sub, api.type.ComponentType.STOCK_LIST) as Engine.Component.StockList
			for _, stock in ipairs(sl ~= nil and sl.stocks or {}) do
				if stock.cargoType == parcel then
					stockList = sub
				end
			end
		end
		found[constructionEntity] = true
		local box = s.boxes[constructionEntity]
		local p = construction.transf:getTransl()
		if box == nil then
			box = { source = constructionEntity, stockList = stockList, residents = 0, pending = 0, produced = 0, requested = -1 }
			s.boxes[constructionEntity] = box
			-- the buildings around it are counted on the next pass (all towns), not on the turns of their towns
			s.townShares = {}
			local sl = stockList >= 0 and api.engine.getComponent(stockList, api.type.ComponentType.STOCK_LIST) as Engine.Component.StockList or nil
			info(string.format("[parcel_delivery] parcel post %d at %.0f, %.0f: parcel stock %d with %d parcels, productivity %.2f, built %d ms ago",
				constructionEntity, p.x, p.y, stockList,
				stockList >= 0 and (api.engine.system.simEntityAtStockSystem.getStockCount(stockList, 0) or 0) or -1,
				sl ~= nil and sl.modifiers ~= nil and sl.modifiers.productivity or -1,
				gameTimeMs() - (construction.timeBuilt or 0)))
		end
		box.stockList = stockList
		box.position = { p.x, p.y, p.z }
		box.drop = isDrop
		box.builtAt = construction.timeBuilt or 0
	end
	local system = api.engine.system.streetConnectorSystem
	local forEach = (system as table).forEach as function(function(Engine.Entity))
	forEach(visit)
	-- the post offices are street stations
	for _, constructionEntity in pairs(api.engine.system.streetConnectorSystem.getStation2ConstructionMap()) do
		visit(constructionEntity)
	end
	-- the parcel drop boxes are free-standing assets, not on the street network: found by their metadata
	api.engine.system.streetConnectorSystem.forEachConstructionWithMetadata(production.DropMetadata, true, true,
		function(constructionEntity : Engine.Entity, _construction : Engine.Component.Construction, _id : ConstructionId)
			visit(constructionEntity)
		end)
	for key in pairs(s.boxes) do
		if not found[key] then
			s.boxes[key] = nil
			-- its buildings go to the other mailboxes on the next pass (all towns)
			s.townShares = {}
		end
	end
	return "parcel posts"
end

--- a mod parameter: the 1-based index of the selected option, nil if missing
local function param(key : string) : integer
	local all = api.engine.config.getModParams()
	local params = all ~= nil and all[ParcelModId] or nil
	local index = params ~= nil and tonumber(params[key]) or nil
	return index ~= nil and math.floor(index) or nil
end

--- the collection radius selected in the mod parameters, also the catchment radius of the delivery points (mod.script.tl)
local function collectionRadius() : number
	return RadiusSteps[param(RadiusParam) or DefaultRadiusIndex] or RadiusSteps[DefaultRadiusIndex]
end

-- placement of the drop boxes -------------------------------------------------------------------------------------

--- a point of a street edge (cubic Hermite curve of its positions and tangents) and its direction, t from 0 to 1
local function edgePoint(e : Engine.Component.BaseEdge, t : number) : number, number, number, number
	local t2, t3 = t * t, t * t * t
	local h00, h10, h01, h11 = 2 * t3 - 3 * t2 + 1, t3 - 2 * t2 + t, -2 * t3 + 3 * t2, t3 - t2
	local x = h00 * e.position0.x + h10 * e.tangent0.x + h01 * e.position1.x + h11 * e.tangent1.x
	local y = h00 * e.position0.y + h10 * e.tangent0.y + h01 * e.position1.y + h11 * e.tangent1.y
	local d00, d10, d01, d11 = 6 * t2 - 6 * t, 3 * t2 - 4 * t + 1, -6 * t2 + 6 * t, 3 * t2 - 2 * t
	local dx = d00 * e.position0.x + d10 * e.tangent0.x + d01 * e.position1.x + d11 * e.tangent1.x
	local dy = d00 * e.position0.y + d10 * e.tangent0.y + d01 * e.position1.y + d11 * e.tangent1.y
	return x, y, dx, dy
end

--- the searches of all streets in this Lua state (streetDistance; for the perf line)
local fullStreetSearches = 0

--- the distance (m) from (x, y) to the nearest of the street edges, math.huge without any
local function edgesDistance(x : number, y : number, edges : {Engine.Entity}) : number
	local nearest : number = math.huge
	for _, edge in ipairs(edges) do
		local e = api.engine.getComponent(edge, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
		if e ~= nil then
			for i = 0, StreetSamples do
				local px, py = edgePoint(e, i / StreetSamples)
				local d = math.sqrt((px - x) ^ 2 + (py - y) ^ 2)
				if d < nearest then
					nearest = d
				end
			end
		end
	end
	return nearest
end

--- The distance (m) from (x, y) to the nearest street, nil without streets. The street edges near it come from the
--- spatial index of the game (octree, within NearStreetSearchRadius); only when none of them is within maxDistance are
--- all streets of the map looked at (the octree may leave out a long edge whose middle is far): a street within
--- maxDistance is found either way, a farther distance is that of the full search.
local function streetDistance(x : number, y : number, maxDistance : number) : number
	local okNear, near = pcall(function() : {Engine.Entity}
		return api.engine.util.octree.findEntitiesInCircle(api.type.Vec2f.new(x, y), NearStreetSearchRadius,
			api.type.ComponentType.BASE_EDGE_STREET)
	end)
	if okNear and near ~= nil then
		local nearest = edgesDistance(x, y, near as {Engine.Entity})
		perfCount("streetEdgesNear", #(near as {Engine.Entity}))
		if nearest <= maxDistance then
			return nearest
		end
	end
	fullStreetSearches = fullStreetSearches + 1
	perfCount("streetFullSearches", fullStreetSearches)
	local all : {Engine.Entity} = {}
	local edgesDone : {Engine.Entity : boolean} = {}
	for _, edges in pairs(api.engine.system.streetSystem.getNode2StreetEdgeMap() or {}) do
		for _, edge in ipairs(edges) do
			if not edgesDone[edge] then
				edgesDone[edge] = true
				all[#all + 1] = edge
			end
		end
	end
	local nearest = edgesDistance(x, y, all)
	return nearest < math.huge and nearest or nil
end

--- A drop box placed by hand away from the streets is removed: the drop boxes stand at a street.
local function checkDropBox(mailbox : Engine.Entity, box : PdBox)
	if box.position == nil or box.stopDone then
		return
	end
	box.stopDone = true
	local distance = streetDistance(box.position[1], box.position[2], MaxStreetDistance)
	if distance == nil or distance > MaxStreetDistance then
		removeConstruction(mailbox)
		info(string.format("[parcel_delivery] drop box %d removed: no street within %d m", mailbox, MaxStreetDistance))
	end
end

--- where the drop box of a delivery point stands: on the sidewalk of the side of the stop, facing the street, beside
--- the stacked boxes of the stop (DropBoxShift along the street); nil when the edge of the stop is not found. A
--- two-sided stop is listed on both sides of its edge: its box stands on the right side.
local function dropBoxPlace(point : Engine.Entity, eo : Engine.Component.EdgeObject, e : Engine.Component.BaseEdge) : {number}
	local onLeft, onRight = false, false
	for _, object in ipairs(e.objects or {}) do
		if object[1] == point then
			if object[2] == api.type["enum"].EdgeObjectType.STOP_LEFT then
				onLeft = true
			else
				onRight = true
			end
		end
	end
	local left = onLeft and not onRight
	local cx, cy, dx, dy = edgePoint(e, eo.param)
	local length = math.sqrt(dx * dx + dy * dy)
	if length <= 0 then
		return nil
	end
	dx, dy = dx / length, dy / length
	-- the side of the stop: left of the direction of the edge or right of it
	local ux, uy = -dy, dx
	if not left then
		ux, uy = dy, -dx
	end
	-- half the width of the street (its lanes with the sidewalks), the box inside the outer edge of the sidewalk
	local width = 0.0
	for _, laneConfig in ipairs((e.laneConfigs or {}) as {LaneConfig}) do
		width = width + (laneConfig.width or 0)
	end
	local offset = math.max(width / 2 - DropBoxInset, MinDropBoxOffset)
	local z = eo.transf:getTransl().z
	return { cx + ux * offset + dx * DropBoxShift, cy + uy * offset + dy * DropBoxShift, z, ux, uy }
end

--- builds a drop box at a place (the box faces the street: its +y points away from it)
local function buildDropBox(place : {number})
	local x, y, z, ux, uy = place[1], place[2], place[3], place[4], place[5]
	local construction = api.type.SimpleProposal.ConstructionEntity.new()
	construction.fileName = DropConFile
	construction.params = { seed = 0 }
	construction.transf = api.type.Mat4f.new(
		api.type.Vec4f.new(uy, -ux, 0, 0),
		api.type.Vec4f.new(ux, uy, 0, 0),
		api.type.Vec4f.new(0, 0, 1, 0),
		api.type.Vec4f.new(x, y, z, 1))
	construction.name = "parcel drop box"
	construction.playerEntity = -1
	-- As the hidden parcel sources of an early version were built (and were built): the lists of the proposal given as a
	-- whole (setting constructionsToAdd[1] changes a copy, the proposal stays empty), no context, not initiated by the
	-- player.
	local proposal = api.type.SimpleProposal.new()
	proposal.constructionsToAdd = { construction }
	proposal.constructionsToRemove = {}
	proposal.old2new = {}
	api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(proposal, nil, true, false))
end

--- Every parcel delivery point (a street stop, it cannot hold a stock) gets a drop box next to it, built by the script;
--- the drop box of a delivery point that was removed is removed as well. A drop box within PairDistance of a delivery
--- point is its drop box (also one placed by hand).
local function pairDeliveryPoints(s : PdState)
	s.pointBoxes = s.pointBoxes or {}
	-- the tries start again when the way of building changes
	if s.pointAttempts == nil or s.pointAttemptsVersion ~= DropBoxBuildVersion then
		s.pointAttempts = {}
		s.pointAttemptsVersion = DropBoxBuildVersion
	end
	-- The edge objects of the streets: getEdgeObject2EdgeMap gives none in the game script, the objects of the street
	-- edges do.
	local edgeObjects : {{Engine.Entity, Engine.Component.EdgeObject, Engine.Component.BaseEdge}} = {}
	local edgesDone : {Engine.Entity : boolean} = {}
	local edgeCount = 0
	for _, edges in pairs(api.engine.system.streetSystem.getNode2StreetEdgeMap() or {}) do
		for _, edge in ipairs(edges) do
			if not edgesDone[edge] then
				edgesDone[edge] = true
				edgeCount = edgeCount + 1
				local e = api.engine.getComponent(edge, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
				for _, object in ipairs(e ~= nil and e.objects or {}) do
					local eo = api.engine.getComponent(object[1], api.type.ComponentType.EDGE_OBJECT) as Engine.Component.EdgeObject
					if eo ~= nil then
						edgeObjects[#edgeObjects + 1] = { object[1], eo, e }
					end
				end
			end
		end
	end
	if pd_debug.Enabled and s.passes % LogEveryPasses == 1 then
		local samples : {string} = {}
		for i = 1, math.min(#edgeObjects, 8) do
			samples[i] = string.format("%d [%s]", edgeObjects[i][1], tostring(edgeObjects[i][2].edgeObjectConstruction))
		end
		info(string.format("[parcel_delivery] edge objects: %d; %s", #edgeObjects, table.concat(samples, "; ")))
	end
	perfCount("streetEdges", edgeCount)
	perfCount("edgeObjects", #edgeObjects)
	local points : {Engine.Entity : boolean} = {}
	local pair2 = PairDistance * PairDistance
	-- The delivery points, each once (a two-sided stop is listed on both sides of its edge), those on the right side of
	-- their street first: of stops close together (the two sides of a street) the one on the right gets the drop box.
	local candidates : {{Engine.Entity, Engine.Component.EdgeObject, Engine.Component.BaseEdge, boolean}} = {}
	for _, item in ipairs(edgeObjects) do
		local point, eo, edge = item[1], item[2], item[3]
		if not points[point] and string.find(tostring(eo.edgeObjectConstruction), BoxFile, 1, true) ~= nil then
			points[point] = true
			local right = false
			for _, object in ipairs(edge.objects or {}) do
				if object[1] == point and object[2] ~= api.type["enum"].EdgeObjectType.STOP_LEFT then
					right = true
				end
			end
			-- a two-sided delivery point is a stop on each side of the street: only the one on the right side gets the box
			local twoSided = string.find(tostring(eo.edgeObjectConstruction), TwoSidedFile, 1, true) ~= nil
			if right or not twoSided then
				candidates[#candidates + 1] = { point, eo, edge, right }
			end
		end
	end
	table.sort(candidates, function(a : {Engine.Entity, Engine.Component.EdgeObject, Engine.Component.BaseEdge, boolean},
			b : {Engine.Entity, Engine.Component.EdgeObject, Engine.Component.BaseEdge, boolean}) : boolean
		return a[4] and not b[4]
	end)
	-- the drop boxes requested in this pass (they stand from the next one on), and the places of the delivery points
	local requested : {{number}} = {}
	local stops : {{number}} = {}
	for _, item in ipairs(candidates) do
		local point, eo, edge = item[1], item[2], item[3]
		local p = eo.transf:getTransl()
		stops[#stops + 1] = { p.x, p.y }
		-- The drop box of a delivery point is the nearest one within PairDistance; of drop boxes at the same place (closer
		-- than SamePlaceDistance to each other's distance), the one built first: it is the one the town buildings count
		-- for (mailboxFor), the others are extra ones (removed below).
		local paired : Engine.Entity = nil
		local pairedDistance, pairedBuilt = math.huge, 0
		for mailbox, box in pairs(s.boxes) do
			if box.drop and box.position ~= nil then
				local d = math.sqrt((box.position[1] - p.x) ^ 2 + (box.position[2] - p.y) ^ 2)
				local built = box.builtAt or 0
				if d * d <= pair2 and (d < pairedDistance - SamePlaceDistance
						or (d < pairedDistance + SamePlaceDistance and (built < pairedBuilt or (built == pairedBuilt and mailbox < paired)))) then
					paired, pairedDistance, pairedBuilt = mailbox, d, built
				end
			end
		end
		local pending = false
		for _, place in ipairs(requested) do
			if (place[1] - p.x) ^ 2 + (place[2] - p.y) ^ 2 <= pair2 then
				pending = true
			end
		end
		if paired ~= nil then
			if s.pointBoxes[point] ~= paired then
				info(string.format("[parcel_delivery] delivery point %d: drop box %d", point, paired))
			end
			s.pointBoxes[point] = paired
		elseif not pending and (s.pointAttempts[point] or 0) < MaxDropBoxAttempts then
			s.pointAttempts[point] = (s.pointAttempts[point] or 0) + 1
			local place = dropBoxPlace(point, eo, edge)
			if place ~= nil then
				buildDropBox(place)
				requested[#requested + 1] = { p.x, p.y }
				if pd_debug.Enabled then
					-- the nearest drop box: a drop box farther than PairDistance from its stop gets a second one
					local nearest, nearestDistance = -1, math.huge
					for mailbox, box in pairs(s.boxes) do
						if box.drop and box.position ~= nil then
							local d = math.sqrt((box.position[1] - p.x) ^ 2 + (box.position[2] - p.y) ^ 2)
							if d < nearestDistance then
								nearest, nearestDistance = mailbox, d
							end
						end
					end
					info(string.format("[parcel_delivery] delivery point %d (%s, attempt %d) at %.0f, %.0f: drop box requested at %.0f, %.0f; nearest drop box %d at %.1f m",
						point, tostring(eo.edgeObjectConstruction), s.pointAttempts[point], p.x, p.y, place[1], place[2], nearest, nearestDistance))
				end
			end
		end
	end
	-- the drop box of a removed delivery point is removed, unless another delivery point uses it
	for point, mailbox in pairs(s.pointBoxes) do
		if not points[point] then
			s.pointBoxes[point] = nil
			s.pointAttempts[point] = nil
			local used = false
			for other, otherBox in pairs(s.pointBoxes) do
				if other ~= point and otherBox == mailbox and points[other] then
					used = true
				end
			end
			if not used and api.engine.entityExists(mailbox) then
				removeConstruction(mailbox)
				info(string.format("[parcel_delivery] delivery point %d removed: its drop box %d removed", point, mailbox))
			end
		end
	end
	for point in pairs(s.pointAttempts) do
		if not points[point] then
			s.pointAttempts[point] = nil
		end
	end
	-- Extra drop boxes: within PairDistance of a delivery point, but the drop box of none. The game may run the update in
	-- two Lua states at once, both building a drop box for the same delivery point in the same place; the one built
	-- first is paired, the others are removed.
	local pairedBoxes : {Engine.Entity : boolean} = {}
	for _, mailbox in pairs(s.pointBoxes) do
		pairedBoxes[mailbox] = true
	end
	local extra = 0
	for mailbox, box in pairs(s.boxes) do
		if box.drop and box.position ~= nil and not pairedBoxes[mailbox] then
			for _, stop in ipairs(stops) do
				if (box.position[1] - stop[1]) ^ 2 + (box.position[2] - stop[2]) ^ 2 <= pair2 then
					removeConstruction(mailbox)
					s.boxes[mailbox] = nil
					extra = extra + 1
					info(string.format("[parcel_delivery] extra drop box %d at %.0f, %.0f removed", mailbox, box.position[1], box.position[2]))
					break
				end
			end
		end
	end
	perfCount("extraDropBoxesRemoved", extra)
	if extra > 0 then
		-- the buildings counted for them go to the drop boxes kept on the next pass (all towns)
		s.townShares = {}
	end
end

--- The mailbox a town building at p counts for: of the mailboxes whose range covers it, the one built first (a mailbox
--- placed where the others already collect gets only the buildings no other one covers); -1 if none covers it.
local function mailboxFor(s : PdState, p : Vec3f, radius2 : number) : Engine.Entity
	local first : PdBox = nil
	local firstKey : Engine.Entity = -1
	for key, box in pairs(s.boxes) do
		if box.position ~= nil then
			local dx, dy = p.x - box.position[1], p.y - box.position[2]
			if dx * dx + dy * dy <= radius2 then
				local built, firstBuilt = box.builtAt or 0, first ~= nil and (first.builtAt or 0) or 0
				if first == nil or built < firstBuilt or (built == firstBuilt and key < firstKey) then
					first, firstKey = box, key
				end
			end
		end
	end
	return firstKey
end

--- the share of every mailbox in the buildings of one town: the residents of the residential buildings and the stock
--- lists of the commercial and industrial ones in its range; and the entities of the town without a town building
--- component (for the perf line: all of them would mean the map holds other entities)
local function scanTown(s : PdState, buildings : {Engine.Entity}, radius2 : number) : {Engine.Entity : PdTownShare}, integer
	local shares : {Engine.Entity : PdTownShare} = {}
	local residential = api.type["enum"].LandUseType.RESIDENTIAL
	local missing = 0
	for _, entity in ipairs(buildings) do
		local building = api.engine.getComponent(entity, api.type.ComponentType.TOWN_BUILDING) as Engine.Component.TownBuilding
		if building == nil then
			missing = missing + 1
		end
		local pc = personCapacityOf(building and building.personCapacity)
		local p = pc ~= nil and positionOf(building.construction) or nil
		local key = p ~= nil and mailboxFor(s, p, radius2) or -1
		if key >= 0 then
			local share = shares[key]
			if share == nil then
				share = { residents = 0, suppliers = {} }
				shares[key] = share
			end
			if pc.type == residential then
				share.residents = share.residents + (pc.capacity or 0)
			elseif building.stockList ~= nil and building.stockList >= 0 then
				table.insert(share.suppliers, building.stockList)
			end
		end
	end
	return shares, missing
end

--- The town buildings within the service range of the mailboxes, spread over the passes: every pass looks at the towns
--- of its turn, each town once in TownScanPasses passes, and keeps their shares in the state; the residents and
--- suppliers of every mailbox are the sum of the shares of all towns. The shares of a mailbox built or removed since
--- count from the next look at the towns around it (a removed one is left out of the sum at once).
local function scanTowns(s : PdState) : boolean
	local radius = collectionRadius()
	local radius2 = radius * radius
	local townMap = api.engine.system.townBuildingSystem.getTown2BuildingMap() or {}
	local towns : {Engine.Entity} = {}
	for town in pairs(townMap) do
		towns[#towns + 1] = town
	end
	table.sort(towns)
	s.townShares = s.townShares or {}
	local turn = s.passes % TownScanPasses
	local buildingCount, missingCount = 0, 0
	for i, town in ipairs(towns) do
		if (i - 1) % TownScanPasses == turn or s.townShares[town] == nil then
			local shares, missing = scanTown(s, townMap[town], radius2)
			s.townShares[town] = shares
			buildingCount = buildingCount + #townMap[town]
			missingCount = missingCount + missing
		end
	end
	-- towns that no longer exist
	for town in pairs(s.townShares) do
		if townMap[town] == nil then
			s.townShares[town] = nil
		end
	end
	for _, box in pairs(s.boxes) do
		box.residents = 0
		box.suppliers = {}
	end
	for _, shares in pairs(s.townShares) do
		for key, share in pairs(shares) do
			local box = s.boxes[key]
			if box ~= nil then
				box.residents = box.residents + share.residents
				for _, stockList in ipairs(share.suppliers) do
					table.insert(box.suppliers, stockList)
				end
			end
		end
	end
	perfCount("towns", #towns)
	perfCount("townBuildingsScanned", buildingCount)
	perfCount("townBuildingsMissing", missingCount)
	return true
end

--- debug: the residents of every residential building of the map by its stock list (for the reachable residents)
local function collectHomes() : {Engine.Entity : integer}
	local homes : {Engine.Entity : integer} = {}
	local residential = api.type["enum"].LandUseType.RESIDENTIAL
	api.engine.forEachEntityWithComponent(function(entity : Engine.Entity)
		local building = api.engine.getComponent(entity, api.type.ComponentType.TOWN_BUILDING) as Engine.Component.TownBuilding
		local pc = personCapacityOf(building and building.personCapacity)
		if pc ~= nil and pc.type == residential and building.stockList ~= nil and building.stockList >= 0 then
			homes[building.stockList] = pc.capacity or 0
		end
	end, api.type.ComponentType.TOWN_BUILDING)
	return homes
end

--- The residents the lines of every mailbox can deliver parcels to, like the destinations of the passengers: the parcels
--- leave at the source stations (the stations of the post office, or those whose catchment covers the stock of a parcel
--- post) and reach the residential buildings in the catchment of the other stations of the lines stopping there. The
--- buildings in the catchment of a source station are left out: cargo is not carried within one station, the game
--- throws such parcels away.
local function updateReachable(s : PdState, homes : {Engine.Entity : integer})
	local catchables : {Engine.Entity : {Engine.Entity : boolean}} = {}
	local stockToStations : {Engine.Entity : {Engine.Entity}} = {}
	local stationCount = 0
	api.engine.forEachEntityWithComponent(function(station : Engine.Entity)
		stationCount = stationCount + 1
		local set : {Engine.Entity : boolean} = {}
		for _, entity in ipairs(api.engine.system.catchmentAreaSystem.getStationCatchables(station, true) or {}) do
			set[entity] = true
			local list = stockToStations[entity]
			if list == nil then
				list = {}
				stockToStations[entity] = list
			end
			table.insert(list, station)
		end
		catchables[station] = set
	end, api.type.ComponentType.STATION)
	perfCount("stations", stationCount)

	for mailbox, box in pairs(s.boxes) do
		local sources : {Engine.Entity : boolean} = {}
		local construction = api.engine.getComponent(mailbox, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
		-- a post office sends from its own station only: the catchment of a nearby post office may cover its stock, but
		-- the parcels are counted for the post office whose lines serve them. A parcel post has no station, the stations
		-- covering its stock send its parcels.
		for _, station in ipairs(construction ~= nil and construction.stations or {}) do
			sources[station] = true
		end
		if next(sources) == nil then
			for _, station in ipairs(stockToStations[box.stockList] or {}) do
				sources[station] = true
			end
		end
		-- The stations the parcels can reach: the lines stopping at a source station, and with a change of lines at a
		-- shared station the lines stopping there, and so on (cargo changes lines at shared stations like the passengers:
		-- parcels from a parcel post reach the districts of the other post offices through a central post office).
		local others : {Engine.Entity : boolean} = {}
		local groupsDone : {Engine.Entity : boolean} = {}
		local linesDone : {Engine.Entity : boolean} = {}
		local queue : {Engine.Entity} = {}
		for station in pairs(sources) do
			local group = api.engine.system.stationGroupSystem.getStationGroup(station)
			if group ~= nil and group >= 0 and not groupsDone[group] then
				groupsDone[group] = true
				table.insert(queue, group)
			end
		end
		box.lines = 0
		local direct = #queue
		local head = 1
		while head <= #queue do
			local group = queue[head]
			for _, lineEntity in ipairs(api.engine.system.lineSystem.getLinesForStationGroup(group) or {}) do
				if not linesDone[lineEntity] then
					linesDone[lineEntity] = true
					-- the lines stopping at the source stations themselves (diagnostics)
					if head <= direct then
						box.lines = box.lines + 1
					end
					local line = api.engine.getComponent(lineEntity, api.type.ComponentType.LINE) as Engine.Component.Line
					for _, stop in ipairs(line ~= nil and line.stops or {}) do
						local sg = api.engine.getComponent(stop.stationGroup, api.type.ComponentType.STATION_GROUP) as Engine.Component.StationGroup
						for _, other in ipairs(sg ~= nil and sg.stations or {}) do
							if not sources[other] then
								others[other] = true
							end
						end
						if not groupsDone[stop.stationGroup] then
							groupsDone[stop.stationGroup] = true
							table.insert(queue, stop.stationGroup)
						end
					end
				end
			end
			head = head + 1
		end
		box.transferLines = 0
		for _ in pairs(linesDone) do
			box.transferLines = box.transferLines + 1
		end
		local reachable : {Engine.Entity : boolean} = {}
		for other in pairs(others) do
			for entity in pairs(catchables[other] or {}) do
				reachable[entity] = true
			end
		end
		for station in pairs(sources) do
			for entity in pairs(catchables[station] or {}) do
				reachable[entity] = nil
			end
		end
		box.reachable = 0
		box.reachableHomes = {}
		for entity in pairs(reachable) do
			if homes[entity] ~= nil then
				box.reachable = box.reachable + homes[entity]
				table.insert(box.reachableHomes, entity)
			end
		end
	end
	-- the room of a home reached by several mailboxes is shared by them
	s.homeShares = {}
	for _, box in pairs(s.boxes) do
		for _, home in ipairs(box.reachableHomes or {}) do
			s.homeShares[home] = (s.homeShares[home] or 0) + 1
		end
	end
end

--- free room (parcels) in the parcel stock of a residential building: it takes no more parcels than that, the game
--- throws away the rest
local function homeRoom(stockListEntity : Engine.Entity, parcel : CargoTypeId) : number
	-- a home removed since the reachable homes were looked up (getComponent throws for an entity that no longer exists)
	if not api.engine.entityExists(stockListEntity) then
		return 0
	end
	local stockList = api.engine.getComponent(stockListEntity, api.type.ComponentType.STOCK_LIST) as Engine.Component.StockList
	for i, stock in ipairs(stockList ~= nil and stockList.stocks or {}) do
		if stock.cargoType == parcel then
			local count = api.engine.system.simEntityAtStockSystem.getStockCount(stockListEntity, i - 1) or 0
			return math.max(0, (stock.capacity or 0) - count)
		end
	end
	return 0
end

--- the room the homes reached by the lines of a mailbox have for its parcels
local function reachableRoom(s : PdState, box : PdBox, parcel : CargoTypeId) : number
	local room = 0.0
	for _, home in ipairs(box.reachableHomes or {}) do
		room = room + homeRoom(home, parcel) / math.max(1, (s.homeShares or {})[home] or 1)
	end
	return room
end

--- cargo units consumed by a stock list in the game time (from, to]: every application of a rule records the stocks
--- it took one unit from
local function consumedBetween(stockListEntity : Engine.Entity, from : integer, to : integer) : integer
	-- a building removed since its town was scanned (getComponent throws for an entity that no longer exists)
	if not api.engine.entityExists(stockListEntity) then
		return 0
	end
	local stockList = api.engine.getComponent(stockListEntity, api.type.ComponentType.STOCK_LIST) as Engine.Component.StockList
	if stockList == nil or stockList.ruleDatas == nil then
		return 0
	end
	local units = 0
	for _, ruleData in ipairs(stockList.ruleDatas) do
		for _, apply in ipairs(ruleData.applyHistory or {}) do
			if apply.time > from and apply.time <= to then
				units = units + #(apply.consumedCargo or {})
			end
		end
	end
	return units
end

--- parcels produced by the rule of a parcel stock in the game time (from, to]
local function producedBetween(stockListEntity : Engine.Entity, from : integer, to : integer) : integer
	if from < 0 then
		return 0
	end
	local stockList = api.engine.getComponent(stockListEntity, api.type.ComponentType.STOCK_LIST) as Engine.Component.StockList
	if stockList == nil or stockList.ruleDatas == nil then
		return 0
	end
	local units = 0
	for _, ruleData in ipairs(stockList.ruleDatas) do
		for _, apply in ipairs(ruleData.applyHistory or {}) do
			if apply.time > from and apply.time <= to then
				for _, produced in ipairs(apply.producedCargo or {}) do
					units = units + (produced[2] or 0)
				end
			end
		end
	end
	return units
end

--- a production multiplier selected in the mod parameters (1x if the option is missing or out of range)
local function rate(key : string) : number
	local index = param(key)
	return index ~= nil and RateSteps[math.floor(index)] or RateSteps[DefaultRateIndex]
end

--- whether the commercial and industrial buildings send parcels (option 2 "on", the default)
local function businessParcels() : boolean
	return (param(BusinessParam) or 2) == 2
end

--- whether the rule of a stock list waits for a parcel far longer than the productivity of now takes (see StuckFactor)
local function isStuck(stockList : Engine.Component.StockList, productivity : number, now : integer) : boolean
	local year = api.util.getDefaultYearDuration()
	local maxWait = math.max(StuckFactor * year / production.RuleCapacity / productivity, StuckMinYearShare * year)
	for _, ruleData in ipairs(stockList.ruleDatas or {}) do
		local last : Engine.Component.StockList.RuleData.ApplyInfo = nil
		for _, apply in ipairs(ruleData.applyHistory or {}) do
			if last == nil or apply.time > last.time then
				last = apply
			end
		end
		if last ~= nil and last.time + last.interval - now > maxWait then
			return true
		end
	end
	return false
end

--- Sets the productivity of every mailbox from its residents and businesses. With checkStuck (every ScanEveryPasses
--- passes: a stuck rule shows only after minutes) returns the drop boxes whose rule is stuck (isStuck): they are built
--- again.
local function produce(s : PdState, days : number, now : integer, parcel : CargoTypeId, checkStuck : boolean) : {Engine.Entity}
	local stuck : {Engine.Entity} = {}
	local perResidentPerDay = ParcelsPerResidentPerDay * rate(RateParam)
	local perSuppliedUnit = ParcelsPerSuppliedUnit * rate(BusinessRateParam)
	-- the consumption of the businesses and the production since the last pass (the history before the first pass is
	-- not counted)
	local from = s.consumedUntil or -1
	local countBusiness = businessParcels() and from >= 0
	s.consumedUntil = now
	for _, box in pairs(s.boxes) do
		-- the parcels of the businesses: their consumption of this pass, averaged over about a month
		if countBusiness and days > 0 then
			local units = 0
			for _, stockList in ipairs(box.suppliers or {}) do
				units = units + consumedBetween(stockList, from, now)
			end
			box.supplied = (box.supplied or 0) + units
			local perDay = units * perSuppliedUnit / days
			box.businessPerDay = (box.businessPerDay or 0) + (perDay - (box.businessPerDay or 0)) * math.min(1, days / BusinessAverageDays)
		elseif not businessParcels() then
			box.businessPerDay = 0
		end
		-- the parcels per year of the residents in the range and of the businesses
		box.perYear = (box.residents or 0) * perResidentPerDay * 365 + (box.businessPerDay or 0) * 365
		if pd_debug.Enabled then
			box.room = reachableRoom(s, box, parcel)
		end
		-- The rule of the stock produces like an industry, production.RuleCapacity parcels per year at productivity 1, so
		-- the productivity is the share of that (DefaultProductivity without parcels).
		-- the stock list of a box removed since the last scan no longer exists (getComponent throws then)
		local stockList = box.stockList >= 0 and api.engine.entityExists(box.stockList)
			and api.engine.getComponent(box.stockList, api.type.ComponentType.STOCK_LIST) as Engine.Component.StockList or nil
		local productivity = box.perYear > 0 and box.perYear / production.RuleCapacity or DefaultProductivity
		if checkStuck and stockList ~= nil and box.drop and isStuck(stockList, productivity, now) then
			stuck[#stuck + 1] = box.source
		end
		if stockList ~= nil then
			-- compared with the productivity the stock list has: a rebuilt stock starts again at 1
			local last = stockList.modifiers ~= nil and stockList.modifiers.productivity or -1
			if last <= 0 or math.abs(productivity - last) > ProductivityTolerance * math.max(last, productivity) then
				local modifiers = api.type.StockList.Modifiers.new()
				modifiers.productivity = productivity
				api.cmd.sendCommand(api.cmd.makeStockListSetModifiersCmd(box.stockList, modifiers))
			end
			box.productivity = productivity
			if pd_debug.Enabled then
				box.produced = (box.produced or 0) + producedBetween(box.stockList, from, now)
			end
		end
	end
	return stuck
end

--- Removes drop boxes (stuck ones): their delivery points get a new one on the next look at the delivery points
--- (pairDeliveryPoints), with tries anew; the parcels in their stock are lost.
local function rebuildDropBoxes(s : PdState, mailboxes : {Engine.Entity})
	for _, mailbox in ipairs(mailboxes) do
		removeConstruction(mailbox)
		s.boxes[mailbox] = nil
		for point, paired in pairs(s.pointBoxes or {}) do
			if paired == mailbox then
				s.pointBoxes[point] = nil
				s.pointAttempts[point] = nil
			end
		end
		info(string.format("[parcel_delivery] drop box %d: its rule waits for a parcel far ahead, built again", mailbox))
	end
	if #mailboxes > 0 then
		-- the town buildings counted for them are counted again on the next pass
		s.townShares = {}
	end
end

-- diagnostics --------------------------------------------------------------------------------------------------------

--- What becomes of the parcels that leave the stocks: the cargo entities in every stock are compared with those of the
--- previous pass. One that is gone either still exists (taken by a vehicle or moved to a station) or was destroyed;
--- its target at the time it was seen tells whether it had a destination.
local function trackCargo(s : PdState)
	for _, box in pairs(s.boxes) do
		if box.stockList >= 0 then
			local now : {Engine.Entity : Engine.Entity} = {}
			for _, item in ipairs(api.engine.system.simEntityAtStockSystem.getStockEntities(box.stockList, 0) or {}) do
				local entity = item[2]
				local cargo = api.engine.getComponent(entity, api.type.ComponentType.SIM_CARGO) as Engine.Component.SimCargo
				now[entity] = cargo ~= nil and cargo.targetOrPickupEntity or -1
			end
			for entity, target in pairs(box.cargoSeen or {}) do
				if now[entity] == nil then
					-- getComponent throws for an entity that no longer exists
					local exists, cargo = pcall(function() : any
						return api.engine.getComponent(entity, api.type.ComponentType.SIM_CARGO)
					end)
					if exists and cargo ~= nil then
						s.leftMoved = (s.leftMoved or 0) + 1
					elseif target ~= nil and target >= 0 then
						s.leftDestroyedWithTarget = (s.leftDestroyedWithTarget or 0) + 1
					else
						s.leftDestroyedNoTarget = (s.leftDestroyedNoTarget or 0) + 1
					end
				end
			end
			box.cargoSeen = now
		end
	end
end

--- which stations have the parcel stocks of the sources in their cargo catchment (a station only loads from those)
local function logCatchment(s : PdState)
	local catchingStations : {Engine.Entity : {string}} = {}
	local stockOf : {Engine.Entity : Engine.Entity} = {}
	for mailbox, box in pairs(s.boxes) do
		if box.stockList >= 0 then
			stockOf[box.stockList] = mailbox
			catchingStations[box.stockList] = {}
		end
	end
	local stations = 0
	local ok, err = pcall(function() : boolean
		api.engine.forEachEntityWithComponent(function(station : Engine.Entity)
			stations = stations + 1
			for _, entity in ipairs(api.engine.system.catchmentAreaSystem.getStationCatchables(station, true) or {}) do
				if stockOf[entity] ~= nil then
					table.insert(catchingStations[entity], tostring(station))
				end
			end
		end, api.type.ComponentType.STATION)
		return true
	end)
	local parts : {string} = {}
	for stockList, mailbox in pairs(stockOf) do
		parts[#parts + 1] = string.format("mailbox %d stock %d (%d parcels): stations [%s]", mailbox, stockList,
			api.engine.system.simEntityAtStockSystem.getStockCount(stockList, 0) or 0, table.concat(catchingStations[stockList], " "))
	end
	log.message(string.format("[parcel_delivery] catchment of the sources (%d stations%s): %s", stations,
		ok and "" or (", failed: " .. tostring(err)), table.concat(parts, "; ")))
	-- the drop boxes (a trial): what the game made of them, and what the stations around them catch of them
	local okDrop, errDrop = pcall(function() : boolean
		for mailbox, box in pairs(s.boxes) do
			if box.drop and box.position ~= nil then
				local construction = api.engine.getComponent(mailbox, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
				local subs : {Engine.Entity : boolean} = {}
				local kinds : {string} = {}
				for _, sub in ipairs(construction ~= nil and construction.subconstructions or {}) do
					subs[sub] = true
					local has : {string} = {}
					if api.engine.getComponent(sub, api.type.ComponentType.STOCK_LIST) ~= nil then table.insert(has, "stock list") end
					if api.engine.getComponent(sub, api.type.ComponentType.WAREHOUSE) ~= nil then table.insert(has, "warehouse") end
					kinds[#kinds + 1] = tostring(sub) .. " (" .. table.concat(has, ", ") .. ")"
				end
				subs[mailbox] = true
				local near : {string} = {}
				api.engine.forEachEntityWithComponent(function(station : Engine.Entity)
					local constructionOfStation = api.engine.system.streetConnectorSystem.getConstructionEntityForStation(station)
					local p : Vec3f = nil
					if constructionOfStation ~= nil and constructionOfStation >= 0 then
						p = positionOf(constructionOfStation)
					else
						-- the street stops (delivery points) are edge objects
						local eo = api.engine.getComponent(station, api.type.ComponentType.EDGE_OBJECT) as Engine.Component.EdgeObject
						if eo ~= nil then
							p = eo.transf:getTransl()
						end
					end
					local catchables = api.engine.system.catchmentAreaSystem.getStationCatchables(station, true) or {}
					local hits = 0
					-- the kinds of the catchables: the file of their construction (a warehouse placed off the streets next
					-- to the stop shows whether such constructions are caught at all)
					local files : {string : integer} = {}
					for _, entity in ipairs(catchables) do
						if subs[entity] then
							hits = hits + 1
						end
						local c = api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction(entity)
						local con = c ~= nil and c >= 0 and api.engine.getComponent(c, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction or nil
						local file = con ~= nil and (string.match(tostring(con.fileName), "([^/]+)$") or "?") or "no construction"
						if api.engine.getComponent(entity, api.type.ComponentType.TOWN_BUILDING) ~= nil or (con ~= nil and #(con.townBuildings or {}) > 0) then
							file = "town building"
						end
						files[file] = (files[file] or 0) + 1
					end
					local kindsCaught : {string} = {}
					for file, n in pairs(files) do
						kindsCaught[#kindsCaught + 1] = file .. " x" .. tostring(n)
					end
					local d = p ~= nil and math.sqrt((p.x - box.position[1]) ^ 2 + (p.y - box.position[2]) ^ 2) or -1
					if hits > 0 or (d >= 0 and d < 200) then
						near[#near + 1] = string.format("station %d (%.0f m, %d catchables, %d of the box: %s)", station, d, #catchables, hits,
							table.concat(kindsCaught, " "))
					end
				end, api.type.ComponentType.STATION)
				log.message(string.format("[parcel_delivery] drop box %d: subconstructions %s; stations: %s", mailbox,
					table.concat(kinds, ", "), table.concat(near, ", ")))
			end
		end
		return true
	end)
	if not okDrop then
		log.message("[parcel_delivery] drop box diagnostics failed: " .. tostring(errDrop))
	end
end

--- the stock lists of the intercity parcel sorting centers (parcel_sorting.script.tl) with their construction
local function sortingStockLists() : {Engine.Entity : Engine.Entity}
	local subs : {Engine.Entity : Engine.Entity} = {}
	api.engine.system.streetConnectorSystem.forEachConstructionWithMetadata(production.SortingMetadata, false, true,
		function(constructionEntity : Engine.Entity, construction : Engine.Component.Construction, _id : ConstructionId)
			for _, sub in ipairs(construction.subconstructions or {}) do
				if api.engine.getComponent(sub, api.type.ComponentType.STOCK_LIST) ~= nil then
					subs[sub] = constructionEntity
				end
			end
		end)
	return subs
end

--- The workers boost of the sorting centers is fixed: the industry_workers script of the base game sets the boost from
--- the workersBoostFactor of the construction (parcel_sorting.script.tl), and a random one between 1.5 and 2.5 if it
--- does not find it. A boosted sorting center is set to the fixed boost; one without enough workers stays at 1.
local function fixSortingBoost() : boolean
	for sub in pairs(sortingStockLists()) do
		local stockList = api.engine.getComponent(sub, api.type.ComponentType.STOCK_LIST) as Engine.Component.StockList
		local productivity = stockList ~= nil and stockList.modifiers ~= nil and stockList.modifiers.productivity or 1
		if productivity > 1 and math.abs(productivity - production.SortingBoostFactor) > 0.01 then
			local modifiers = api.type.StockList.Modifiers.new()
			modifiers.productivity = production.SortingBoostFactor
			api.cmd.sendCommand(api.cmd.makeStockListSetModifiersCmd(sub, modifiers))
			info(string.format("[parcel_delivery] sorting center %d: workers boost %.2f set to %.2f", sub, productivity,
				production.SortingBoostFactor))
		end
	end
	return true
end

--- The intercity parcel sorting centers (parcel_sorting.script.tl): what is in their stocks, how often their rule has
--- converted, and how many stations have them in their catchment (the stations load and unload their stocks).
local function logSorting() : boolean
	local parts : {string} = {}
	local stationsOf : {Engine.Entity : integer} = {}
	local subs = sortingStockLists()
	for sub in pairs(subs) do
		stationsOf[sub] = 0
	end
	if next(subs) == nil then
		return true
	end
	api.engine.forEachEntityWithComponent(function(station : Engine.Entity)
		for _, entity in ipairs(api.engine.system.catchmentAreaSystem.getStationCatchables(station, true) or {}) do
			if stationsOf[entity] ~= nil then
				stationsOf[entity] = stationsOf[entity] + 1
			end
		end
	end, api.type.ComponentType.STATION)
	for sub, constructionEntity in pairs(subs) do
		local construction = api.engine.getComponent(constructionEntity, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
		local kind = string.find(tostring(construction ~= nil and construction.fileName or ""), "import", 1, true) ~= nil and "import" or "export"
		local stockList = api.engine.getComponent(sub, api.type.ComponentType.STOCK_LIST) as Engine.Component.StockList
		local applies = 0
		for _, ruleData in ipairs(stockList ~= nil and stockList.ruleDatas or {}) do
			applies = applies + #(ruleData.applyHistory or {})
		end
		local stockSystem = api.engine.system.simEntityAtStockSystem
		parts[#parts + 1] = string.format("%s %d: %d in, %d out, %d recent conversions, productivity %.2f, in the catchment of %d stations",
			kind, constructionEntity,
			stockSystem.getStockCount(sub, production.SortingInputStock) or 0,
			stockSystem.getStockCount(sub, production.SortingOutputStock) or 0,
			applies, stockList ~= nil and stockList.modifiers ~= nil and stockList.modifiers.productivity or -1, stationsOf[sub])
	end
	log.message("[parcel_delivery] sorting centers: " .. table.concat(parts, "; "))
	return true
end

local function logSummary(s : PdState, parcel : CargoTypeId, how : string)
	logCatchment(s)
	local okSorting, errSorting = pcall(logSorting)
	if not okSorting then
		log.message("[parcel_delivery] sorting center diagnostics failed: " .. tostring(errSorting))
	end
	local boxes, withSource, residents, inStock, produced = 0, 0, 0, 0, 0
	local suppliers, supplied = 0, 0
	for _, box in pairs(s.boxes) do
		boxes = boxes + 1
		residents = residents + box.residents
		suppliers = suppliers + #(box.suppliers or {})
		supplied = supplied + (box.supplied or 0)
		produced = produced + (box.produced or 0)
		if box.stockList >= 0 then
			withSource = withSource + 1
			inStock = inStock + (api.engine.system.simEntityAtStockSystem.getStockCount(box.stockList, 0) or 0)
		end
	end
	-- residential buildings with a parcel stock and the parcels delivered to them
	local residential, withParcelStock, parcelsAtHomes = 0, 0, 0
	api.engine.forEachEntityWithComponent(function(entity : Engine.Entity)
		local building = api.engine.getComponent(entity, api.type.ComponentType.TOWN_BUILDING) as Engine.Component.TownBuilding
		if building == nil or not isResidential(building.personCapacity) then
			return
		end
		residential = residential + 1
		local stockList = building.stockList ~= nil and building.stockList >= 0
			and api.engine.getComponent(building.stockList, api.type.ComponentType.STOCK_LIST) as Engine.Component.StockList or nil
		for i, stock in ipairs(stockList ~= nil and stockList.stocks or {}) do
			if stock.cargoType == parcel then
				withParcelStock = withParcelStock + 1
				parcelsAtHomes = parcelsAtHomes + (api.engine.system.simEntityAtStockSystem.getStockCount(building.stockList, i - 1) or 0)
			end
		end
	end, api.type.ComponentType.TOWN_BUILDING)
	log.message(string.format("[parcel_delivery] cargo %d; %d mailboxes (found via %s), %d with source, %d residents, %d produced, %d in stock; residential buildings %d, with parcel stock %d, parcels delivered there %d",
		parcel, boxes, how or "-", withSource, residents, produced, inStock, residential, withParcelStock, parcelsAtHomes))
	local reach : {string} = {}
	local now = gameTimeMs()
	for mailbox, box in pairs(s.boxes) do
		local sl = box.stockList >= 0 and api.engine.getComponent(box.stockList, api.type.ComponentType.STOCK_LIST) as Engine.Component.StockList or nil
		-- the productivity the stock list has, and when its rule last made a parcel (whether it produces at all)
		local lastApply, lastInterval, applies, decay = -1, -1, 0, -1.0
		for _, ruleData in ipairs(sl ~= nil and sl.ruleDatas or {}) do
			decay = ruleData.lastApplyDecayFactor or -1
			for _, apply in ipairs(ruleData.applyHistory or {}) do
				applies = applies + 1
				if apply.time > lastApply then
					lastApply, lastInterval = apply.time, apply.interval
				end
			end
		end
		reach[#reach + 1] = string.format("%d: %d residents, %d lines (%d with changes), %d residents in %d homes reachable with room for %.1f parcels, %.0f parcels per year, productivity %.3f (set %.3f), %d applies in the history, the last %s with interval %s, decay factor %.3f, %d stocks and %d rules, %d produced, %d in stock, %.1f pending",
			mailbox, box.residents or 0, box.lines or 0, box.transferLines or 0, box.reachable or 0, #(box.reachableHomes or {}), box.room or -1,
			box.perYear or 0, sl ~= nil and sl.modifiers ~= nil and sl.modifiers.productivity or -1, box.productivity or -1, applies,
			lastApply >= 0 and string.format("%.0f s ago", (now - lastApply) / 1000) or "never",
			lastInterval >= 0 and string.format("%.1f s", lastInterval / 1000) or "-", decay,
			sl ~= nil and #(sl.stocks or {}) or -1, sl ~= nil and #(sl.rules or {}) or -1,
			box.produced or 0, box.stockList >= 0 and (api.engine.system.simEntityAtStockSystem.getStockCount(box.stockList, 0) or 0) or -1,
			box.pending or 0)
	end
	log.message(string.format("[parcel_delivery] radius %.0f m; by line: %s", collectionRadius(), table.concat(reach, "; ")))
	log.message(string.format("[parcel_delivery] parcels that left the stocks: %d moved on, %d destroyed with a target, %d destroyed without",
		s.leftMoved or 0, s.leftDestroyedWithTarget or 0, s.leftDestroyedNoTarget or 0))
	-- where the produced parcels are: cargo with a destination leaves the stock and waits at the stops of the lines
	local waiting, inVehicles, lines = 0, 0, 0
	local okLines, errLines = pcall(function() : boolean
		for _, lineEntity in ipairs(api.engine.system.lineSystem.getLines() or {}) do
			local line = api.engine.getComponent(lineEntity, api.type.ComponentType.LINE) as Engine.Component.Line
			lines = lines + 1
			for i = 1, #(line and line.stops or {}) do
				waiting = waiting + (api.engine.system.simEntityAtTerminalSystem.getLineStopSimEntitiesCount(lineEntity, i - 1, parcel) or 0)
			end
		end
		return true
	end)
	local okVehicles, errVehicles = pcall(function() : boolean
		for _, cargos in pairs(api.engine.system.simEntityAtVehicleSystem.getVehicle2Cargo2SimEntitesMap() or {}) do
			inVehicles = inVehicles + #(cargos[parcel] or {})
		end
		return true
	end)
	log.message(string.format("[parcel_delivery] parcels in transport: %d waiting at the stops of %d lines%s, %d in vehicles%s",
		waiting, lines, okLines and "" or (" (failed: " .. tostring(errLines) .. ")"),
		inVehicles, okVehicles and "" or (" (failed: " .. tostring(errVehicles) .. ")")))
	log.message(string.format("[parcel_delivery] businesses %s: %d commercial and industrial buildings in range, %d units supplied to them",
		businessParcels() and "on" or "off", suppliers, supplied))
	-- the parcel demand of the residential districts against their residents (the demand of the passengers)
	local parts : {string} = {}
	api.engine.forEachEntityWithComponent(function(townEntity : Engine.Entity)
		local capacities = api.engine.system.townBuildingSystem.getLandUsePersonCapacities(townEntity) or {}
		local supplyAndLimit = api.engine.system.townBuildingSystem.getCargoSupplyAndLimit(townEntity, api.type["enum"].LandUseType.RESIDENTIAL) or {}
		local parcels = supplyAndLimit[parcel]
		parts[#parts + 1] = string.format("town %d: %d residents, parcel supply %.1f limit %.1f", townEntity, capacities[1] or 0,
			parcels ~= nil and parcels[1] or -1, parcels ~= nil and parcels[2] or -1)
	end, api.type.ComponentType.TOWN)
	log.message("[parcel_delivery] residential parcel demand: " .. table.concat(parts, "; "))
end

-- game script --------------------------------------------------------------------------------------------------------

--- One update call (every frame); returns the game time, -1 if it was not read. The parts are timed for the perf line.
local function runUpdate(state : GameScriptState<PdState>) : integer
	-- Between two passes the update returns before reading the state (read as a whole): most calls come between
	-- passes. A game time before the last pass seen (a savegame loaded) reads it again.
	local now = gameTimeMs()
	if lastPassSeen >= 0 and now >= lastPassSeen and now - lastPassSeen < PassIntervalMs then
		return now
	end
	local s : PdState
	timed("stateGet", function()
		s = state:get()
	end)
	if s == nil or s.version ~= StateVersion then
		s = newState()
		info("[parcel_delivery] state initialized")
	end
	if s.lastTime < 0 or now < s.lastTime then
		s.lastTime = now
		lastPassSeen = now
		state:set(s)
		return now
	end
	-- the last pass may have run in another Lua state
	lastPassSeen = s.lastTime
	local dt = now - s.lastTime
	if dt < PassIntervalMs then
		return now
	end
	lastPassSeen = now
	s.lastTime = now
	s.passes = (s.passes or 0) + 1

	local parcel = parcelCargoId()
	if parcel < 0 then
		if s.passes % LogEveryPasses == 1 then
			log.message("[parcel_delivery] parcel cargo not found")
		end
		state:set(s)
		return now
	end
	local how : string = nil
	-- every task looked up every ScanEveryPasses passes on a pass of its own (ScanTurn)
	local turn = s.passes % ScanEveryPasses
	if turn == ScanTurn.townNeeds then
		local okNeeds, errNeeds : boolean, any
		timed("townNeeds", function()
			okNeeds, errNeeds = pcall(function() : boolean
				ensureResidentialNeeds(parcel)
				return true
			end)
		end)
		if not okNeeds then
			log.message("[parcel_delivery] town needs failed: " .. tostring(errNeeds))
		end
	end
	if turn == ScanTurn.mailboxes then
		local ok, result : boolean, any
		timed("mailboxes", function()
			ok, result = pcall(updatePosts, s, parcel)
		end)
		if ok then
			how = result as string
		else
			log.message("[parcel_delivery] parcel post update failed: " .. tostring(result))
		end
		-- the street near a new drop box (all streets of the map are looked at, once for every new drop box)
		for mailbox, box in pairs(s.boxes) do
			if box.drop and not box.stopDone then
				local okCheck, errCheck : boolean, any
				timed("dropBoxStreet", function()
					okCheck, errCheck = pcall(function() : boolean
						checkDropBox(mailbox, box)
						return true
					end)
				end)
				if not okCheck then
					box.stopDone = true
					log.message("[parcel_delivery] checking drop box " .. tostring(mailbox) .. " failed: " .. tostring(errCheck))
				end
			end
		end
	end
	if turn == ScanTurn.deliveryPoints then
		local okPair, errPair : boolean, any
		timed("deliveryPoints", function()
			okPair, errPair = pcall(function() : boolean
				pairDeliveryPoints(s)
				return true
			end)
		end)
		if not okPair then
			log.message("[parcel_delivery] drop boxes of the delivery points failed: " .. tostring(errPair))
		end
	end
	-- the towns of this pass (every pass)
	local okTowns, errTowns : boolean, any
	timed("townBuildings", function()
		okTowns, errTowns = pcall(scanTowns, s)
	end)
	if not okTowns then
		log.message("[parcel_delivery] town buildings failed: " .. tostring(errTowns))
	end
	if turn == ScanTurn.reachable then
		if pd_debug.Enabled then
			local okReach, errReach : boolean, any
			timed("reachable", function()
				okReach, errReach = pcall(function() : boolean
					updateReachable(s, collectHomes())
					return true
				end)
			end)
			if not okReach then
				log.message("[parcel_delivery] reachable residents failed: " .. tostring(errReach))
			end
		else
			-- the diagnostics of a debug version are not kept in the state
			s.homeShares = nil
			for _, box in pairs(s.boxes) do
				box.cargoSeen = nil
				box.reachableHomes = nil
			end
		end
	end
	if turn == ScanTurn.sortingBoost then
		local okBoost, errBoost : boolean, any
		timed("sortingBoost", function()
			okBoost, errBoost = pcall(fixSortingBoost)
		end)
		if not okBoost then
			log.message("[parcel_delivery] sorting center boost failed: " .. tostring(errBoost))
		end
	end
	if pd_debug.Enabled then
		local okTrack, errTrack : boolean, any
		timed("cargoTracking", function()
			okTrack, errTrack = pcall(function() : boolean
				trackCargo(s)
				return true
			end)
		end)
		if not okTrack and s.passes % LogEveryPasses == 1 then
			log.message("[parcel_delivery] cargo tracking failed: " .. tostring(errTrack))
		end
	end
	-- the parts below may fail like the others without keeping the state from being saved
	local okProduce, errProduce : boolean, any
	local stuck : {Engine.Entity} = {}
	timed("production", function()
		okProduce, errProduce = pcall(function() : boolean
			stuck = produce(s, dt / millisPerDay(), now, parcel, turn == ScanTurn.stuckRules)
			rebuildDropBoxes(s, stuck)
			return true
		end)
	end)
	perfCount("stuckDropBoxesRebuilt", #stuck)
	if not okProduce then
		log.message("[parcel_delivery] production failed: " .. tostring(errProduce))
	end
	if pd_debug.Enabled and s.passes % LogEveryPasses == 1 then
		local okSummary, errSummary : boolean, any
		timed("summaryLog", function()
			okSummary, errSummary = pcall(function() : boolean
				logSummary(s, parcel, how)
				return true
			end)
		end)
		if not okSummary then
			log.message("[parcel_delivery] summary log failed: " .. tostring(errSummary))
		end
	end
	-- the size of the state (read and written as a whole): the mailboxes and the diagnostics kept in it
	local cargoSeen, reachableHomes, boxes = 0, 0, 0
	for _, box in pairs(s.boxes) do
		boxes = boxes + 1
		for _ in pairs(box.cargoSeen or {}) do
			cargoSeen = cargoSeen + 1
		end
		reachableHomes = reachableHomes + #(box.reachableHomes or {})
	end
	perfCount("boxes", boxes)
	perfCount("stateCargoSeen", cargoSeen)
	perfCount("stateReachableHomes", reachableHomes)
	timed("stateSet", function()
		state:set(s)
	end)
	return now
end

local script = {
	update = function(_userParams : table, state : GameScriptState<PdState>, _dt : number) : any
		local t0 = clock ~= nil and clock() or 0
		-- An error must not leave the update: the game runs the script in its simulation step, and an error there kept the
		-- drop boxes from producing (and, as the state was not saved, the same pass and the same error came again).
		local ok, result = pcall(runUpdate, state)
		local now = ok and result as integer or -1
		if not ok then
			log.message("[parcel_delivery] update failed: " .. tostring(result))
		end
		if clock ~= nil then
			perfAdd("update", clock() - t0)
		end
		perf.frames = perf.frames + 1
		if now >= 0 then
			if perf.since < 0 or now < perf.since then
				perf.since = now
				perf.sinceClock = clock ~= nil and clock() or 0
				perf.frames = 0
				perf.parts = {}
			elseif now - perf.since >= PerfLogMs then
				perfLog(now)
			end
		end
	end,
}

return script
