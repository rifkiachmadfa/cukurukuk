--!strict
--[[
	OrderActionHandler — validates player intents (Accept / Refuse / Serve) before touching order state (Phase 3.2 + 3.5).

	The client only supplies an action name and an orderId. Everything else (status, price, customer,
	category, reward) is read from server state. Rewards/reputation are NOT applied here: Economy and
	Reputation services (Phase 5) will react to OrderService.OrderChanged (Served / Refused).

	Validation order: action -> orderId format -> cooldown -> game-state gate -> order exists ->
	status matches action -> character alive -> interaction point -> distance -> transition.

	Result codes: Ok, InvalidAction, InvalidOrderId, Cooldown, NotAllowed, NotFound, WrongStatus,
	NoCharacter, NoInteractionPoint, TooFar, or a code from OrderService.Transition.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OrderTypes = require(ReplicatedStorage.Shared.Types.OrderTypes)
local OrderServiceModule = require(script.Parent.OrderService)

type OrderAction = OrderTypes.OrderAction
type OrderStatus = OrderTypes.OrderStatus
type ActionResult = OrderTypes.ActionResult

local ACTION_TARGET: { [string]: OrderStatus } = {
	Accept = "Accepted",
	Refuse = "Refused",
	Serve = "Served",
}

local ACTION_REQUIRED_STATUS: { [string]: OrderStatus } = {
	Accept = "Presented",
	Refuse = "Presented",
	Serve = "Ready",
}

local OrderActionHandler = {}
OrderActionHandler.__index = OrderActionHandler

export type InteractionPointProvider = (orderId: string, action: OrderAction) -> Vector3?
-- Future hook for DayCycle/Session: return (false, code) when actions are not allowed (e.g. Closing phase).
export type ActionGate = (player: Player, action: OrderAction) -> (boolean, string?)

export type OrderActionHandler = typeof(setmetatable({} :: {
	_orderService: OrderServiceModule.OrderService,
	_config: OrderTypes.OrderConfig,
	_getPoint: InteractionPointProvider?,
	_gate: ActionGate?,
	_lastActionAt: { [number]: number },
	_removingConnection: RBXScriptConnection,
}, OrderActionHandler))

local function fail(code: string): ActionResult
	return { ok = false, code = code }
end

function OrderActionHandler.new(orderService: OrderServiceModule.OrderService, config: OrderTypes.OrderConfig): OrderActionHandler
	local lastActionAt: { [number]: number } = {}
	local removingConnection = Players.PlayerRemoving:Connect(function(player)
		lastActionAt[player.UserId] = nil
	end)
	return setmetatable({
		_orderService = orderService,
		_config = config,
		_getPoint = nil,
		_gate = nil,
		_lastActionAt = lastActionAt,
		_removingConnection = removingConnection,
	}, OrderActionHandler)
end

function OrderActionHandler.SetInteractionPointProvider(self: OrderActionHandler, provider: InteractionPointProvider?)
	self._getPoint = provider
end

function OrderActionHandler.SetActionGate(self: OrderActionHandler, gate: ActionGate?)
	self._gate = gate
end

-- `action` and `orderId` come from the client and are untrusted (typed `any`).
function OrderActionHandler.Handle(self: OrderActionHandler, player: Player, action: any, orderId: any): ActionResult
	local cfg = self._config

	if type(action) ~= "string" or ACTION_TARGET[action] == nil then
		return fail("InvalidAction")
	end
	if type(orderId) ~= "string" or #orderId == 0 or #orderId > cfg.MaxIdLength or string.find(orderId, "^[%w_%-]+$") == nil then
		return fail("InvalidOrderId")
	end

	local now = os.clock()
	local last = self._lastActionAt[player.UserId]
	if last ~= nil and now - last < cfg.ActionCooldownSeconds then
		return fail("Cooldown")
	end
	self._lastActionAt[player.UserId] = now

	local gate = self._gate
	if gate then
		local allowed, code = gate(player, action :: OrderAction)
		if not allowed then
			return fail(code or "NotAllowed")
		end
	end

	local summary = self._orderService:GetSummary(orderId)
	if summary == nil then
		return fail("NotFound")
	end
	if summary.status ~= ACTION_REQUIRED_STATUS[action] then
		return fail("WrongStatus")
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return fail("NoCharacter")
	end

	local getPoint = self._getPoint
	local point = if getPoint then getPoint(orderId, action :: OrderAction) else nil
	if point == nil then
		return fail("NoInteractionPoint")
	end
	if (root.Position - point).Magnitude > cfg.MaxInteractDistance then
		return fail("TooFar")
	end

	local ok, code = self._orderService:Transition(orderId, ACTION_TARGET[action], "Player" .. action)
	return { ok = ok, code = code }
end

function OrderActionHandler.Destroy(self: OrderActionHandler)
	self._removingConnection:Disconnect()
	table.clear(self._lastActionAt)
end

return OrderActionHandler
