--!strict
--[[
	OrderSystem — composition root for the OrderSystem (Phase 3).
	Wires OrderService + validation + remotes + world screen + timeouts. Start() once per server.

	Later integration points (not built yet, do NOT fake them here):
		CustomerService   -> handle.OrderService:CreateOrder({ customerId = ..., customerCategory = ... })
		                     handle.Timeouts.OnCustomerLeft(customerId)
		DayCycleService   -> handle.Timeouts.OnShopClosing("ShopClosed"); handle.ActionHandler:SetActionGate(...)
		CookingService    -> started below (Phase 4): drives Accepted -> Cooking -> Ready -> Served from the world stations
		Economy/Reputation-> handle.OrderService.OrderChanged (toStatus == "Served" | "Refused")
]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OrderConfig = require(ReplicatedStorage.Shared.Config.OrderConfig)
local OrderService = require(script.Parent.OrderService)
local OrderActionHandler = require(script.Parent.OrderActionHandler)
local OrderRemotes = require(script.Parent.OrderRemotes)
local OrderScreenService = require(script.Parent.OrderScreenService)
local OrderTimeoutService = require(script.Parent.OrderTimeoutService)
local CookingConfig = require(ReplicatedStorage.Shared.Config.CookingConfig)
local CookingService = require(script.Parent.CookingService)
local OrderDevHarness = require(script.Parent.Dev.OrderDevHarness)
local OrderSelfTest = require(script.Parent.Dev.OrderSelfTest)

local OrderSystem = {}

export type Handle = {
	OrderService: OrderService.OrderService,
	ActionHandler: OrderActionHandler.OrderActionHandler,
	Timeouts: OrderTimeoutService.Handle,
	Cooking: CookingService.Handle,
	Destroy: () -> (),
}

local started = false

function OrderSystem.Start(): Handle
	assert(not started, "[OrderSystem] Start() sudah dipanggil.")
	started = true
	local config = OrderConfig
	local inStudio = RunService:IsStudio()

	if inStudio and config.Debug.RunSelfTest then
		OrderSelfTest.Run(config)
	end

	local orderService = OrderService.new(config, { runId = "run_" .. string.sub(HttpService:GenerateGUID(false), 1, 8) })
	local actionHandler = OrderActionHandler.new(orderService, config)
	local remotes = OrderRemotes.Start(orderService, actionHandler, config)
	local screen = OrderScreenService.Start(orderService, actionHandler, config)
	actionHandler:SetInteractionPointProvider(function()
		return screen.GetPosition()
	end)
	local timeouts = OrderTimeoutService.Start(orderService, config)
	local cooking = CookingService.Start(orderService, config, CookingConfig)

	local harness: OrderDevHarness.Handle? = nil
	if inStudio and config.Debug.EnableDevHarness then
		harness = OrderDevHarness.Start(orderService, config)
	end

	return {
		OrderService = orderService,
		ActionHandler = actionHandler,
		Timeouts = timeouts,
		Cooking = cooking,
		Destroy = function()
			started = false
			if harness then
				harness.Destroy()
			end
			cooking.Destroy()
			timeouts.Destroy()
			screen.Destroy()
			remotes.Destroy()
			actionHandler:Destroy()
			orderService:Destroy()
		end,
	}
end

return OrderSystem
