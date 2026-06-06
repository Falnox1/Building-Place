--[[
	Script by Falnox | GoldGamerHack (discord | roblox old nickname)
	278 lines of code
	Client script: placing, moving and deleting builds
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Players           = game:GetService("Players")

-- Modules
local Modules      = ReplicatedStorage:WaitForChild("Modules")
local Settings     = require(Modules:WaitForChild("Config"))
local Config       = Settings.Build
local Palette      = Settings.Palette
local Building     = Modules:WaitForChild("Building")
local ItemCatalog  = require(Building:WaitForChild("ItemCatalog"))
local Grounding    = require(Building:WaitForChild("Grounding"))
local Validator    = require(Building:WaitForChild("PlacementValidator"))
local GridUtil     = require(Building:WaitForChild("GridUtil"))

-- Remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Variables
local localPlayer = Players.LocalPlayer
local mouse       = localPlayer:GetMouse()

-- Constants
local KEY_MOVE   = Config.KEY_MOVE
local KEY_DELETE = Config.KEY_DELETE

-- all cube faces except the bottom (otherwise it looks bad while moving)
local FACES      = { Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }
local OFF_COLOR  = Palette.Off
local MOVE_BLUE  = Palette.Blue

-- checks if the right mouse button is held, to avoid conflicts with camera rotation
local function cameraDragging(): boolean
	return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
end

-- clone the ready-made BuildHud (because CharacterAutoLoads is off)
local playerGui = localPlayer:WaitForChild("PlayerGui")
local oldHud    = playerGui:FindFirstChild("BuildHud")
if oldHud then oldHud:Destroy() end
local gui  = game:GetService("StarterGui"):WaitForChild("BuildHud"):Clone()
gui.Parent = playerGui

-- BindsHud: hints panel at bottom-right, rows are cloned from a template for the current mode
local BindsHud = {}
do
	local frame    = gui:WaitForChild("Binds")
	local template = frame:WaitForChild("RowTemplate")
	local SHOWN    = UDim2.new(1, -16, 1, -78)
	local HIDDEN   = UDim2.new(1, 60, 1, -78)

	-- rebuild the rows from the given list and animate the panel
	function BindsHud.show(rows)
		-- remove previously cloned rows, but keep the template itself
		for _, c in frame:GetChildren() do
			if c:IsA("Frame") and c ~= template then c:Destroy() end
		end
		for i, rw in rows do
			local r = template:Clone()
			r.LayoutOrder = i; r.Visible = true
			r.Key.Text = rw[1]; r.Desc.Text = rw[2]
			r.Parent = frame
		end
		frame.Visible = true
		TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quart), { Position = SHOWN }):Play()
	end

	-- animate the panel out, then hide it (only if it's still off-screen, so a quick re-show doesn't hide it)
	function BindsHud.hide()
		local t = TweenService:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In), { Position = HIDDEN })
		t.Completed:Once(function() if frame.Position.X.Offset >= 59 then frame.Visible = false end end)
		t:Play()
	end
end

-- Toolbar: Edit / Delete buttons, each has Mode and active color attributes set in the explorer
local Toolbar = { onMode = nil }
do
	local bar     = gui:WaitForChild("Toolbar")
	local buttons = {}
	for _, b in bar:GetChildren() do
		if b:IsA("TextButton") then
			local mode = b:GetAttribute("Mode")
			buttons[mode] = { btn = b, on = b:GetAttribute("OnColor") }
			b.MouseButton1Click:Connect(function() if Toolbar.onMode then Toolbar.onMode(mode) end end)
		end
	end

	-- highlight the active mode button, set the rest to OFF_COLOR
	function Toolbar.setActive(mode)
		for m, info in buttons do
			info.btn.BackgroundColor3 = (m == mode) and info.on or OFF_COLOR
		end
	end
end

-- returns the build under the mouse or nil (climbs from the hit part up to the model inside PlacedBuilds)
local function modelUnderMouse(): Model?
	local target = mouse.Target
	if not target then return nil end
	local root = workspace:FindFirstChild(Config.BUILDS_ROOT)
	if not root then return nil end
	local m = target
	while m and m.Parent ~= root do m = m.Parent end
	return m
