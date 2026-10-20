--!strict
--[[
	CookingConfig — Phase 4 tunables + workspace/ServerStorage names.
	Names below mirror the map the project owner already built. If the map is renamed, change it HERE only.
	Values marked ASSUMPTION / TUNABLE CONFIG are not fixed by the GDD and need playtesting.
]]

local CookingTypes = require(script.Parent.Parent.Types.CookingTypes)

local config: CookingTypes.CookingConfig = {
	StationRootPath = { "Stasion" },
	ChickenPath = { "Stasion", "Chicken" }, -- Workspace.Stasion.Chicken
	GeprekPath = { "Stasion", "Geprek" }, -- Workspace.Stasion.Geprek (part/model that owns the Geprek ProximityPrompt)
	FoodBoxName = "FoodBox",
	ChickenName = "Chicken",
	GeprekName = "Geprek",
	TrayPlacementName = "TrayPlacement",
	TrayPromptName = "Tray",
	SambalFolderPath = { "Stasion", "Sambal" },
	SambalStations = {
		Hijau = "hijau",
		Korek = "korek",
		Matah = "matah",
		Original = "original",
	},

	FoodBoxTemplatePath = { "Models", "Foodbox" },
	ChickenTemplatePath = { "Models", "Chicken" },

	-- ASSUMPTION / TUNABLE CONFIG (adjust to the real size of your models)
	TrayPortionSpacing = Vector3.new(2.5, 0, 0),
	TrayPlacementOffset = Vector3.new(0, 0.5, 0),
	ChickenOnBoxOffset = Vector3.new(0, 0, 0),
	GeprekChickenOffset = Vector3.new(0,5, -0,2, -0.7),
	SmashScale = 0

	StepCooldownSeconds = 0.3,
	DistanceSlack = 6,
	ResolveTimeoutSeconds = 10,
	ServeCleanupDelaySeconds = 1.5,
	HintSeconds = 3,
	ShowHint = true,
}

return config
