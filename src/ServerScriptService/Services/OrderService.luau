--!strict
--[[
	OrderService — authoritative order state + lifecycle (Phase 3.1).

	One instance per run (OrderService.new). The server is the only writer of order state.
	Clients never send price/quantity/status; they only send intents (see OrderActionHandler).

	Lifecycle (legal transitions):
		Created   -> Presented | Cancelled | Expired
		Presented -> Accepted | Refused | Cancelled | Expired
		Accepted  -> Cooking | Cancelled | Expired
		Cooking   -> Ready | Cancelled | Expired
		Ready     -> Served | Cancelled | Expired
		Served / Refused / Cancelled / Expired are terminal.

	Who triggers what (server-side callers only):
		Presented            OrderService.CreateOrder (default)
		Accepted / Refused   OrderActionHandler (player intent, validated)
		Cooking / Ready      CookingService (Phase 4)  <- not built yet; dev harness simulates it
		Served               OrderActionHandler (player intent, validated)
		Cancelled            OrderService.CancelOrder / CancelAll* (customer leaves, shop closes)
		Expired              OrderTimeoutService (deadline exceeded)

	Public API (all return plain values, never throw on bad input):
		new(config, options?)
		CreateOrder(params) -> (ok, orderIdOrCode)
		GenerateLines(rng?) -> { OrderLine }
		ValidateLines(lines) -> (ok, code)
		Transition(orderId, toStatus, reason?) -> (ok, code)
		CancelOrder(orderId, reason?) / ExpireOrder(orderId, reason?) -> (ok, code)
		CancelAllForCustomer(customerId, reason?) -> number
		CancelAll(reason?) -> number
		GetSummary(orderId) -> OrderSummary?
		GetStatus(orderId) -> OrderStatus?
		GetCustomerCategory(orderId) -> CustomerType?   (server only; never replicate)
		GetActiveOrderIdForCustomer(customerId) -> string?
		GetActiveSummaries() -> { OrderSummary }  (oldest first)
		GetNewestActiveSummary() -> OrderSummary?
		GetNow() -> number
		Destroy()
	Signals:
		OrderCreated(summary)
		OrderChanged(orderId, fromStatus, toStatus, summary)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OrderTypes = require(ReplicatedStorage.Shared.Types.OrderTypes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

type Order = OrderTypes.Order
type OrderStatus = OrderTypes.OrderStatus
type OrderConfig = OrderTypes.OrderConfig
type OrderLine = OrderTypes.OrderLine
type OrderSummary = OrderTypes.OrderSummary

local LEGAL_TRANSITIONS: { [OrderStatus]: { [OrderStatus]: boolean } } = {
	Created = { Presented = true, Cancelled = true, Expired = true },
	Presented = { Accepted = true, Refused = true, Cancelled = true, Expired = true },
	Accepted = { Cooking = true, Cancelled = true, Expired = true },
	Cooking = { Ready = true, Cancelled = true, Expired = true },
	Ready = { Served = true, Cancelled = true, Expired = true },
	Served = {},
	Refused = {},
	Cancelled = {},
	Expired = {},
}

local TERMINAL: { [OrderStatus]: boolean } = {
	Served = true,
	Refused = true,
	Cancelled = true,
	Expired = true,
}

local OrderService = {}
OrderService.__index = OrderService

export type Options = {
	runId: string?,
	now: (() -> number)?, -- injectable clock (tests)
}

export type OrderService = typeof(setmetatable({} :: {
	_config: OrderConfig,
	_runId: string,
	_now: () -> number,
	_orders: { [string]: Order },
	_activeByCustomer: { [string]: string },
	_finishedIds: { string },
	_counter: number,
	_destroyed: boolean,
	OrderCreated: Signal.Signal,
	OrderChanged: Signal.Signal,
}, OrderService))

local function weightedPick(keys: { any }, weights: { [any]: number }, rng: Random): any
	local total = 0
	for _, key in keys do
		total += math.max(0, weights[key] or 0)
	end
	if total <= 0 then
		return keys[1]
	end
	local roll = rng:NextNumber() * total
	local acc = 0
	for _, key in keys do
		acc += math.max(0, weights[key] or 0)
		if roll < acc then
			return key
		end
	end
	return keys[#keys]
end

function OrderService.new(config: OrderConfig, options: Options?): OrderService
	local opts: Options = options or {}
	local self = setmetatable({
		_config = config,
		_runId = opts.runId or "run",
		_now = opts.now or function()
			return workspace:GetServerTimeNow()
		end,
		_orders = {},
		_activeByCustomer = {},
		_finishedIds = {},
		_counter = 0,
		_destroyed = false,
		OrderCreated = Signal.new(),
		OrderChanged = Signal.new(),
	}, OrderService)
	return self
end

function OrderService.GetNow(self: OrderService): number
	return self._now()
end

-- Returns (ok, code). Codes: InvalidLines, InvalidLineCount, InvalidLine, UnknownRecipe,
-- UnknownSambal, InvalidQuantity, TooManyGeprek
function OrderService.ValidateLines(self: OrderService, lines: any): (boolean, string)
	local cfg = self._config
	if type(lines) ~= "table" then
		return false, "InvalidLines"
	end
	local count = #lines
	if count < 1 or count > cfg.MaxLinesPerOrder then
		return false, "InvalidLineCount"
	end
	local geprekTotal = 0
	for index = 1, count do
		local line = lines[index]
		if type(line) ~= "table" then
			return false, "InvalidLine"
		end
		local recipeId, sambalId, quantity = line.recipeId, line.sambalId, line.quantity
		if type(recipeId) ~= "string" or cfg.Recipes[recipeId] == nil then
			return false, "UnknownRecipe"
		end
		if type(sambalId) ~= "string" or cfg.Sambal[sambalId] == nil then
			return false, "UnknownSambal"
		end
		if type(quantity) ~= "number" or quantity % 1 ~= 0 or quantity < 1 or quantity > cfg.MaxGeprekPerOrder then
			return false, "InvalidQuantity"
		end
		if cfg.Recipes[recipeId].isGeprek then
			geprekTotal += quantity
		end
	end
	if geprekTotal > cfg.MaxGeprekPerOrder then
		return false, "TooManyGeprek"
	end
	return true, "Ok"
end

-- Server-side random order content, driven entirely by config weights.
function OrderService.GenerateLines(self: OrderService, rng: Random?): { OrderLine }
	local cfg = self._config
	local random = rng or Random.new()

	local portionKeys: { any } = {}
	for portions in cfg.PortionWeights do
		table.insert(portionKeys, portions)
	end
	table.sort(portionKeys, function(a, b)
		return (a :: number) < (b :: number)
	end)
	local portionCount = math.clamp(weightedPick(portionKeys, cfg.PortionWeights :: any, random) :: number, 1, cfg.MaxGeprekPerOrder)

	local sambalKeys: { any } = table.clone(cfg.SambalOrder :: any)
	local sambalWeights: { [any]: number } = {}
	for id, def in cfg.Sambal do
		sambalWeights[id] = def.weight
	end

	local tally: { [string]: number } = {}
	for _ = 1, portionCount do
		local sambalId = weightedPick(sambalKeys, sambalWeights, random) :: string
		tally[sambalId] = (tally[sambalId] or 0) + 1
	end

	local lines: { OrderLine } = {}
	for _, sambalId in cfg.SambalOrder do
		local quantity = tally[sambalId]
		if quantity then
			table.insert(lines, { recipeId = cfg.DefaultRecipeId, sambalId = sambalId, quantity = quantity })
		end
	end
	return lines
end

-- Builds frozen normalized lines + pricing from already-validated lines.
function OrderService._price(self: OrderService, lines: { OrderLine }): ({ OrderLine }, number, number)
	local cfg = self._config
	local normalized: { OrderLine } = {}
	local totalQuantity, totalPrice = 0, 0
	for _, line in lines do
		local recipe = cfg.Recipes[line.recipeId]
		local sambal = cfg.Sambal[line.sambalId]
		local unitPrice = recipe.basePrice + sambal.extraPrice
		totalQuantity += line.quantity
		totalPrice += unitPrice * line.quantity
		table.insert(
			normalized,
			table.freeze({ recipeId = line.recipeId, sambalId = line.sambalId, quantity = line.quantity })
		)
	end
	return table.freeze(normalized), totalQuantity, totalPrice
end

function OrderService._summarize(self: OrderService, order: Order): OrderSummary
	local cfg = self._config
	local lines = {}
	for _, line in order.lines do
		local recipe = cfg.Recipes[line.recipeId]
		local sambal = cfg.Sambal[line.sambalId]
		local unitPrice = recipe.basePrice + sambal.extraPrice
		table.insert(lines, {
			recipeId = line.recipeId,
			displayName = recipe.displayName,
			sambalId = line.sambalId,
			sambalName = sambal.displayName,
			quantity = line.quantity,
			unitPrice = unitPrice,
			lineTotal = unitPrice * line.quantity,
		})
	end
	return {
		orderId = order.orderId,
		customerId = order.customerId,
		status = order.status,
		lines = lines,
		totalQuantity = order.totalQuantity,
		totalPrice = order.totalPrice,
		deadlineAt = order.deadlineAt,
		deadlineKind = order.deadlineKind,
		endReason = order.endReason,
	}
end

-- Returns (ok, orderId) or (false, errorCode).
-- Codes: ServiceDestroyed, InvalidCustomer, CustomerHasActiveOrder, + ValidateLines codes.
function OrderService.CreateOrder(self: OrderService, params: OrderTypes.CreateOrderParams): (boolean, string)
	if self._destroyed then
		return false, "ServiceDestroyed"
	end
	local cfg = self._config
	local customerId = params.customerId
	if type(customerId) ~= "string" or #customerId == 0 or #customerId > cfg.MaxIdLength then
		return false, "InvalidCustomer"
	end
	if self._activeByCustomer[customerId] ~= nil then
		return false, "CustomerHasActiveOrder"
	end

	local rawLines: { OrderLine } = params.lines or self:GenerateLines(params.rng)
	local valid, code = self:ValidateLines(rawLines)
	if not valid then
		return false, code
	end
	local lines, totalQuantity, totalPrice = self:_price(rawLines)

	self._counter += 1
	local orderId = string.format("%s-%04d", self._runId, self._counter)
	local metadata: { [string]: any } = if params.metadata then table.clone(params.metadata) else {}

	local order: Order = {
		orderId = orderId,
		seq = self._counter,
		customerId = customerId,
		customerCategory = params.customerCategory or "Normal",
		lines = lines,
		totalQuantity = totalQuantity,
		totalPrice = totalPrice,
		status = "Created",
		createdAt = self._now(),
		ownerUserId = params.ownerUserId,
		metadata = metadata,
	}
	self._orders[orderId] = order
	self._activeByCustomer[customerId] = orderId
	self.OrderCreated:Fire(self:_summarize(order))

	if params.present ~= false then
		self:Transition(orderId, "Presented")
	end
	return true, orderId
end

function OrderService._applyTransition(self: OrderService, order: Order, toStatus: OrderStatus, reason: string?)
	local cfg = self._config
	local fromStatus = order.status
	local now = self._now()
	order.status = toStatus

	if toStatus == "Presented" then
		order.presentedAt = now
		order.deadlineAt = now + cfg.PresentedTimeoutSeconds
		order.deadlineKind = "Presented"
	elseif toStatus == "Accepted" then
		order.acceptedAt = now
		order.deadlineAt = now + cfg.WorkTimeLimitSeconds
		order.deadlineKind = "Work"
	end

	if TERMINAL[toStatus] then
		order.finishedAt = now
		order.deadlineAt = nil
		order.deadlineKind = nil
		order.endReason = reason
		if self._activeByCustomer[order.customerId] == order.orderId then
			self._activeByCustomer[order.customerId] = nil
		end
		table.insert(self._finishedIds, order.orderId)
		while #self._finishedIds > cfg.MaxFinishedHistory do
			local oldest = table.remove(self._finishedIds, 1)
			if oldest then
				self._orders[oldest] = nil
			end
		end
	end

	self.OrderChanged:Fire(order.orderId, fromStatus, toStatus, self:_summarize(order))
end

-- Returns (ok, code). Codes: ServiceDestroyed, InvalidOrderId, NotFound, IllegalTransition, OrderExpired, Ok
function OrderService.Transition(self: OrderService, orderId: string, toStatus: OrderStatus, reason: string?): (boolean, string)
	if self._destroyed then
		return false, "ServiceDestroyed"
	end
	if type(orderId) ~= "string" then
		return false, "InvalidOrderId"
	end
	local order = self._orders[orderId]
	if order == nil then
		return false, "NotFound"
	end
	local allowed = LEGAL_TRANSITIONS[order.status]
	if allowed[toStatus] ~= true then
		return false, "IllegalTransition"
	end

	-- Late guard: a deadline that already passed must not be beaten by a transition
	-- that arrives before the timeout timer fires (no reward after expiry).
	local deadlineAt = order.deadlineAt
	if deadlineAt ~= nil and self._now() > deadlineAt and toStatus ~= "Expired" and toStatus ~= "Cancelled" then
		self:_applyTransition(order, "Expired", "DeadlineExceeded")
		return false, "OrderExpired"
	end

	self:_applyTransition(order, toStatus, reason)
	return true, "Ok"
end

function OrderService.CancelOrder(self: OrderService, orderId: string, reason: string?): (boolean, string)
	return self:Transition(orderId, "Cancelled", reason or "Cancelled")
end

function OrderService.ExpireOrder(self: OrderService, orderId: string, reason: string?): (boolean, string)
	return self:Transition(orderId, "Expired", reason or "Expired")
end

function OrderService.CancelAllForCustomer(self: OrderService, customerId: string, reason: string?): number
	local orderId = self._activeByCustomer[customerId]
	if orderId and self:CancelOrder(orderId, reason or "CustomerLeft") then
		return 1
	end
	return 0
end

-- Closing / day change / cleanup. Returns how many orders were cancelled.
function OrderService.CancelAll(self: OrderService, reason: string?): number
	local ids: { string } = {}
	for orderId in self._activeByCustomer do
		table.insert(ids, self._activeByCustomer[orderId])
	end
	local cancelled = 0
	for _, orderId in ids do
		if self:CancelOrder(orderId, reason or "Cleanup") then
			cancelled += 1
		end
	end
	return cancelled
end

function OrderService.GetSummary(self: OrderService, orderId: string): OrderSummary?
	local order = if type(orderId) == "string" then self._orders[orderId] else nil
	if order == nil then
		return nil
	end
	return self:_summarize(order)
end

function OrderService.GetStatus(self: OrderService, orderId: string): OrderStatus?
	local order = if type(orderId) == "string" then self._orders[orderId] else nil
	return if order then order.status else nil
end

-- Server-only. Never put the result on a remote.
function OrderService.GetCustomerCategory(self: OrderService, orderId: string): OrderTypes.CustomerType?
	local order = if type(orderId) == "string" then self._orders[orderId] else nil
	return if order then order.customerCategory else nil
end

function OrderService.GetActiveOrderIdForCustomer(self: OrderService, customerId: string): string?
	return self._activeByCustomer[customerId]
end

function OrderService.GetActiveSummaries(self: OrderService): { OrderSummary }
	local active: { Order } = {}
	for _, orderId in self._activeByCustomer do
		local order = self._orders[orderId]
		if order then
			table.insert(active, order)
		end
	end
	table.sort(active, function(a, b)
		return a.seq < b.seq
	end)
	local summaries: { OrderSummary } = {}
	for _, order in active do
		table.insert(summaries, self:_summarize(order))
	end
	return summaries
end

function OrderService.GetNewestActiveSummary(self: OrderService): OrderSummary?
	local newest: Order? = nil
	for _, orderId in self._activeByCustomer do
		local order = self._orders[orderId]
		if order and (newest == nil or order.seq > newest.seq) then
			newest = order
		end
	end
	return if newest then self:_summarize(newest) else nil
end

function OrderService.Destroy(self: OrderService)
	if self._destroyed then
		return
	end
	self:CancelAll("ServiceDestroyed")
	self._destroyed = true
	self.OrderCreated:DisconnectAll()
	self.OrderChanged:DisconnectAll()
	table.clear(self._orders)
	table.clear(self._activeByCustomer)
	table.clear(self._finishedIds)
end

return OrderService