end

-- hides or shows a model (used to hide the original while moving)
local function setLocalHidden(model: Model, hidden: boolean): ()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then d.LocalTransparencyModifier = hidden and 1 or 0 end
	end
end

-- Placement: drives the semi-transparent preview, grid snap, rotation, tilt and validation
local Placement = {}
Placement.__index = Placement

function Placement.new()
	return setmetatable({ active = false }, Placement)
end

-- builds the preview clone (no collision, semi-transparent) plus the colored hitbox cube
function Placement:_prepPreview(): ()
	local m = self.template:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false; d.CanQuery = false; d.Anchored = true
			-- keep already-invisible parts invisible, make the rest semi-transparent
			if d.Transparency < 1 then d.Transparency = 0.55 end
		end
	end
	m.Name = "__Preview"; m.Parent = workspace
	self.preview = m

	-- hitbox size and the bbox offset relative to the model
	local cf, size = ItemCatalog.computeHitbox(self.template)
	self.hbSize  = size
	self.relBBox = self.template:GetPivot():Inverse() * cf

	-- create the invisible hitbox cube
	local hb = Instance.new("Part")
	hb.Name = "__Hitbox"; hb.Size = size; hb.Anchored = true
	hb.CanCollide = false; hb.CanQuery = false; hb.Transparency = 1; hb.Parent = m

	self.faceFrames = {}
	-- for each face create a SurfaceGui with a frame
	for _, face in FACES do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face; sg.Adornee = hb; sg.AlwaysOnTop = false
		sg.LightInfluence = 0; sg.PixelsPerStud = 4; sg.Parent = hb
		local f = Instance.new("Frame", sg)
		f.Size = UDim2.fromScale(1, 1); f.BorderSizePixel = 0
		f.BackgroundColor3 = Config.COL_OK; f.BackgroundTransparency = Config.HITBOX_TR
		table.insert(self.faceFrames, f)
	end

	-- create the outline around the whole hitbox
	local sb = Instance.new("SelectionBox")
	sb.Adornee = hb; sb.LineThickness = 0.05; sb.Color3 = Config.COL_OK
	sb.SurfaceTransparency = 1; sb.Parent = hb
	self.hitbox = hb; self.selbox = sb
end

-- recolors every visible face and the outline to the needed colors
function Placement:_setColor(col: Color3): ()
	for _, f in self.faceFrames do f.BackgroundColor3 = col end
	self.selbox.Color3 = col
end

-- start placing: save the category and name to send to the server
function Placement:begin(category: string, name: string, slot: number?, moveCtx): ()
	self:stop()
	self.template = ItemCatalog.getTemplate(category, name)
	if not self.template then return end
	self.category, self.name, self.slot = category, name, slot
	self.rot       = (moveCtx and moveCtx.rot) or 0
	self.moveId    = moveCtx and moveCtx.buildId or nil
	self.moveModel = moveCtx and moveCtx.model or nil
	self.active = true; self.valid = false
	self.current = nil; self.smoothVel = Vector3.zero; self.prevCurrent = nil
	self.cx, self.cz, self.crot = nil, nil, nil

	-- hide the original so only the ghost follows the mouse
	if self.moveModel then setLocalHidden(self.moveModel, true) end
	self:_prepPreview()
	-- compute the metrics
	self.metrics = Grounding.prepare(self.template)
	self.params  = Grounding.surfaceParams()
	-- when moving, ignore the original
	self.ignoreModel = self.moveModel or self.preview

	-- reusable params for the mouse->ground ray: skip placed builds and our preview
	local gp = RaycastParams.new()
	gp.FilterType = Enum.RaycastFilterType.Exclude
	gp.FilterDescendantsInstances = { workspace:FindFirstChild(Config.BUILDS_ROOT), self.preview }
	self.groundParams = gp

	BindsHud.show(self.moveId and {
		{ "LMB", "Confirm" }, { "R", "Rotate" }, { "X", "Cancel" },
	} or {
		{ "LMB", "Place" }, { "R", "Rotate" }, { "1-8 / X", "Exit" },
	})
	self.stepConn  = RunService.RenderStepped:Connect(function(dt) self:_step(dt) end)
	self.inputConn = UserInputService.InputBegan:Connect(function(inp, gpe) self:_input(inp, gpe) end)
