--!strict
--[[
	OrderSelfTest — DEVELOPMENT ONLY. Plain-assert tests for OrderService (Phase 3.7).
	Runs in Studio on server start (OrderConfig.Debug.RunSelfTest). Uses a fake clock and its own
	OrderService instance, so it never touches live order state. Prints PASS/FAIL per case.

	Not covered (needs a live Player/Studio session): remote spam, TooFar, prompt UI. See the manual
	checklist in ai/PHASE_3_ORDERSYSTEM.md.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OrderTypes = require(ReplicatedStorage.Shared.Types.OrderTypes)
local OrderServiceModule = require(script.Parent.Parent.OrderService)

local LOG = "[OrderSelfTest]"

local OrderSelfTest = {}

function OrderSelfTest.Run(config: OrderTypes.OrderConfig): (number, number)
	local passed, failed = 0, 0
	local clock = 1000

	local function newService()
		return OrderServiceModule.new(config, {
			runId = "test",
			now = function()
				return clock
			end,
		})
	end

	local function check(name: string, condition: boolean)
		if condition then
			passed += 1
			print(LOG, "PASS", name)
		else
			failed += 1
			warn(LOG, "FAIL", name)
		end
	end

	local function line(sambalId: string, quantity: number): OrderTypes.OrderLine
		return { recipeId = config.DefaultRecipeId, sambalId = sambalId, quantity = quantity }
	end

	-- create + unique ids
	do
		local service = newService()
		local ok1, id1 = service:CreateOrder({ customerId = "c1" })
		local ok2, id2 = service:CreateOrder({ customerId = "c2" })
		check("create returns ok and unique ids", ok1 and ok2 and id1 ~= id2)
		check("new order is Presented with deadline", service:GetStatus(id1) == "Presented")
		local summary = service:GetSummary(id1)
		check(
			"presented deadline uses PresentedTimeoutSeconds",
			summary ~= nil and summary.deadlineAt == clock + config.PresentedTimeoutSeconds
		)
		service:Destroy()
	end

	-- max 3 geprek
	do
		local service = newService()
		check("3 geprek accepted", (service:CreateOrder({ customerId = "a", lines = { line("sedang", 3) } })))
		check("4 geprek rejected", not (service:CreateOrder({ customerId = "b", lines = { line("sedang", 4) } })))
		check(
			"2+2 geprek across lines rejected",
			not (service:CreateOrder({ customerId = "c", lines = { line("sedang", 2), line("pedas", 2) } }))
		)
		check("unknown sambal rejected", not (service:CreateOrder({ customerId = "d", lines = { line("nope", 1) } })))
		check("zero quantity rejected", not (service:CreateOrder({ customerId = "e", lines = { line("sedang", 0) } })))
		check("fractional quantity rejected", not (service:CreateOrder({ customerId = "f", lines = { line("sedang", 1.5) } })))
		check("empty lines rejected", not (service:CreateOrder({ customerId = "g", lines = {} })))
		service:Destroy()
	end

	-- generated orders always respect the cap
	do
		local service = newService()
		local rng = Random.new(1234)
		local allValid = true
		for _ = 1, 300 do
			local lines = service:GenerateLines(rng)
			local valid = service:ValidateLines(lines)
			if not valid then
				allValid = false
			end
		end
		check("300 generated orders are valid (<= max geprek)", allValid)
		service:Destroy()
	end

	-- pricing from config
	do
		local service = newService()
		local _, id = service:CreateOrder({ customerId = "p", lines = { line("sedang", 2), line("extra_pedas", 1) } })
		local summary = service:GetSummary(id)
		local expected = 2 * (config.Recipes[config.DefaultRecipeId].basePrice + config.Sambal.sedang.extraPrice)
			+ (config.Recipes[config.DefaultRecipeId].basePrice + config.Sambal.extra_pedas.extraPrice)
		check("total price computed from config", summary ~= nil and summary.totalPrice == expected)
		service:Destroy()
	end

	-- duplicate order per customer
	do
		local service = newService()
		local _, id = service:CreateOrder({ customerId = "dup" })
		local ok, code = service:CreateOrder({ customerId = "dup" })
		check("second active order for same customer rejected", not ok and code == "CustomerHasActiveOrder")
		service:CancelOrder(id)
		check("customer can order again after cancel", (service:CreateOrder({ customerId = "dup" })))
		service:Destroy()
	end

	-- legal / illegal transitions + finished orders locked
	do
		local service = newService()
		local _, id = service:CreateOrder({ customerId = "t" })
		check("Presented -> Served is illegal", not (service:Transition(id, "Served")))
		check("Presented -> Ready is illegal", not (service:Transition(id, "Ready")))
		check("Presented -> Accepted ok", (service:Transition(id, "Accepted")))
		check("accepted deadline = work limit", (service:GetSummary(id) :: any).deadlineAt == clock + config.WorkTimeLimitSeconds)
		check("Accepted -> Served is illegal", not (service:Transition(id, "Served")))
		check("Accepted -> Cooking ok", (service:Transition(id, "Cooking")))
		check("Cooking -> Ready ok", (service:Transition(id, "Ready")))
		check("Ready -> Served ok", (service:Transition(id, "Served")))
		check("Served cannot be served twice", not (service:Transition(id, "Served")))
		check("Served cannot be cancelled", not (service:Transition(id, "Cancelled")))
		check("Served order has no deadline", (service:GetSummary(id) :: any).deadlineAt == nil)
		check("customer slot freed after Served", service:GetActiveOrderIdForCustomer("t") == nil)
		check("unknown order id rejected", not (service:Transition("missing", "Accepted")))
		service:Destroy()
	end

	-- refuse / cancel / expire blocks serving
	do
		local service = newService()
		local _, refusedId = service:CreateOrder({ customerId = "r" })
		service:Transition(refusedId, "Refused")
		check("refused order cannot be accepted", not (service:Transition(refusedId, "Accepted")))

		local _, cancelledId = service:CreateOrder({ customerId = "x" })
		service:Transition(cancelledId, "Accepted")
		service:Transition(cancelledId, "Cooking")
		service:Transition(cancelledId, "Ready")
		service:CancelOrder(cancelledId, "CustomerLeft")
		check("cancelled order cannot be served", not (service:Transition(cancelledId, "Served")))

		local _, expiredId = service:CreateOrder({ customerId = "y" })
		service:ExpireOrder(expiredId, "PresentedTimeout")
		check("expired order cannot be accepted", not (service:Transition(expiredId, "Accepted")))
		service:Destroy()
	end

	-- late guard: serving after the 2-minute limit expires instead of paying out
	do
		local service = newService()
		local _, id = service:CreateOrder({ customerId = "late" })
		service:Transition(id, "Accepted")
		service:Transition(id, "Cooking")
		service:Transition(id, "Ready")
		clock += config.WorkTimeLimitSeconds + 1
		local ok, code = service:Transition(id, "Served")
		check("serving after work limit is rejected", not ok and code == "OrderExpired")
		check("late order ends Expired", service:GetStatus(id) == "Expired")
		clock = 1000
		service:Destroy()
	end

	-- cleanup helpers
	do
		local service = newService()
		service:CreateOrder({ customerId = "k1" })
		service:CreateOrder({ customerId = "k2" })
		check("CancelAllForCustomer cancels one", service:CancelAllForCustomer("k1", "CustomerLeft") == 1)
		check("CancelAll cancels the rest", service:CancelAll("ShopClosed") == 1)
		check("no active orders remain", #service:GetActiveSummaries() == 0)
		service:Destroy()
	end

	-- summaries never leak server-only fields
	do
		local service = newService()
		local _, id = service:CreateOrder({ customerId = "leak", customerCategory = "Secret", metadata = { isAnomaly = true } })
		local summary = service:GetSummary(id) :: any
		check(
			"summary hides category and metadata",
			summary.customerCategory == nil and summary.metadata == nil and summary.isAnomaly == nil
		)
		service:Destroy()
	end

	print(LOG, string.format("done: %d passed, %d failed", passed, failed))
	return passed, failed
end

return OrderSelfTest
