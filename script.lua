-- Grappling Hook System
-- For HiddenDevs Scripter Application

--// SERVICES
local Players = game:GetService("Players") -- Access to player-related data
local RunService = game:GetService("RunService") -- For heartbeat/render updates
local UserInputService = game:GetService("UserInputService") -- To detect player input
local Workspace = game:GetService("Workspace") -- Access to game world

--// CONSTANTS
local MAX_DISTANCE = 300 -- Maximum grappling distance
local FORCE_MULTIPLIER = 4000 -- Strength of the grappling force
local COOLDOWN_TIME = 2 -- Cooldown between grapples

--// Grapple Class - This block defines a table structure in Lua to capture the grappling hook logic
local Grapple = {}
Grapple.__index = Grapple

-- Create a new Grapple object for the player
function Grapple.new(player)
	local self = setmetatable({}, Grapple)
	self.Player = player
	self.Character = player.Character or player.CharacterAdded:Wait()
	self.HookActive = false
	self.Cooldown = false
	self.HookPosition = nil
	self.Force = nil
	self.Beam = nil
	self.Attachment0 = nil
	self.Attachment1 = nil
	self.HookPart = nil
	self.PreviewPart = nil
	self.Crosshair = nil
	self.DebugLabel = nil
	self.Heartbeat = nil
	self:Init() -- Setup everything
	return self
end

-- Initialize inputs and UI
function Grapple:Init()
	self:SetupInput()
	self:InitUI()
end

-- Set up input bindings
function Grapple:SetupInput()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end -- Ignore UI-processed inputs
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:FireHook() -- Left click = grapple
		elseif input.KeyCode == Enum.KeyCode.Q then
			self:ReleaseHook() -- Q key = release
		end
	end)
end

-- Attempt to grapple
-- This function is necessary to the grappling mechanic. It performs a raycast from the player's head towards the mouse position
-- to determine if there is a surface to grapple to. If a target is found, it stores the hook position and creates the hook effect.
function Grapple:FireHook()
	if self.HookActive or self.Cooldown then return end
	self.Cooldown = true

	local mouse = self.Player:GetMouse()
	local character = self.Player.Character
	if not character then return end

	-- Raycast from head to mouse
	local origin = character:WaitForChild("Head").Position
	local direction = (mouse.Hit.Position - origin).Unit * MAX_DISTANCE

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {character}
	params.FilterType = Enum.RaycastFilterType.Blacklist

	local result = Workspace:Raycast(origin, direction, params)
	if result then
		self.HookPosition = result.Position
		self:CreateHook()
	end

	task.delay(COOLDOWN_TIME, function()
		self.Cooldown = false
	end)
end

-- Create the hook and attach to target
-- This function visually represents the hook and preps the physics needed to pull the player
function Grapple:CreateHook()
	self.HookActive = true
	local root = self.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	-- Create the red ball at hit position
	local hook = Instance.new("Part")
	hook.Size = Vector3.new(0.5, 0.5, 0.5)
	hook.Shape = Enum.PartType.Ball
	hook.Position = self.HookPosition
	hook.Anchored = true
	hook.CanCollide = false
	hook.BrickColor = BrickColor.new("Bright red")
	hook.Material = Enum.Material.Neon
	hook.Name = "GrappleHook"
	hook.Parent = Workspace
	self.HookPart = hook

	-- Create beam attachments
	local a0 = Instance.new("Attachment")
	local a1 = Instance.new("Attachment")
	a0.Parent = root
	a1.Parent = hook
	self.Attachment0 = a0
	self.Attachment1 = a1

	-- Visual beam between player and hook
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(Color3.new(1, 0, 0))
	beam.Width0 = 0.1
	beam.Width1 = 0.1
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Parent = hook
	self.Beam = beam

	-- Apply pulling force
	local force = Instance.new("VectorForce")
	force.Attachment0 = a0
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Parent = root
	self.Force = force

	-- This updates the pulling force each frame to simulate a grappling effect toward the target.
	self.Heartbeat = RunService.Heartbeat:Connect(function(dt)
		self:UpdateHook()
	end)
end

