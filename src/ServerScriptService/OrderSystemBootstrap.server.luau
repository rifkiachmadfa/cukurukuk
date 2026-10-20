--!strict
--[[
	OrderSystemBootstrap — starts the OrderSystem on the server.
	Standalone on purpose so it cannot collide with an existing ServerBootstrap. When a central
	bootstrap exists, call require(Services.OrderSystem).Start() from there and delete this file.
]]

local OrderSystem = require(script.Parent.Services.OrderSystem)

local ok, err = pcall(OrderSystem.Start)
if not ok then
	warn("[OrderSystemBootstrap] OrderSystem gagal start:", err)
end
