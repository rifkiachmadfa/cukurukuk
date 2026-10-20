--!strict
--[[
	CookingStations — finds the world objects and ServerStorage templates the cooking flow needs (Phase 4).

	Everything is looked up by NAME from CookingConfig (no names hard-coded in other scripts), once,
	and returned as one typed table. Resolve() never throws: it returns (stations, {}) when complete or
	(nil, missingDescriptions) so the caller can retry / print a useful message.

	Map contract (see ai/PHASE_4_COOKING.md):
		Objects below are searched in Workspace.Stasion first, then anywhere in Workspace:
		FoodBox            (part)  + ProximityPrompt
		Chicken            (part)  + ProximityPrompt   (e.g. Workspace.Stasion.Chicken)
		Geprek             (model) + ProximityPrompt
		Workspace.Stasion.Sambal.{Hijau,Korek,Matah,Original} (parts) + ProximityPrompt each
		Workspace.TrayPlacement      (part)
		Workspace.Tray               (ProximityPrompt, or a part/model containing one)
		ServerStorage.FoodBox        (Model)
		ServerStorage.Models.Chicken (Model)
]]

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CookingTypes = require(ReplicatedStorage.Shared.Types.CookingTypes)
local OrderTypes = require(ReplicatedStorage.Shared.Types.OrderTypes)

local CookingStations = {}

export type Stations = {
	foodBoxPrompt: ProximityPrompt,
	chickenPrompt: ProximityPrompt,
	geprekPrompt: ProximityPrompt,
	geprekAnchor: Instance, -- Model or BasePart that owns the geprek station
	trayPlacement: BasePart,
	trayPrompt: ProximityPrompt,
	sambalPrompts: { [string]: ProximityPrompt }, -- sambalId -> prompt
	foodBoxTemplate: Model,
	chickenTemplate: Model,
}

local function findPrompt(root: Instance?): ProximityPrompt?
	if root == nil then
		return nil
	end
	if root:IsA("ProximityPrompt") then
		return root
	end
	return root:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function findByPath(root: Instance, path: { string }): Instance?
	local current: Instance? = root
	for _, segment in path do
		if current == nil then
			return nil
		end
		current = current:FindFirstChild(segment)
	end
	return current
end

function CookingStations.Resolve(cfg: CookingTypes.CookingConfig, orderConfig: OrderTypes.OrderConfig): (Stations?, { string })
	local missing: { string } = {}

	-- Search Workspace.<StationRootPath> first (e.g. Workspace.Stasion), then all of Workspace.
	-- First match wins; keep these names unique in the map.
	local scopeRoot = findByPath(workspace, cfg.StationRootPath)
	local function findInWorkspace(name: string): Instance?
		local inScope = if scopeRoot then scopeRoot:FindFirstChild(name, true) else nil
		return inScope or workspace:FindFirstChild(name, true)
	end

	local function need<T>(value: T?, description: string): T?
		if value == nil then
			table.insert(missing, description)
		end
		return value
	end

	local foodBoxRoot = findInWorkspace(cfg.FoodBoxName)
	local foodBoxPrompt = need(findPrompt(foodBoxRoot), `Workspace "{cfg.FoodBoxName}" + ProximityPrompt`)

	local chickenRoot = findInWorkspace(cfg.ChickenName)
	local chickenPrompt = need(findPrompt(chickenRoot), `Workspace "{cfg.ChickenName}" + ProximityPrompt`)

	local geprekRoot = findInWorkspace(cfg.GeprekName)
	local geprekPrompt = need(findPrompt(geprekRoot), `Workspace "{cfg.GeprekName}" + ProximityPrompt`)
	local geprekAnchor: Instance? = nil
	if geprekRoot then
		geprekAnchor = if geprekRoot:IsA("ProximityPrompt") then geprekRoot.Parent else geprekRoot
	end

	local trayPlacementInstance = findInWorkspace(cfg.TrayPlacementName)
	local trayPlacement: BasePart? = nil
	if trayPlacementInstance and trayPlacementInstance:IsA("BasePart") then
		trayPlacement = trayPlacementInstance
	else
		table.insert(missing, `Workspace "{cfg.TrayPlacementName}" (harus BasePart)`)
	end

	-- Prefer a ProximityPrompt literally named "Tray"; otherwise any instance named "Tray" that contains one.
	local trayPrompt: ProximityPrompt? = nil
	for _, searchRoot in { scopeRoot or workspace, workspace } do
		for _, instance in searchRoot:GetDescendants() do
			if instance.Name == cfg.TrayPromptName and instance:IsA("ProximityPrompt") then
				trayPrompt = instance
				break
			end
		end
		if trayPrompt then
			break
		end
	end
	if trayPrompt == nil then
		trayPrompt = findPrompt(findInWorkspace(cfg.TrayPromptName))
	end
	need(trayPrompt, `Workspace ProximityPrompt "{cfg.TrayPromptName}"`)

	local sambalFolder = findByPath(workspace, cfg.SambalFolderPath)
	local sambalPrompts: { [string]: ProximityPrompt } = {}
	if sambalFolder == nil then
		table.insert(missing, "Workspace." .. table.concat(cfg.SambalFolderPath, "."))
	else
		for stationName, sambalId in cfg.SambalStations do
			if orderConfig.Sambal[sambalId] == nil then
				table.insert(missing, `CookingConfig.SambalStations["{stationName}"] -> "{sambalId}" tidak ada di OrderConfig.Sambal`)
			else
				local prompt = findPrompt(sambalFolder:FindFirstChild(stationName))
				if prompt then
					sambalPrompts[sambalId] = prompt
				else
					table.insert(missing, `Workspace.{table.concat(cfg.SambalFolderPath, ".")}.{stationName} + ProximityPrompt`)
				end
			end
		end
	end

	local foodBoxTemplate = findByPath(ServerStorage, cfg.FoodBoxTemplatePath)
	if foodBoxTemplate == nil or not foodBoxTemplate:IsA("Model") then
		foodBoxTemplate = nil
		table.insert(missing, "ServerStorage." .. table.concat(cfg.FoodBoxTemplatePath, ".") .. " (Model)")
	end
	local chickenTemplate = findByPath(ServerStorage, cfg.ChickenTemplatePath)
	if chickenTemplate == nil or not chickenTemplate:IsA("Model") then
		chickenTemplate = nil
		table.insert(missing, "ServerStorage." .. table.concat(cfg.ChickenTemplatePath, ".") .. " (Model)")
	end

	if #missing > 0 then
		return nil, missing
	end

	return {
		foodBoxPrompt = foodBoxPrompt :: ProximityPrompt,
		chickenPrompt = chickenPrompt :: ProximityPrompt,
		geprekPrompt = geprekPrompt :: ProximityPrompt,
		geprekAnchor = geprekAnchor :: Instance,
		trayPlacement = trayPlacement :: BasePart,
		trayPrompt = trayPrompt :: ProximityPrompt,
		sambalPrompts = sambalPrompts,
		foodBoxTemplate = foodBoxTemplate :: Model,
		chickenTemplate = chickenTemplate :: Model,
	}, missing
end

return CookingStations
