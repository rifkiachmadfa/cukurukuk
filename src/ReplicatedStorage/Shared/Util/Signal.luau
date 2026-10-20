--!strict
--[[
	Signal — tiny dependency-free signal used by server services.
	Handlers run in their own thread (task.spawn), so a failing handler cannot break the emitter.
]]

local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (self: Connection) -> () }

export type Signal = typeof(setmetatable({} :: {
	_handlers: { [number]: (...any) -> () },
	_nextId: number,
}, Signal))

function Signal.new(): Signal
	return setmetatable({ _handlers = {}, _nextId = 0 }, Signal)
end

function Signal.Connect(self: Signal, handler: (...any) -> ()): Connection
	self._nextId += 1
	local id = self._nextId
	self._handlers[id] = handler
	local connection = {}
	function connection.Disconnect(_: Connection)
		self._handlers[id] = nil
	end
	return connection :: Connection
end

function Signal.Fire(self: Signal, ...: any)
	for _, handler in self._handlers do
		task.spawn(handler, ...)
	end
end

function Signal.DisconnectAll(self: Signal)
	table.clear(self._handlers)
end

return Signal