-- Apply force toward the hook
function Grapple:UpdateHook()
	if not self.HookActive or not self.Force then return end

	local root = self.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local direction = (self.HookPosition - root.Position)
	local distance = direction.Magnitude

	if distance < 5 then
		self:ReleaseHook()
		return
	end

	local velocity = direction.Unit * FORCE_MULTIPLIER
	self.Force.Force = velocity
end

-- Remove all hook elements
function Grapple:ReleaseHook()
	if not self.HookActive then return end

	self.HookActive = false
	self.HookPosition = nil

	if self.Heartbeat then
		self.Heartbeat:Disconnect()
		self.Heartbeat = nil
	end

	if self.Force then
		if self.Force.Attachment0 then
			self.Force.Attachment0:Destroy()
		end
		self.Force:Destroy()
		self.Force = nil
	end

	if self.Beam then self.Beam:Destroy() end
	if self.Attachment0 then self.Attachment0:Destroy() end
	if self.Attachment1 then self.Attachment1:Destroy() end
	if self.HookPart then self.HookPart:Destroy() end

	self.Beam = nil
	self.Attachment0 = nil
	self.Attachment1 = nil
	self.HookPart = nil
end

-- This function also initializes all UI elements for the grappling hook system, inclkuding the crosshairs and debug label.
function Grapple:InitUI()
	self:CreateCrosshair()
	self:CreateDebugHUD()
end

-- Crosshair at screen center
function Grapple:CreateCrosshair()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "GrappleUI"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = self.Player:WaitForChild("PlayerGui")

	local crosshair = Instance.new("Frame")
	crosshair.Size = UDim2.new(0, 8, 0, 8)
	crosshair.Position = UDim2.new(0.5, -4, 0.5, -4)
	crosshair.BackgroundColor3 = Color3.new(1, 1, 1)
	crosshair.BorderSizePixel = 0
	crosshair.Name = "Crosshair"
	crosshair.Parent = screenGui

	self.Crosshair = crosshair
end

-- Change crosshair color based on raycast
function Grapple:UpdateCrosshairColor(isValid)
	if not self.Crosshair then return end
	self.Crosshair.BackgroundColor3 = isValid and Color3.new(0, 1, 0) or Color3.new(1, 1, 1)
end

-- Show preview dot on target
function Grapple:UpdatePreviewRay()
	local mouse = self.Player:GetMouse()
	local character = self.Player.Character
	if not character then return end

	local origin = character:WaitForChild("Head").Position
	local direction = (mouse.Hit.Position - origin).Unit * MAX_DISTANCE

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {character}
	params.FilterType = Enum.RaycastFilterType.Blacklist

	local result = Workspace:Raycast(origin, direction, params)
	self:UpdateCrosshairColor(result ~= nil)

	if not self.PreviewPart then
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.new(1, 1, 0)
		p.Name = "RayPreview"
		p.Size = Vector3.new(0.2, 0.2, 0.2)
		p.Parent = Workspace
		self.PreviewPart = p
	end

	if result then
		self.PreviewPart.Position = result.Position
		self.PreviewPart.Transparency = 0
	else
		self.PreviewPart.Transparency = 1
	end
end

-- Create label with grapple status
function Grapple:CreateDebugHUD()
	local label = Instance.new("TextLabel")
	label.Name = "DebugLabel"
	label.Size = UDim2.new(0, 200, 0, 50)
	label.Position = UDim2.new(0, 10, 0, 10)
	label.BackgroundTransparency = 0.3
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Text = "Grapple: Inactive"
	label.Parent = self.Player.PlayerGui:WaitForChild("GrappleUI")
	self.DebugLabel = label
end

-- Update the HUD with current state
function Grapple:UpdateDebugHUD()
	if not self.DebugLabel then return end
	if self.HookActive then
		self.DebugLabel.Text = "Grapple: Active"
	elseif self.Cooldown then
		self.DebugLabel.Text = "Grapple: Cooldown"
	else
		self.DebugLabel.Text = "Grapple: Ready"
	end
end

--// BOOTSTRAP (Start the system)
local localPlayer = Players.LocalPlayer
localPlayer.CharacterAdded:Wait()
local grappleSystem = Grapple.new(localPlayer)

-- Update UI and ray preview every frame
RunService.RenderStepped:Connect(function()
	if grappleSystem then
		grappleSystem:UpdatePreviewRay()
		grappleSystem:UpdateDebugHUD()
	end
end)
