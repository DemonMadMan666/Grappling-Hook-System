--[[
    GrappleModule.lua
    -----------------
    Grappling Hook System for HiddenDevs Application

    OVERVIEW:
    This system lets a player to shoot a grappling hook towards a valid surface and it
    visually connects them with a beam which applies pulling force until they reach
    the target or release early.

    HOW IT WORKS:
    1. INPUT DETECTION:
        - Left Mouse Button: Attempt grapple
        - Q Key: Release hook
    2. GRAPPLE ATTEMPT:
        - Performs an angle check.
        - Raycasts towards the mouse hit position to detect a valid target.
        - Uses CollectionService for tagged grapple points.
    3. HOOK CREATION:
        - Visually represented as a ball that tweens from player to target.
        - Beam connects player and hook.
        - VectorForce pulls the player toward target.
    4. RELEASE:
        - Triggered when close to target or player cancels.
        - Cleans up all temporary objects & enters cooldown before next grapple.
    5. UI + FEEDBACK:
        - Crosshair changes color on failure.
        - Debug label shows current state.
        - Update loop syncs UI with grappling state.
]]

--// SERVICES
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")

--// CONSTANTS
local MAX_DISTANCE = 300
local FORCE_MULTIPLIER = 4000
local COOLDOWN_TIME = 2
local ANGLE_LIMIT = 120 -- max degrees from camera forward direction

--// STATE ENUM — improves clarity over multiple booleans
local GrappleState = {
	Idle = "Idle",
	Active = "Active",
	Cooldown = "Cooldown"
}

--// CLASS
local Grapple = {}
Grapple.__index = Grapple

-- Constructor
function Grapple.new(player)
	local self = setmetatable({}, Grapple)
	self.Player = player
	self.Character = player.Character or player.CharacterAdded:Wait()
	self.Root = self.Character:WaitForChild("HumanoidRootPart")
	self.State = GrappleState.Idle

	self.HookPart = nil
	self.Beam = nil
	self.Force = nil
	self.Attachments = {}
	self.HeartbeatConn = nil
	self.CooldownFinish = 0

	self:Init()
	return self
end

-- Initialize system: binds input & sets up UI
function Grapple:Init()
	self:SetupInput()
	self:InitUI()
end

-- Binds player input for grapple actions
function Grapple:SetupInput()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:AttemptGrapple()
		elseif input.KeyCode == Enum.KeyCode.Q then
			self:ReleaseHook()
		end
	end)
end

-- Player tries to grapple
function Grapple:AttemptGrapple()
	-- Prevents spamming during cooldown or while active
	if self.State ~= GrappleState.Idle or tick() < self.CooldownFinish then return end

	local mouse = self.Player:GetMouse()
	local origin = self.Character:WaitForChild("Head").Position
	local direction = (mouse.Hit.Position - origin)

	-- Angle check: ensures that the hook can’t fire directly behind player
	local camLook = workspace.CurrentCamera.CFrame.LookVector
	if math.deg(math.acos(camLook:Dot(direction.Unit))) > ANGLE_LIMIT then
		self:ShowFailFeedback()
		return
	end

	-- Raycast towards mouse position
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {self.Character}
	params.FilterType = Enum.RaycastFilterType.Blacklist

	local result = workspace:Raycast(origin, direction.Unit * MAX_DISTANCE, params)

	-- Checks if hit surface is valid
	if result and self:IsSurfaceValid(result.Instance) then
		self:FireHook(result.Position)
	else
		self:ShowFailFeedback()
	end
end

-- Determines if a surface can be grappled
function Grapple:IsSurfaceValid(instance)
	-- Tagged grapple points take priority, otherwise default to allowing all
	return CollectionService:HasTag(instance, "GrapplePoint") or true
end

