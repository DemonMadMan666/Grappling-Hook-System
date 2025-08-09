-- LocalScript to hook it into the player

local Players = game:GetService("Players")
local Grapple = require(script.Parent.GrappleModule)

local player = Players.LocalPlayer
player.CharacterAdded:Wait()

local grappleSystem = Grapple.new(player)
