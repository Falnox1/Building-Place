local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config")).Camera

local focus = Vector3.zero
local velocity = Vector3.zero
local yaw = 0
local pitch = Config.PITCH_START
local zoom = 220
local zoomTarget = zoom
local isDragging = false

repeat task.wait() until workspace.CurrentCamera
workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable

UserInputService.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
	isDragging = true
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
	isDragging = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end)

UserInputService.InputChanged:Connect(function(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
	zoomTarget = math.clamp(zoomTarget - input.Position.Z * Config.ZOOM_STEP, Config.ZOOM_MIN, Config.ZOOM_MAX)
end)

local function moveInput(): (number, number)
	local forward, right = 0, 0
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then forward += 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then forward -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then right += 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then right -= 1 end
	return forward, right
end

local function updateCamera(dt: number)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable

	if isDragging then
		local delta = UserInputService:GetMouseDelta()
		yaw -= delta.X * Config.YAW_SENS
		pitch = math.clamp(pitch + delta.Y * Config.PITCH_SENS, Config.PITCH_MIN, Config.PITCH_MAX)
	end

	local boosting = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	local speed = if boosting then Config.BOOST_SPEED else Config.MOVE_SPEED

	local forward, right = moveInput()
	local forwardDir = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local rightDir = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
	local desired = forwardDir * forward + rightDir * right
	desired = if desired.Magnitude > 0 then desired.Unit * speed else Vector3.zero
	velocity = velocity:Lerp(desired, 1 - math.exp(-Config.MOVE_ACCEL * dt))

	focus = Vector3.new(
		math.clamp(focus.X + velocity.X * dt, Config.MIN_X, Config.MAX_X),
		0,
		math.clamp(focus.Z + velocity.Z * dt, Config.MIN_Z, Config.MAX_Z)
	)

	zoom += (zoomTarget - zoom) * (1 - math.exp(-Config.ZOOM_RESPONSE * dt))

	local fovTarget = if boosting and (forward ~= 0 or right ~= 0) then Config.FOV_BASE + Config.FOV_BOOST else Config.FOV_BASE
	camera.FieldOfView += (fovTarget - camera.FieldOfView) * (1 - math.exp(-Config.FOV_RESPONSE * dt))

	local height = zoom * math.sin(pitch)
	local horizontal = zoom * math.cos(pitch)
	local position = focus + Vector3.new(math.sin(yaw) * horizontal, height, math.cos(yaw) * horizontal)
	camera.CFrame = CFrame.lookAt(position, focus)
end

RunService:BindToRenderStep("CustomCamera", Enum.RenderPriority.Last.Value, updateCamera)
