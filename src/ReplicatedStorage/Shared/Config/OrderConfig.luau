--!strict
--[[
	OrderConfig — all OrderSystem tunables (Phase 3).
	Values marked "TUNABLE CONFIG" are ASSUMPTIONS that need playtesting; the GDD does not fix them.
	Hard rules from the project owner: max 3 geprek per order, max 2 minutes working time.
]]

local OrderTypes = require(script.Parent.Parent.Types.OrderTypes)

local config: OrderTypes.OrderConfig = {
	-- Owner rules ---------------------------------------------------------
	MaxGeprekPerOrder = 3, -- total geprek portions in ONE order
	WorkTimeLimitSeconds = 120, -- max working time: Accepted -> Served (2 minutes)

	-- Structure -----------------------------------------------------------
	MaxLinesPerOrder = 3, -- distinct (recipe, sambal) lines

	-- ASSUMPTION / TUNABLE CONFIG ------------------------------------------
	PresentedTimeoutSeconds = 60, -- how long a customer waits for Accept/Refuse
	MaxInteractDistance = 14, -- studs, server-validated
	ActionCooldownSeconds = 0.4, -- per-player cooldown for order actions
	MaxIdLength = 64,
	MaxFinishedHistory = 50, -- finished orders kept for duplicate guards

	DefaultRecipeId = "ayam_geprek",

	Recipes = {
		-- Rp15.000 is an ASSUMPTION. Rp5.000.000 / 7 days needs ~48 portions/day at this price.
		ayam_geprek = { displayName = "Ayam Geprek", basePrice = 15000, isGeprek = true },
	},

	Sambal = {
		tidak_pedas = { displayName = "Tidak Pedas", extraPrice = 0, weight = 2 },
		sedang = { displayName = "Sedang", extraPrice = 0, weight = 4 },
		pedas = { displayName = "Pedas", extraPrice = 1000, weight = 3 },
		extra_pedas = { displayName = "Extra Pedas", extraPrice = 2000, weight = 1 },
	},
	-- Deterministic iteration order (also display order).
	SambalOrder = { "tidak_pedas", "sedang", "pedas", "extra_pedas" },

	-- Chance weights for portions per generated order (keys must be 1..MaxGeprekPerOrder).
	PortionWeights = { [1] = 5, [2] = 3, [3] = 2 },

	-- World screen ----------------------------------------------------------
	Screen = {
		PartName = "screen", -- Workspace part (matched case-insensitively)
		Face = "Front", -- Enum.NormalId the SurfaceGui is placed on
		ResultDisplaySeconds = 3,
	},

	-- Remote contract (see ai/PHASE_3_ORDERSYSTEM.md) ----------------------
	Remotes = {
		FolderName = "OrderRemotes",
		ActionFunction = "RequestOrderAction", -- client -> server intent
		SnapshotFunction = "RequestOrderSnapshot", -- client -> server read
		UpdateEvent = "OrderUpdated", -- server -> client summary push
	},

	-- Development only (ignored outside Roblox Studio) ----------------------
	Debug = {
		EnableDevHarness = true,
		DevAutoCookSeconds = 5, -- simulates Phase 4 cooking so Serve can be tested
		DevNextOrderDelaySeconds = 4,
		RunSelfTest = true,
	},
}

return config
