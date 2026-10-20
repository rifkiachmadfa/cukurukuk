--!strict
--[[
	CookingService — Phase 4: player cooks at the world stations, server validates every step.

	Flow per portion (repeated until the tray holds every portion of the order):
		1. FoodBox prompt  -> clones ServerStorage.FoodBox onto TrayPlacement
		2. Chicken prompt  -> clones ServerStorage.Models.Chicken into the Geprek station
		3. Geprek prompt   -> smashes the chicken
		4. Sambal prompt   -> (Hijau / Korek / Matah / Original) chicken is packed into the box on the tray
	Then the Tray prompt serves the whole tray:
		- tray matches the order  -> order Cooking -> Ready -> Served
		- tray does NOT match     -> tray is cleared and the player restarts from step 1
		  (the order stays Cooking and its 2-minute work timer keeps running; nothing is refused or paid)

	Authority: the client sends nothing. ProximityPrompt.Triggered fires on the server; this service
	checks cooldown, character, distance, step order and order status, and reads the expected sambal
	from OrderService (never from the player). Rewards/reputation are NOT applied here (Phase 5 listens
	to OrderService.OrderChanged).

	Order binding: the first FoodBox press binds the player to the OLDEST order in status Accepted and
	moves it to Cooking. One order = one session. MVP assumes one cook at a time (single-player).

	Session cleanup: when the bound order reaches Served / Refused / Cancelled / Expired, every prop
	clone is destroyed (Served after CookingConfig.ServeCleanupDelaySeconds).

	Public API: Start(orderService, orderConfig, cookingConfig) -> { Destroy }.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OrderTypes = require(ReplicatedStorage.Shared.Types.OrderTypes)
local CookingTypes = require(ReplicatedStorage.Shared.Types.CookingTypes)
local OrderServiceModule = require(script.Parent.OrderService)
local CookingStations = require(script.Parent.CookingStations)

type PortionStage = CookingTypes.PortionStage

local LOG = "[CookingService]"

local NEXT_STEP_TEXT: { [string]: string } = {
	NeedBox = "Ambil FoodBox",
	NeedChicken = "Ambil ayam",
	NeedSmash = "Geprek ayamnya",
	NeedSambal = "Pilih sambal",
}

local TERMINAL: { [string]: boolean } = { Served = true, Refused = true, Cancelled = true, Expired = true }

type Session = {
	userId: number,
	orderId: string,
	totalPortions: number,
	stage: PortionStage,
	plated: { string }, -- sambalId per finished portion, in tray order
	boxes: { Model },
	currentBox: Model?,
	currentChicken: Model?,
}

local CookingService = {}

export type Handle = { Destroy: () -> () }

local function getPosition(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Attachment") then
		return instance.WorldPosition
	elseif instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	return nil
end

local function getPivotCFrame(instance: Instance): CFrame?
	if instance:IsA("BasePart") then
		return instance.CFrame
	elseif instance:IsA("Model") then
		return instance:GetPivot()
	end
	return nil
end

-- Props are static decoration: anchor them so they never fall or push the player.
local function freezeProp(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
end

local function tally(sambalIds: { string }): { [string]: number }
	local counts: { [string]: number } = {}
	for _, id in sambalIds do
		counts[id] = (counts[id] or 0) + 1
	end
	return counts
end

local function sameTally(a: { [string]: number }, b: { [string]: number }): boolean
	for key, count in a do
		if b[key] ~= count then
			return false
		end
	end
	for key, count in b do
		if a[key] ~= count then
			return false
		end
	end
	return true
end

function CookingService.Start(
	orderService: OrderServiceModule.OrderService,
	orderConfig: OrderTypes.OrderConfig,
	cfg: CookingTypes.CookingConfig
): Handle
	local destroyed = false
	local stations: CookingStations.Stations? = nil
	local connections: { RBXScriptConnection } = {}
	local sessions: { [number]: Session } = {} -- userId -> session
	local sessionByOrder: { [string]: number } = {} -- orderId -> userId
	local lastStepAt: { [number]: number } = {}

	-- Hint (server-built BillboardGui on TrayPlacement; no client script needed) -------------------
	local hintLabel: TextLabel? = nil
	local hintGui: BillboardGui? = nil
	local hintToken = 0
	local progressText = ""

	local function setLabel(text: string)
		local label, gui = hintLabel, hintGui
		if label == nil or gui == nil then
			return
		end
		label.Text = text
		gui.Enabled = text ~= ""
	end

	local function showProgress(session: Session?)
		if session == nil then
			progressText = ""
		else
			local plated = #session.plated
			if plated >= session.totalPortions then
				progressText = `Porsi {plated}/{session.totalPortions} — sajikan di Tray`
			else
				progressText = `Porsi {plated + 1}/{session.totalPortions} — {NEXT_STEP_TEXT[session.stage]}`
			end
		end
		hintToken += 1
		setLabel(progressText)
	end

	local function flashHint(text: string)
		hintToken += 1
		local token = hintToken
		setLabel(text)
		task.delay(cfg.HintSeconds, function()
			if not destroyed and hintToken == token then
				setLabel(progressText)
			end
		end)
	end

	local function createHintGui(tray: BasePart)
		if not cfg.ShowHint then
			return
		end
		local gui = Instance.new("BillboardGui")
		gui.Name = "CookingHintGui"
		gui.Size = UDim2.fromOffset(280, 56)
		gui.StudsOffset = Vector3.new(0, 3, 0)
		gui.AlwaysOnTop = true
		gui.Enabled = false
		gui.Adornee = tray
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(30, 24, 20)
		label.BackgroundTransparency = 0.25
		label.TextColor3 = Color3.fromRGB(245, 240, 225)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 18
		label.TextWrapped = true
		label.Text = ""
		label.Parent = gui
		gui.Parent = tray
		hintGui, hintLabel = gui, label
	end

	-- Session helpers ------------------------------------------------------------------------------
	local function destroyProps(session: Session)
		for _, box in session.boxes do
			box:Destroy()
		end
		table.clear(session.boxes)
		if session.currentChicken then
			session.currentChicken:Destroy()
		end
		session.currentBox = nil
		session.currentChicken = nil
	end

	local function endSession(session: Session, cleanupDelay: number)
		if sessions[session.userId] == session then
			sessions[session.userId] = nil
		end
		if sessionByOrder[session.orderId] == session.userId then
			sessionByOrder[session.orderId] = nil
		end
		if next(sessions) == nil then
			showProgress(nil)
		end
		if cleanupDelay > 0 then
			task.delay(cleanupDelay, function()
				destroyProps(session)
			end)
		else
			destroyProps(session)
		end
	end

	-- Failed tray: clear props and restart from step 1; the order itself is untouched.
	local function restartSession(session: Session)
		destroyProps(session)
		table.clear(session.plated)
		session.stage = "NeedBox"
		showProgress(session)
	end

	local function slotCFrame(tray: BasePart, index: number): CFrame
		return tray.CFrame * CFrame.new(cfg.TrayPlacementOffset + cfg.TrayPortionSpacing * index)
	end

	-- Validation shared by every prompt ------------------------------------------------------------
	local function validatePlayer(player: Player, prompt: ProximityPrompt): boolean
		local now = os.clock()
		local last = lastStepAt[player.UserId]
		if last ~= nil and now - last < cfg.StepCooldownSeconds then
			return false
		end
		lastStepAt[player.UserId] = now

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
			return false
		end
		local promptParent = prompt.Parent
		local promptPosition = if promptParent then getPosition(promptParent) else nil
		if promptPosition == nil then
			return false
		end
		return (root.Position - promptPosition).Magnitude <= prompt.MaxActivationDistance + cfg.DistanceSlack
	end

	local function bindSession(player: Player): Session?
		for _, summary in orderService:GetActiveSummaries() do
			if summary.status == "Accepted" and sessionByOrder[summary.orderId] == nil then
				local ok, code = orderService:Transition(summary.orderId, "Cooking", "CookingStarted")
				if not ok then
					flashHint("Pesanan tidak bisa dimasak (" .. code .. ")")
					return nil
				end
				local session: Session = {
					userId = player.UserId,
					orderId = summary.orderId,
					totalPortions = summary.totalQuantity,
					stage = "NeedBox",
					plated = {},
					boxes = {},
					currentBox = nil,
					currentChicken = nil,
				}
				sessions[player.UserId] = session
				sessionByOrder[summary.orderId] = player.UserId
				return session
			end
		end
		flashHint("Terima pesanan dulu di layar")
		return nil
	end

	-- A session is only usable while its order is still being cooked.
	local function activeSession(player: Player): Session?
		local session = sessions[player.UserId]
		if session == nil then
			return nil
		end
		if orderService:GetStatus(session.orderId) ~= "Cooking" then
			endSession(session, 0)
			return nil
		end
		return session
	end

	-- Step handlers (each runs synchronously => no double-processing of one trigger) ---------------
	local function wrongStep(session: Session)
		if #session.plated >= session.totalPortions then
			flashHint("Nampan sudah lengkap — sajikan di Tray")
		else
			flashHint("Langkah berikutnya: " .. NEXT_STEP_TEXT[session.stage])
		end
	end

	local function onFoodBox(player: Player, s: CookingStations.Stations)
		local session = activeSession(player) or bindSession(player)
		if session == nil then
			return
		end
		if session.stage ~= "NeedBox" or #session.plated >= session.totalPortions then
			return wrongStep(session)
		end
		local box = s.foodBoxTemplate:Clone()
		box.Name = "FoodBoxClone"
		freezeProp(box)
		box:PivotTo(slotCFrame(s.trayPlacement, #session.plated))
		box.Parent = workspace
		table.insert(session.boxes, box)
		session.currentBox = box
		session.stage = "NeedChicken"
		showProgress(session)
	end

	local function onChicken(player: Player, s: CookingStations.Stations)
		local session = activeSession(player)
		if session == nil then
			flashHint("Mulai dengan mengambil FoodBox")
			return
		end
		if session.stage ~= "NeedChicken" then
			return wrongStep(session)
		end
		local chicken = s.chickenTemplate:Clone()
		chicken.Name = "ChickenClone"
		freezeProp(chicken)
		local anchorCFrame = getPivotCFrame(s.geprekAnchor)
		if anchorCFrame then
			chicken:PivotTo(CFrame.new(anchorCFrame.Position + cfg.GeprekChickenOffset))
		end
		chicken.Parent = if s.geprekAnchor:IsA("Model") then s.geprekAnchor else workspace
		session.currentChicken = chicken
		session.stage = "NeedSmash"
		showProgress(session)
	end

	local function onGeprek(player: Player, _s: CookingStations.Stations)
		local session = activeSession(player)
		if session == nil then
			flashHint("Mulai dengan mengambil FoodBox")
			return
		end
		local chicken = session.currentChicken
		if session.stage ~= "NeedSmash" or chicken == nil then
			return wrongStep(session)
		end
		if cfg.SmashScale ~= 1 then
			pcall(function()
				chicken:ScaleTo(cfg.SmashScale)
			end)
		end
		chicken:SetAttribute("Smashed", true)
		session.stage = "NeedSambal"
		showProgress(session)
	end

	local function onSambal(player: Player, s: CookingStations.Stations, sambalId: string)
		local session = activeSession(player)
		if session == nil then
			flashHint("Mulai dengan mengambil FoodBox")
			return
		end
		local chicken, box = session.currentChicken, session.currentBox
		if session.stage ~= "NeedSambal" or chicken == nil or box == nil then
			return wrongStep(session)
		end
		-- Pack: chicken goes into the box that already sits on TrayPlacement.
		chicken:SetAttribute("SambalId", sambalId)
		chicken:PivotTo(slotCFrame(s.trayPlacement, #session.plated) * CFrame.new(cfg.ChickenOnBoxOffset))
		chicken.Parent = box
		table.insert(session.plated, sambalId)
		session.currentChicken = nil
		session.currentBox = nil
		session.stage = "NeedBox"
		showProgress(session)
	end

	local function onTray(player: Player, _s: CookingStations.Stations)
		local session = activeSession(player)
		if session == nil then
			flashHint("Belum ada pesanan yang dimasak")
			return
		end
		if #session.plated < session.totalPortions then
			flashHint(`Pesanan belum lengkap ({#session.plated}/{session.totalPortions})`)
			return
		end

		-- Expected sambal comes from the server order, never from the player.
		local summary = orderService:GetSummary(session.orderId)
		if summary == nil then
			endSession(session, 0)
			return
		end
		local expected: { [string]: number } = {}
		for _, line in summary.lines do
			expected[line.sambalId] = (expected[line.sambalId] or 0) + line.quantity
		end
		if not sameTally(expected, tally(session.plated)) then
			restartSession(session)
			flashHint("Pesanan salah! Ulangi dari awal")
			return
		end

		local readyOk, readyCode = orderService:Transition(session.orderId, "Ready", "CookingDone")
		if not readyOk then
			-- OrderExpired: OrderChanged already ended the session. Anything else: keep session, tell player.
			flashHint(if readyCode == "OrderExpired" then "Waktu habis!" else "Gagal menyajikan (" .. readyCode .. ")")
			return
		end
		local servedOk, servedCode = orderService:Transition(session.orderId, "Served", "TrayServe")
		if not servedOk then
			flashHint(if servedCode == "OrderExpired" then "Waktu habis!" else "Gagal menyajikan (" .. servedCode .. ")")
			return
		end
		-- OrderChanged(Served) ends the session and schedules prop cleanup.
		flashHint("Pesanan disajikan!")
	end

	-- Wiring (runs once the map objects exist) ------------------------------------------------------
	local function connectPrompt(prompt: ProximityPrompt, handler: (Player) -> ())
		table.insert(
			connections,
			prompt.Triggered:Connect(function(player: Player)
				if destroyed or not validatePlayer(player, prompt) then
					return
				end
				handler(player)
			end)
		)
	end

	local function wire(s: CookingStations.Stations)
		stations = s
		createHintGui(s.trayPlacement)
		connectPrompt(s.foodBoxPrompt, function(player)
			onFoodBox(player, s)
		end)
		connectPrompt(s.chickenPrompt, function(player)
			onChicken(player, s)
		end)
		connectPrompt(s.geprekPrompt, function(player)
			onGeprek(player, s)
		end)
		for sambalId, prompt in s.sambalPrompts do
			connectPrompt(prompt, function(player)
				onSambal(player, s, sambalId)
			end)
		end
		connectPrompt(s.trayPrompt, function(player)
			onTray(player, s)
		end)
		print(LOG, "stations siap")
	end

	table.insert(
		connections,
		orderService.OrderChanged:Connect(function(orderId: string, _from: string, toStatus: string)
			if not TERMINAL[toStatus] then
				return
			end
			local userId = sessionByOrder[orderId]
			local session = if userId then sessions[userId] else nil
			if session == nil then
				return
			end
			endSession(session, if toStatus == "Served" then cfg.ServeCleanupDelaySeconds else 0)
			if toStatus == "Expired" then
				flashHint("Waktu habis!")
			elseif toStatus == "Cancelled" then
				flashHint("Pesanan dibatalkan")
			end
		end)
	)

	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			lastStepAt[player.UserId] = nil
			local session = sessions[player.UserId]
			if session then
				endSession(session, 0)
			end
		end)
	)

	-- Bounded wait for the map (never blocks OrderSystem.Start).
	task.spawn(function()
		local deadline = os.clock() + cfg.ResolveTimeoutSeconds
		local missing: { string } = {}
		while not destroyed do
			local resolved, missingNow = CookingStations.Resolve(cfg, orderConfig)
			if resolved then
				wire(resolved)
				return
			end
			missing = missingNow
			if os.clock() >= deadline then
				break
			end
			task.wait(0.5)
		end
		if not destroyed then
			warn(LOG, "CookingService TIDAK aktif. Objek belum ditemukan: " .. table.concat(missing, "; "))
		end
	end)

	return {
		Destroy = function()
			destroyed = true
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			for _, session in sessions do
				destroyProps(session)
			end
			table.clear(sessions)
			table.clear(sessionByOrder)
			table.clear(lastStepAt)
			if hintGui then
				hintGui:Destroy()
			end
			stations = nil
		end,
	}
end

return CookingService
