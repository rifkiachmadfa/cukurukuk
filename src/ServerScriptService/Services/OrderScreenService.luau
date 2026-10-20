--!strict
--[[
	OrderScreenService — renders the current order on the world part named "screen" (Phase 3.4).

	- Finds Workspace part by OrderConfig.Screen.PartName (case-insensitive). Waits for it if streamed in later.
	- Builds a SurfaceGui (server-created, so every client sees the same server-authoritative text).
	- Shows: portion count, sambal choice, price per line, total, status and a countdown.
	- Adds ProximityPrompts (Terima / Tolak / Antar) that call OrderActionHandler; the server still validates everything.
	- The countdown refreshes once per second only while an order with a deadline is displayed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OrderTypes = require(ReplicatedStorage.Shared.Types.OrderTypes)
local CurrencyFormat = require(ReplicatedStorage.Shared.Util.CurrencyFormat)
local OrderServiceModule = require(script.Parent.OrderService)
local OrderActionHandlerModule = require(script.Parent.OrderActionHandler)

type OrderSummary = OrderTypes.OrderSummary

local LOG = "[OrderScreenService]"
local GUI_NAME = "OrderScreenGui"

local STATUS_TEXT: { [string]: string } = {
	Created = "Pesanan baru",
	Presented = "Menunggu keputusan",
	Accepted = "Diterima — siapkan pesanan",
	Cooking = "Sedang dimasak",
	Ready = "Siap diantar",
	Served = "Selesai — pesanan diantar",
	Refused = "Pesanan ditolak",
	Cancelled = "Pesanan dibatalkan",
	Expired = "Waktu habis",
}

local TERMINAL: { [string]: boolean } = { Served = true, Refused = true, Cancelled = true, Expired = true }

local OrderScreenService = {}

export type Handle = {
	GetPosition: () -> Vector3?,
	Destroy: () -> (),
}

local function findScreenPart(name: string): BasePart?
	local direct = workspace:FindFirstChild(name, true)
	if direct and direct:IsA("BasePart") then
		return direct
	end
	local lowered = string.lower(name)
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("BasePart") and string.lower(instance.Name) == lowered then
			return instance
		end
	end
	return nil
end

local function makeLabel(parent: Instance, name: string, position: UDim2, size: UDim2, textSize: number, bold: boolean): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	label.TextSize = textSize
	label.TextColor3 = Color3.fromRGB(245, 240, 225)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.Text = ""
	label.Parent = parent
	return label
end

local function formatCountdown(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

function OrderScreenService.Start(
	orderService: OrderServiceModule.OrderService,
	handler: OrderActionHandlerModule.OrderActionHandler,
	config: OrderTypes.OrderConfig
): Handle
	local screenCfg = config.Screen

	local screenPart: BasePart? = nil
	local gui: SurfaceGui? = nil
	local statusLabel: TextLabel? = nil
	local linesLabel: TextLabel? = nil
	local totalLabel: TextLabel? = nil
	local timerLabel: TextLabel? = nil
	local prompts: { [string]: ProximityPrompt } = {}
	local promptConnections: { RBXScriptConnection } = {}
	local streamConnection: RBXScriptConnection? = nil

	local displayed: OrderSummary? = nil
	local lastResult: OrderSummary? = nil
	local resultToken = 0
	local tickerRunning = false
	local destroyed = false

	local function updateTimerLabel()
		local label = timerLabel
		local summary = displayed
		if label == nil then
			return
		end
		if summary == nil or summary.deadlineAt == nil then
			label.Text = ""
			return
		end
		local remaining = summary.deadlineAt - orderService:GetNow()
		local caption = if summary.deadlineKind == "Work" then "Batas pengerjaan" else "Pelanggan menunggu"
		label.Text = string.format("%s: %s", caption, formatCountdown(remaining))
	end

	local function render()
		local summary = displayed
		if statusLabel == nil or linesLabel == nil or totalLabel == nil then
			return
		end
		if summary == nil then
			statusLabel.Text = "Belum ada pesanan"
			linesLabel.Text = ""
			totalLabel.Text = ""
			updateTimerLabel()
		else
			statusLabel.Text = STATUS_TEXT[summary.status] or summary.status
			local rows: { string } = {}
			for _, line in summary.lines do
				table.insert(
					rows,
					string.format(
						"%dx %s  •  Sambal %s  •  %s",
						line.quantity,
						line.displayName,
						line.sambalName,
						CurrencyFormat.formatRupiah(line.lineTotal)
					)
				)
			end
			linesLabel.Text = table.concat(rows, "\n")
			totalLabel.Text = string.format(
				"Total (%d porsi): %s",
				summary.totalQuantity,
				CurrencyFormat.formatRupiah(summary.totalPrice)
			)
			updateTimerLabel()
		end

		local status = if summary then summary.status else nil
		local acceptPrompt, refusePrompt, servePrompt = prompts.Accept, prompts.Refuse, prompts.Serve
		if acceptPrompt then
			acceptPrompt.Enabled = status == "Presented"
		end
		if refusePrompt then
			refusePrompt.Enabled = status == "Presented"
		end
		if servePrompt then
			servePrompt.Enabled = status == "Ready"
		end
	end

	local function ensureTicker()
		local summary = displayed
		if tickerRunning or summary == nil or summary.deadlineAt == nil then
			return
		end
		tickerRunning = true
		task.spawn(function()
			while not destroyed and displayed ~= nil and displayed.deadlineAt ~= nil do
				updateTimerLabel()
				task.wait(1)
			end
			tickerRunning = false
		end)
	end

	local function refresh()
		local newest = orderService:GetNewestActiveSummary()
		if newest then
			displayed = newest
			lastResult = nil
		elseif lastResult then
			displayed = lastResult
		else
			displayed = nil
		end
		render()
		ensureTicker()
	end

	local function makePrompt(part: BasePart, key: string, actionText: string, keyCode: Enum.KeyCode, gamepad: Enum.KeyCode, action: OrderTypes.OrderAction)
		local name = "Order" .. key .. "Prompt"
		local old = part:FindFirstChild(name)
		if old then
			old:Destroy()
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = name
		prompt.ActionText = actionText
		prompt.ObjectText = "Pesanan"
		prompt.HoldDuration = 0
		prompt.KeyboardKeyCode = keyCode
		prompt.GamepadKeyCode = gamepad
		prompt.MaxActivationDistance = math.max(4, config.MaxInteractDistance - 2)
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt.Parent = part
		prompts[key] = prompt
		table.insert(
			promptConnections,
			prompt.Triggered:Connect(function(player: Player)
				local summary = displayed
				if summary == nil then
					return
				end
				handler:Handle(player, action, summary.orderId)
			end)
		)
	end

	local function attach(part: BasePart)
		screenPart = part

		local oldGui = part:FindFirstChild(GUI_NAME)
		if oldGui then
			oldGui:Destroy()
		end

		local face = Enum.NormalId.Front
		local okFace, resolved = pcall(function()
			return (Enum.NormalId :: any)[screenCfg.Face]
		end)
		if okFace and resolved then
			face = resolved
		else
			warn(LOG, "Screen.Face tidak valid, memakai Front:", screenCfg.Face)
		end

		local surface = Instance.new("SurfaceGui")
		surface.Name = GUI_NAME
		surface.Face = face
		surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		surface.CanvasSize = Vector2.new(800, 500)
		surface.LightInfluence = 0
		surface.Brightness = 1
		surface.ClipsDescendants = true
		surface.Adornee = part
		surface.Parent = part
		gui = surface

		local background = Instance.new("Frame")
		background.Name = "Background"
		background.BackgroundColor3 = Color3.fromRGB(20, 18, 22)
		background.BorderSizePixel = 0
		background.Size = UDim2.fromScale(1, 1)
		background.Parent = surface

		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 28)
		padding.PaddingRight = UDim.new(0, 28)
		padding.PaddingTop = UDim.new(0, 20)
		padding.PaddingBottom = UDim.new(0, 20)
		padding.Parent = background

		local title = makeLabel(background, "Title", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.14), 44, true)
		title.Text = "PESANAN"
		title.TextColor3 = Color3.fromRGB(255, 170, 60)
		statusLabel = makeLabel(background, "Status", UDim2.fromScale(0, 0.15), UDim2.fromScale(1, 0.1), 32, true)
		linesLabel = makeLabel(background, "Lines", UDim2.fromScale(0, 0.27), UDim2.fromScale(1, 0.38), 30, false)
		totalLabel = makeLabel(background, "Total", UDim2.fromScale(0, 0.68), UDim2.fromScale(1, 0.1), 32, true)
		timerLabel = makeLabel(background, "Timer", UDim2.fromScale(0, 0.82), UDim2.fromScale(1, 0.1), 28, false)

		makePrompt(part, "Accept", "Terima", Enum.KeyCode.E, Enum.KeyCode.ButtonX, "Accept")
		makePrompt(part, "Refuse", "Tolak", Enum.KeyCode.F, Enum.KeyCode.ButtonY, "Refuse")
		makePrompt(part, "Serve", "Antar", Enum.KeyCode.E, Enum.KeyCode.ButtonX, "Serve")

		refresh()
	end

	local initial = findScreenPart(screenCfg.PartName)
	if initial then
		attach(initial)
	else
		warn(
			LOG,
			string.format(
				"Part '%s' belum ditemukan di Workspace. Menunggu (mungkin StreamingEnabled) — pastikan nama part benar.",
				screenCfg.PartName
			)
		)
		local lowered = string.lower(screenCfg.PartName)
		streamConnection = workspace.DescendantAdded:Connect(function(instance)
			if screenPart == nil and instance:IsA("BasePart") and string.lower(instance.Name) == lowered then
				if streamConnection then
					streamConnection:Disconnect()
					streamConnection = nil
				end
				attach(instance)
			end
		end)
	end

	local changedConnection = orderService.OrderChanged:Connect(function(_orderId, _from, toStatus, summary)
		if TERMINAL[toStatus] then
			lastResult = summary
			resultToken += 1
			local token = resultToken
			task.delay(screenCfg.ResultDisplaySeconds, function()
				if not destroyed and token == resultToken and lastResult ~= nil then
					lastResult = nil
					refresh()
				end
			end)
		end
		refresh()
	end)
	local createdConnection = orderService.OrderCreated:Connect(function()
		refresh()
	end)

	return {
		GetPosition = function()
			local part = screenPart
			return if part and part.Parent then part.Position else nil
		end,
		Destroy = function()
			destroyed = true
			changedConnection:Disconnect()
			createdConnection:Disconnect()
			if streamConnection then
				streamConnection:Disconnect()
			end
			for _, connection in promptConnections do
				connection:Disconnect()
			end
			table.clear(promptConnections)
			for _, prompt in prompts do
				prompt:Destroy()
			end
			table.clear(prompts)
			if gui then
				gui:Destroy()
			end
		end,
	}
end

return OrderScreenService
