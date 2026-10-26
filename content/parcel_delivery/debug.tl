-- Debug switch of the mod. With Enabled, the game script keeps its diagnostics (where the parcels go, the residents the
-- lines reach, the stations covering the stocks) and writes them and its other messages to the log; without it, only
-- the errors are logged and the diagnostics are not computed. tools\deploy.ps1 -Release deploys a copy with Enabled
-- false; the project keeps true.

local pd_debug : PdDebug = {
	Enabled = true,
}

return pd_debug