-- Create hook visuals, tween into place, and attach pulling force
function Grapple:FireHook(hitPosition)
	self.State = GrappleState.Active

	-- Create hook part (visual anchor in world)
	local hook = Instance.new("Part")
	hook.Size = Vector3.new(0.5, 0.5, 0.5)
	hook.Shape = Enum.PartType.Ball
	hook.Material = Enum.Material.Neon
	hook.BrickColor = BrickColor.new("Bright red")
	hook.Anchored = true
	hook.CanCollide = false
	hook.CFrame = CFrame.new(self.Root.Position)
	hook.Name = "GrappleHook"
	hook.Parent = workspace
	self.HookPart = hook
	Debris:AddItem(hook, 10) -- Clean automatically in case of unexpected release

	-- Tween hook from player to target for visual polish
	local tween = TweenService:Create(hook, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = hitPosition
	})
	tween:Play()

	-- Create attachments for beam & force
	local a0 = Instance.new("Attachment", self.Root)
	local a1 = Instance.new("Attachment", hook)
	self.Attachments = {a0, a1}

	-- Beam visually connects player and hook
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 0, 0))
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
	force.Parent = self.Root
	self.Force = force

	-- Start continuous pull update
	self.HeartbeatConn = RunService.Heartbeat:Connect(function()
		self:UpdatePull(hitPosition)
	end)
end

-- Update pulling force each frame
function Grapple:UpdatePull(targetPos)
	local direction = (targetPos - self.Root.Position)
	local distance = direction.Magnitude

	-- Rope tension: pull force decreases as player gets closer
	local tensionFactor = math.clamp(distance / MAX_DISTANCE, 0.2, 1)
	local velocity = direction.Unit * FORCE_MULTIPLIER * tensionFactor
	self.Force.Force = velocity

	-- Release once close enough to target
	if distance < 5 then
		self:ReleaseHook()
	end
end

-- Release hook & cleanup
function Grapple:ReleaseHook()
	if self.State ~= GrappleState.Active then return end
	self.State = GrappleState.Cooldown
	self.CooldownFinish = tick() + COOLDOWN_TIME

	if self.HeartbeatConn then
		self.HeartbeatConn:Disconnect()
		self.HeartbeatConn = nil
	end

	if self.Force then self.Force:Destroy() self.Force = nil end
	if self.Beam then self.Beam:Destroy() self.Beam = nil end
	for _, att in ipairs(self.Attachments) do att:Destroy() end
	self.Attachments = {}
	if self.HookPart then self.HookPart:Destroy() self.HookPart = nil end

	-- Returns to idle after cooldown
	task.delay(COOLDOWN_TIME, function()
		self.State = GrappleState.Idle
	end)
end

-- Creates crosshair & debugs UI
function Grapple:InitUI()
	local gui = Instance.new("ScreenGui")
	gui.Name = "GrappleUI"
	gui.ResetOnSpawn = false
	gui.Parent = self.Player:WaitForChild("PlayerGui")

	local crosshair = Instance.new("Frame")
	crosshair.Size = UDim2.new(0, 8, 0, 8)
	crosshair.Position = UDim2.new(0.5, -4, 0.5, -4)
	crosshair.BackgroundColor3 = Color3.new(1, 1, 1)
	crosshair.BorderSizePixel = 0
	crosshair.Parent = gui
	self.Crosshair = crosshair

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 200, 0, 50)
	label.Position = UDim2.new(0, 10, 0, 10)
	label.BackgroundTransparency = 0.3
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Text = "State: Idle"
	label.Parent = gui
	self.DebugLabel = label

	-- Keeps UI synced to state
	RunService.RenderStepped:Connect(function()
		self:UpdateUI()
	end)
end

-- Updates UI elements based on state
function Grapple:UpdateUI()
	if not self.DebugLabel then return end
	self.DebugLabel.Text = "State: " .. self.State
end

-- Visual fail feedback for invalid grapples
function Grapple:ShowFailFeedback()
	if self.Crosshair then
		self.Crosshair.BackgroundColor3 = Color3.new(1, 0, 0)
		task.delay(0.2, function()
			if self.Crosshair then
				self.Crosshair.BackgroundColor3 = Color3.new(1, 1, 1)
			end
		end)
	end
end

return Grapple
