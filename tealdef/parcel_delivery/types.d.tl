recordDef = true

--- A parcel mailbox (street stop) with its hidden parcel source.
global record PdBox
	--- construction entity of the hidden parcel source (parcel_source.con.lua), -1 while it is missing
	source : Engine.Entity
	--- stock list entity of the parcel stock of the source, -1 while it is missing
	stockList : Engine.Entity
	--- world position of the mailbox {x, y, z}
	position : {number}
	--- residents (residential capacity) of the town buildings within the service range
	residents : integer
	--- residents the lines stopping at the mailbox can deliver to (outside the catchment of its own stations)
	reachable : integer
	--- the stock lists of the residential buildings the lines reach, and their free room for parcels (shared with the
	--- other mailboxes reaching them)
	reachableHomes : {Engine.Entity}
	room : number
	--- lines stopping at the stations of the mailbox, and all lines the parcels can use with changes (diagnostics)
	lines : integer
	transferLines : integer
	--- stock list entities of the commercial and industrial town buildings within the service range
	suppliers : {Engine.Entity}
	--- cargo units consumed by the suppliers in total (diagnostics)
	supplied : integer
	--- parcels produced but not yet put into the stock (less than one)
	pending : number
	--- parcels per year the stock should produce (residents and businesses), and the productivity set for it
	perYear : number
	productivity : number
	--- parcels per day of the businesses (averaged)
	businessPerDay : number
	--- a parcel drop box (parcel_drop.con), the attempts to add its delivery point and whether that is settled
	drop : boolean
	stopAttempts : integer
	stopDone : boolean
	--- game time (ms) the construction was built: a building in the range of several mailboxes counts for the first one
	builtAt : integer
	--- the amount the stock was set to last, -1 or nil if never
	lastSet : integer
	--- game time (ms) of the last write into a stock that was not empty
	lastWrite : integer
	--- diagnostics: the cargo entities seen in the stock with their target (-1 none)
	cargoSeen : {Engine.Entity : Engine.Entity}
	--- parcels put into the stock in total (diagnostics)
	produced : integer
	--- pass in which the source was last requested, -1 if never
	requested : integer
end

--- Game script state (parcel_delivery.script.tl).
global record PdState
	version : integer
	--- mailboxes by their edge object entity
	boxes : {Engine.Entity : PdBox}
	--- game time (ms) of the last pass
	lastTime : integer
	--- number of passes so far (log and search intervals)
	passes : integer
	--- number of mailboxes whose lines reach a residential building, by its stock list
	homeShares : {Engine.Entity : integer}
	--- line stops ("line:stationGroup") whose loading of parcels a previous version switched off (no longer used)
	blockedStops : {string : boolean}
	--- the drop box of every parcel delivery point (edge object of the stop -> construction), and the tries to build one
	pointBoxes : {Engine.Entity : Engine.Entity}
	pointAttempts : {Engine.Entity : integer}
	pointAttemptsVersion : integer
	--- the delivery points have to be looked for again: set after a build proposal of the player and while a requested
	--- drop box is not paired yet
	pointsDirty : boolean
	--- the town buildings are scanned on the next pass (a new mailbox was found)
	buildingsDirty : boolean
	--- diagnostics: parcels that left a stock, by what became of them
	leftDestroyedNoTarget : integer
	leftDestroyedWithTarget : integer
	leftMoved : integer
	--- diagnostics: reads of the stock count above / below the amount set last
	readsHigh : integer
	readsLow : integer
	--- game time (ms) up to which the consumption of the commercial and industrial buildings is counted, -1 if not yet
	consumedUntil : integer
end

--- parcel_delivery/debug.tl
global record PdDebug
	Enabled : boolean
end

--- parcel_delivery/production.tl
global record PdProduction
	ParcelCargo : string
	ParcelClass : string
	OutputStock : integer
	Capacity : integer
	RuleCapacity : number
	DropMetadata : string
	IntercityCargo : string
	SortingMetadata : string
	SortingInputStock : integer
	SortingOutputStock : integer
	SortingInputCapacity : integer
	SortingOutputCapacity : integer
	SortingRuleCapacity : number
	SortingWorkers : integer
	SortingBoostFactor : number
	stocks : function() : {table}
	rules : function() : {table}
	sortingStocks : function(export : boolean) : {table}
	sortingRules : function(export : boolean) : {table}
end

recordDef = false