end

-- per-frame update: ray to the ground, snap, validation on cell change, then smooth movement and tilt of the preview
function Placement:_step(dt: number): ()
	local ray = mouse.UnitRay
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 5000, self.groundParams)
	local gp  = hit and hit.Position or nil

	if gp then
		local sx, sz = GridUtil.snap(gp.X), GridUtil.snap(gp.Z)
		-- recompute target + validation only when the cell or rotation actually changed (optimization)
		if sx ~= self.cx or sz ~= self.cz or self.rot ~= self.crot then
			self.cx, self.cz, self.crot = sx, sz, self.rot
			self.gridX, self.gridZ = sx / Config.GRID, sz / Config.GRID
			self.lastTarget = Grounding.solveFrom(self.metrics, sx, sz, self.rot * Config.ROT_STEP, self.params, gp.Y)
			self.valid = Validator.isValid(self.lastTarget * self.relBBox, self.hbSize, self.ignoreModel)
			self:_setColor(self.valid and Config.COL_OK or Config.COL_BAD)
		end
	end

	-- if the mouse left the ground for a frame, just settle on the last target
	local target = self.lastTarget or self.current
	if not target then return end
	if not self.current then self.current = target end
	self.current = self.current:Lerp(target, 1 - math.exp(-Config.MOVE_RESPONSE * dt))

	-- tilt from the object's own speed (so there's no tilt while within one cell)
	local cvel = (self.current.Position - (self.prevCurrent or self.current.Position)) / math.max(dt, 1 / 240)
	self.prevCurrent = self.current.Position
	self.smoothVel = self.smoothVel:Lerp(cvel, 1 - math.exp(-Config.TILT_SMOOTH * dt))
	local tiltX = math.clamp(self.smoothVel.Z * Config.TILT_FACTOR, -Config.TILT_MAX, Config.TILT_MAX)
	local tiltZ = math.clamp(-self.smoothVel.X * Config.TILT_FACTOR, -Config.TILT_MAX, Config.TILT_MAX)

	-- apply the tilt around the current position, keeping the model's yaw
	local rotOnly   = self.current - self.current.Position
	local displayCF = CFrame.new(self.current.Position) * CFrame.Angles(tiltX, 0, tiltZ) * rotOnly
	self.preview:PivotTo(displayCF)
	self.hitbox.CFrame = displayCF * self.relBBox
end

-- input handling while placing
function Placement:_input(inp: InputObject, gpe: boolean): ()
	if gpe then return end
	if inp.KeyCode == Enum.KeyCode.R then
		self.rot = (self.rot + 1) % 4
	elseif inp.KeyCode == Enum.KeyCode.X then
		self:stop()
	elseif inp.UserInputType == Enum.UserInputType.MouseButton1 then
		-- ignore the click if it's camera rotation or the spot is invalid
		if cameraDragging() or not self.valid then return end
		if self.moveId then
			-- confirm moving an existing build
			remotes.MoveObject:FireServer(self.moveId, self.gridX, self.gridZ, self.rot)
			self:stop()
		else
			-- place a new build;
			remotes.PlaceObject:FireServer(self.category, self.name, self.gridX, self.gridZ, self.rot)
		end
	end
end

-- removes the preview and restores the hidden original (on confirm or cancel)
function Placement:stop(): ()
	if self.stepConn then self.stepConn:Disconnect(); self.stepConn = nil end
	if self.inputConn then self.inputConn:Disconnect(); self.inputConn = nil end
	if self.preview then self.preview:Destroy(); self.preview = nil end
	if self.moveModel then setLocalHidden(self.moveModel, false); self.moveModel = nil end
	if self.active then BindsHud.hide() end
	self.active = false; self.slot = nil
