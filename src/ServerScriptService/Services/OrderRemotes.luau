--!strict
--[[
	OrderRemotes — remote contract for the OrderSystem (Phase 3.2).

	Created under ReplicatedStorage.<Remotes.FolderName> (names in OrderConfig.Remotes):

	RemoteFunction RequestOrderAction (client -> server)
		args:    action: "Accept" | "Refuse" | "Serve", orderId: string
		returns: { ok: boolean, code: string }   -- never contains server data
	RemoteFunction RequestOrderSnapshot (client -> server)
		args:    none
		returns: { OrderSummary }                 -- active orders only, client-safe fields
	RemoteEvent OrderUpdated (server -> client)
		args:    OrderSummary                     -- fired on creation and every status change

	The client may never send price, reward, category, status or any decision result.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OrderTypes = require(ReplicatedStorage.Shared.Types.OrderTypes)
local OrderServiceModule = require(script.Parent.OrderService)
local OrderActionHandlerModule = require(script.Parent.OrderActionHandler)

local LOG = "[OrderRemotes]"
local SNAPSHOT_COOLDOWN_SECONDS = 1

local OrderRemotes = {}

export type Handle = { Destroy: () -> () }

local function getOrCreate(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

function OrderRemotes.Start(
	orderService: OrderServiceModule.OrderService,
	handler: OrderActionHandlerModule.OrderActionHandler,
	config: OrderTypes.OrderConfig
): Handle
	local names = config.Remotes
	local folder = getOrCreate(ReplicatedStorage, "Folder", names.FolderName)
	local actionFunction = getOrCreate(folder, "RemoteFunction", names.ActionFunction) :: RemoteFunction
	local snapshotFunction = getOrCreate(folder, "RemoteFunction", names.SnapshotFunction) :: RemoteFunction
	local updateEvent = getOrCreate(folder, "RemoteEvent", names.UpdateEvent) :: RemoteEvent

	actionFunction.OnServerInvoke = function(player: Player, action: any, orderId: any)
		local ok, result = pcall(handler.Handle, handler, player, action, orderId)
		if not ok then
			warn(LOG, "Handle failed:", result)
			return { ok = false, code = "InternalError" }
		end
		return { ok = result.ok, code = result.code }
	end

	local lastSnapshotAt: { [number]: number } = {}
	snapshotFunction.OnServerInvoke = function(player: Player)
		local now = os.clock()
		local last = lastSnapshotAt[player.UserId]
		if last ~= nil and now - last < SNAPSHOT_COOLDOWN_SECONDS then
			return {}
		end
		lastSnapshotAt[player.UserId] = now
		return orderService:GetActiveSummaries()
	end

	local removing = Players.PlayerRemoving:Connect(function(player)
		lastSnapshotAt[player.UserId] = nil
	end)
	local createdConnection = orderService.OrderCreated:Connect(function(summary)
		updateEvent:FireAllClients(summary)
	end)
	local changedConnection = orderService.OrderChanged:Connect(function(_orderId, _from, _to, summary)
		updateEvent:FireAllClients(summary)
	end)

	return {
		Destroy = function()
			actionFunction.OnServerInvoke = nil :: any
			snapshotFunction.OnServerInvoke = nil :: any
			removing:Disconnect()
			createdConnection:Disconnect()
			changedConnection:Disconnect()
			folder:Destroy()
		end,
	}
end

return OrderRemotes
