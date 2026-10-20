--!strict
--[[
	OrderTimeoutService — deadline enforcement + closing cleanup (Phase 3.6).

	One task.delay per order that has a deadline (no per-frame loop, no polling).
	Deadlines come from OrderService (server clock):
		Presented -> PresentedTimeoutSeconds  (customer waiting for Accept/Refuse)
		Accepted  -> WorkTimeLimitSeconds     (max 2 minutes until Served)
	When a timer fires the order is Expired with reason "PresentedTimeout" or "WorkTimeExceeded".
	Expired orders cannot be served and never pay out (OrderService blocks the transition).

	Hooks for later systems (call from DayCycleService / CustomerService):
		OnShopClosing(reason?)       cancel every active order (Closing phase, day change)
		OnCustomerLeft(customerId)   cancel that customer's active order
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OrderTypes = require(ReplicatedStorage.Shared.Types.OrderTypes)
local OrderServiceModule = require(script.Parent.OrderService)

local OrderTimeoutService = {}

export type Handle = {
	OnShopClosing: (reason: string?) -> number,
	OnCustomerLeft: (customerId: string) -> number,
	Destroy: () -> (),
}

function OrderTimeoutService.Start(orderService: OrderServiceModule.OrderService, _config: OrderTypes.OrderConfig): Handle
	local timers: { [string]: thread } = {}

	local function clearTimer(orderId: string)
		local timer = timers[orderId]
		if timer then
			timers[orderId] = nil
			task.cancel(timer)
		end
	end

	local connection = orderService.OrderChanged:Connect(function(orderId: string, _from: string, _to: string, summary: OrderTypes.OrderSummary)
		clearTimer(orderId)
		local deadlineAt = summary.deadlineAt
		if deadlineAt == nil then
			return -- terminal status: nothing to schedule
		end
		local reason = if summary.deadlineKind == "Work" then "WorkTimeExceeded" else "PresentedTimeout"
		local delaySeconds = math.max(0, deadlineAt - orderService:GetNow())
		timers[orderId] = task.delay(delaySeconds, function()
			timers[orderId] = nil -- clear first so our own status change does not cancel this running thread
			orderService:ExpireOrder(orderId, reason)
		end)
	end)

	return {
		OnShopClosing = function(reason: string?)
			return orderService:CancelAll(reason or "ShopClosed")
		end,
		OnCustomerLeft = function(customerId: string)
			return orderService:CancelAllForCustomer(customerId, "CustomerLeft")
		end,
		Destroy = function()
			connection:Disconnect()
			for orderId in timers do
				clearTimer(orderId)
			end
		end,
	}
end

return OrderTimeoutService
