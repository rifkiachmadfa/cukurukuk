--!strict
--[[
	CookingTypes — shared type definitions for Cooking & Serving (Phase 4).
	Types only; no runtime logic.
]]

export type PortionStage = "NeedBox" | "NeedChicken" | "NeedSmash" | "NeedSambal"

export type CookingConfig = {
	-- Workspace objects (names are the ones the map already uses). Resolved once at start.
	StationRootPath: { string }, -- Workspace folder searched FIRST for the objects below (falls back to all of Workspace)
	FoodBoxName: string, -- Workspace part holding the FoodBox ProximityPrompt
	ChickenName: string, -- Workspace part holding the Chicken ProximityPrompt
	GeprekName: string, -- Workspace model/part (geprek station) holding the Geprek ProximityPrompt
	TrayPlacementName: string, -- Workspace part where FoodBox + finished geprek are placed
	TrayPromptName: string, -- ProximityPrompt (or a part containing one) used to serve
	SambalFolderPath: { string }, -- Workspace path of the folder with the sambal parts
	SambalStations: { [string]: string }, -- station part name -> sambalId (must exist in OrderConfig.Sambal)

	-- ServerStorage templates (Models)
	FoodBoxTemplatePath: { string }, -- ServerStorage.FoodBox
	ChickenTemplatePath: { string }, -- ServerStorage.Models.Chicken

	-- Placement. ASSUMPTION / TUNABLE CONFIG
	TrayPortionSpacing: Vector3, -- offset between portions on the tray (local to TrayPlacement)
	TrayPlacementOffset: Vector3, -- offset of the first box from the TrayPlacement centre (local)
	ChickenOnBoxOffset: Vector3, -- offset of the chicken above its box (local to TrayPlacement)
	GeprekChickenOffset: Vector3, -- offset of the chicken above the geprek station pivot (world up)
	SmashScale: number, -- visual scale applied when smashed (1 = no change)

	-- Validation. ASSUMPTION / TUNABLE CONFIG
	StepCooldownSeconds: number, -- per-player cooldown between cooking steps
	DistanceSlack: number, -- studs added to prompt.MaxActivationDistance for the server-side check
	ResolveTimeoutSeconds: number, -- how long start-up waits for world objects before warning
	ServeCleanupDelaySeconds: number, -- served food stays visible this long before props are removed
	HintSeconds: number, -- how long an error/hint message stays on the tray hint
	ShowHint: boolean, -- BillboardGui on TrayPlacement (no client script needed)
}

export type FailReason = "WrongSambal" | "WrongCount"

return {}