end

-- create the Edit metatable that manages the modes
local Edit = {}
Edit.__index = Edit

-- init Edit, keep a reference to Placement to turn it off when entering edit mode
function Edit.new(placement)
	return setmetatable({ mode = nil, placement = placement }, Edit)
end

-- creates the hover highlight
function Edit:_ensureHL(): ()
	if self.hl then return end
	local hl = Instance.new("Highlight")
	hl.FillTransparency = 0.55; hl.OutlineColor = Color3.fromRGB(230, 230, 255)
	hl.Enabled = false; hl.Parent = workspace
	self.hl = hl
end

-- highlights the build under the cursor in the mode's color
function Edit:_hover(): ()
	local m = self.mode and modelUnderMouse() or nil
	if self.hl then
		self.hl.Adornee  = m
		self.hl.Enabled  = m ~= nil
		self.hl.FillColor = (self.mode == "delete") and Config.COL_BAD or MOVE_BLUE
	end
end

-- function to turn the edit modes on/off
function Edit:setMode(mode: string?): ()
	if self.mode == mode then mode = nil end
	self.mode = mode
	Toolbar.setActive(mode)
	-- make it so you can't place new objects
	if mode and self.placement.active then self.placement:stop() end

	-- check entering a mode: if mode isn't nil, enable the highlight and binds, otherwise disable
	if mode then
		self:_ensureHL()
		-- if not created earlier, create the RenderStepped connection
		if not self.stepConn then self.stepConn = RunService.RenderStepped:Connect(function() self:_hover() end) end
		-- if not created earlier, create the InputBegan connection
		if not self.inputConn then self.inputConn = UserInputService.InputBegan:Connect(function(inp, gpe) self:_input(inp, gpe) end) end
		BindsHud.show(mode == "delete" and {
			{ "LMB", "Delete" }, { "T", "Exit mode" },
		} or {
			{ "LMB", "Pick & move" }, { "E", "Exit mode" },
		})
	else
		-- leaving edit: drop the connections and hide the highlight + hints
		if self.stepConn then self.stepConn:Disconnect(); self.stepConn = nil end
		if self.inputConn then self.inputConn:Disconnect(); self.inputConn = nil end
		if self.hl then self.hl.Enabled = false; self.hl.Adornee = nil end
		BindsHud.hide()
	end
end

-- click in edit mode: delete or pick up for moving the build under the cursor
function Edit:_input(inp: InputObject, gpe: boolean): ()
	if gpe then return end
	if inp.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	-- ignore clicks that rotate the camera
	if cameraDragging() then return end
	local m = modelUnderMouse()
	if not m then return end
	if self.mode == "delete" then
		remotes.DeleteObject:FireServer(m:GetAttribute("BuildId"))
	elseif self.mode == "move" then
		-- hand the build to Placement with its current id/rotation, leaving the mode first
		local ctx = { buildId = m:GetAttribute("BuildId"), rot = m:GetAttribute("Rot"), model = m }
		local cat, name = m:GetAttribute("Category"), m:GetAttribute("ItemName")
		self:setMode(nil)
		self.placement:begin(cat, name, nil, ctx)
	end
end

-- init the main Placement and Edit objects, and the bind for the toolbar buttons
local placement = Placement.new()
local edit      = Edit.new(placement)
Toolbar.onMode  = function(mode) edit:setMode(mode) end

-- receive the start-placement event from the hotbar; if the slot matches the current one, turn placement off, otherwise start a new one
remotes.StartPlacement.Event:Connect(function(category: string, name: string, slot: number)
	if placement.active and not placement.moveId and placement.slot == slot then
		placement:stop()
		return
	end
	if edit.mode then edit:setMode(nil) end
	placement:begin(category, name, slot)
end)

-- binds for the edit modes
UserInputService.InputBegan:Connect(function(inp: InputObject, gpe: boolean)
	if gpe then return end
	if inp.KeyCode == KEY_MOVE then edit:setMode("move")
	elseif inp.KeyCode == KEY_DELETE then edit:setMode("delete") end
end)
