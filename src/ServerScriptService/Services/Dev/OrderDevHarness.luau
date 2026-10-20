--!strict
--[[
	OrderDevHarness — DEVELOPMENT ONLY (Roblox Studio). Lets you play the order flow before CustomerService
	and CookingService exist.

	- Creates a fake customer order automatically (customerId "dev_customer_N").
	- After you press Terima (Accept) it simulates Phase 4: Cooking, then Ready after DevAutoCookSeconds,
	  so the Antar (Serve) prompt can be tested. Let the clock run out to test the 2-minute expiry.
	- After an order ends, the next one is created after DevNextOrderDelaySeconds.

	Disabled automatically outside Studio, or via OrderConfig.Debug.EnableDevHarness = false.
	Remove this folder from the release build (Phase 16.2).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OrderTypes = require(ReplicatedStorage.Shared.Types.OrderTypes)
local OrderServiceModule = require(script.Parent.Parent.OrderService)

local LOG = "[OrderDevHarness]"

local OrderDevHarness = {}

export type Handle = { Destroy: () -> () }

function OrderDevHarness.Start(orderService: OrderServiceModule.OrderService, config: OrderTypes.OrderConfig): Handle
	local debugCfg = config.Debug
	local destroyed = false
	local counter = 0
	local pending = false

	local function spawnOrder()
		if destroyed or #Players:GetPlayers() == 0 then
			return
		end
		counter += 1
		local ok, result = orderService:CreateOrder({
			customerId = "dev_customer_" .. counter,
			customerCategory = "Normal",
		})
		if ok then
			print(LOG, "created", result)
		else
			warn(LOG, "CreateOrder failed:", result)
		end
	end

	local function scheduleNext()
		if pending or destroyed then
			return
		end
		pending = true
		task.delay(debugCfg.DevNextOrderDelaySeconds, function()
			pending = false
			if orderService:GetNewestActiveSummary() == nil then
				spawnOrder()
			end
		end)
	end

	local connection = orderService.OrderChanged:Connect(function(orderId: string, _from: string, toStatus: string)
		if toStatus == "Accepted" then
			orderService:Transition(orderId, "Cooking")
			task.delay(debugCfg.DevAutoCookSeconds, function()
				if orderService:GetStatus(orderId) == "Cooking" then
					orderService:Transition(orderId, "Ready")
				end
			end)
		elseif toStatus == "Served" or toStatus == "Refused" or toStatus == "Cancelled" or toStatus == "Expired" then
			scheduleNext()
		end
	end)

	local playerConnection = Players.PlayerAdded:Connect(function()
		task.delay(3, function()
			if orderService:GetNewestActiveSummary() == nil then
				spawnOrder()
			end
		end)
	end)
	if #Players:GetPlayers() > 0 then
		task.delay(3, spawnOrder)
	end

	return {
		Destroy = function()
			destroyed = true
			connection:Disconnect()
			playerConnection:Disconnect()
		end,
	}
end

return OrderDevHarness
