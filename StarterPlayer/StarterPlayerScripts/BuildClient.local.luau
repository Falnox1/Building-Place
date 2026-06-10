--[[
	Script by Falnox | GoldGamerHack (discord | roblox old nickname)
	286 lines of code
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

-- Constants
local KEY_MOVE   = Config.KEY_MOVE
local KEY_DELETE = Config.KEY_DELETE

-- every cube face except the bottom. we leave the bottom open on purpose - looks cleaner while you drag the build around
local FACES      = { Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }
local OFF_COLOR  = Palette.Off
local MOVE_BLUE  = Palette.Blue

--[[
	while RMB is held the player is rotating the camera, so we swallow mouse clicks in that moment -
	otherwise you'd accidentally place a build or grab one. we read the button state directly
	instead of keeping a separate flag, so it can't drift out of sync
]]
local function cameraDragging(): boolean
	return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
end

--[[
	this used to be localPlayer:GetMouse(), but it's considered deprecated (so I rewrote it).
	now we build the cursor ray ourselves: take the mouse location and shoot it out of the camera.
	the same ray is later used both to probe the ground and to pick builds under the cursor
]]
local function mouseRay(): Ray?
	local camera = workspace.CurrentCamera
	if not camera then return nil end -- the camera might not exist yet on the very first frames
	local location = UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(location.X, location.Y)
end

--[[
	CharacterAutoLoads is off and there's no character - so the GUI won't be auto-copied into PlayerGui either.
	so we grab the prebuilt BuildHud from StarterGui and parent it to the player ourselves.
	if an old one somehow stuck around, nuke it first - so we don't end up with a duplicate
]]
local playerGui = localPlayer:WaitForChild("PlayerGui")
local oldHud    = playerGui:FindFirstChild("BuildHud")
if oldHud then oldHud:Destroy() end
local gui  = game:GetService("StarterGui"):WaitForChild("BuildHud"):Clone()
gui.Parent = playerGui

--[[
	BindsHud - the little key-hint panel (bottom right).
	the rows aren't hardcoded: a row template lives in the GUI, and we just clone it for the current mode
]]
local BindsHud = {}
do
	local frame    = gui:WaitForChild("Binds")
	local template = frame:WaitForChild("RowTemplate")
	local SHOWN    = UDim2.new(1, -16, 1, -78)
	local HIDDEN   = UDim2.new(1, 60, 1, -78)

	-- rebuild the rows for the given list and slide the panel in
	function BindsHud.show(rows)
		-- drop the old rows, but keep the template itself
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

	--[[
		slide the panel off-screen and hide it. but the mode could change mid-tween and show it again -
		so we only really hide it if it actually made it past the edge.
		the 59 threshold is basically HIDDEN (where X = 60); if it got re-shown, X goes negative and we skip hiding
	]]
	function BindsHud.hide()
		local t = TweenService:Create(frame, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In), { Position = HIDDEN })
		t.Completed:Once(function() if frame.Position.X.Offset >= 59 then frame.Visible = false end end)
		t:Play()
	end
end

--[[
	toolbar with the Edit / Delete buttons. which mode a button is and what color to highlight it with
	lives in the button's own attributes (set in the explorer), so we don't duplicate that here in code
]]
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

	-- paint the active button in its color, dim the rest
	function Toolbar.setActive(mode)
		for m, info in buttons do
			info.btn.BackgroundColor3 = (m == mode) and info.on or OFF_COLOR
		end
	end
end

--[[
	find the build under the cursor. shoot the ray and from whatever we hit, climb up the parents
	until we land right inside the builds container. if it's not a build under the cursor
	(ground, sky) - returns nil
]]
local function modelUnderMouse(): Model?
	local ray = mouseRay()
	if not ray then return nil end
	local result = workspace:Raycast(ray.Origin, ray.Direction * 5000) -- 5000 - just way more than the map size, so the ray definitely reaches
	local m: Instance? = result and result.Instance
	if not m then return nil end
	local root = workspace:FindFirstChild(Config.BUILDS_ROOT)
	if not root then return nil end
	while m and m.Parent ~= root do m = m.Parent end
	return m
end

--[[
	hide/show a model on this client only (LocalTransparencyModifier).
	needed while moving: the original is hidden, the player drags the ghost and doesn't see two identical models.
	on the server and for other players the object stays put
]]
local function setLocalHidden(model: Model, hidden: boolean): ()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then d.LocalTransparencyModifier = hidden and 1 or 0 end
	end
end

--[[
	Placement - all the preview logic: drag the ghost with the cursor, snap to grid,
	rotate it, tilt it a bit while moving, and check whether you can build here
]]
local Placement = {}
Placement.__index = Placement

function Placement.new()
	return setmetatable({ active = false }, Placement)
end

--[[
	build the preview for the chosen item: clone the model (no collision, semi-transparent)
	and add a cube hitbox. checking placement and highlighting against the cube is cheaper than against the whole model geometry
]]
function Placement:_prepPreview(): ()
	local m = self.template:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false; d.CanQuery = false; d.Anchored = true
			-- don't touch already-invisible parts, dim the rest - so it reads as a ghost
			if d.Transparency < 1 then d.Transparency = 0.55 end
		end
	end
	m.Name = "__Preview"; m.Parent = workspace
	self.preview = m

	-- compute the hitbox size and its offset from the pivot once, so we don't redo it every frame
	local cf, size = ItemCatalog.computeHitbox(self.template)
	self.hbSize  = size
	self.relBBox = self.template:GetPivot():Inverse() * cf

	-- the cube itself is invisible, we'll draw its faces separately below
	local hb = Instance.new("Part")
	hb.Name = "__Hitbox"; hb.Size = size; hb.Anchored = true
	hb.CanCollide = false; hb.CanQuery = false; hb.Transparency = 1; hb.Parent = m

	self.faceFrames = {}
	-- draw faces as separate SurfaceGuis: you can't hide a single face of a normal Part (it renders as a whole), and we need an open bottom
	for _, face in FACES do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face; sg.Adornee = hb; sg.AlwaysOnTop = false
		sg.LightInfluence = 0; sg.PixelsPerStud = 4; sg.Parent = hb
		local f = Instance.new("Frame", sg)
		f.Size = UDim2.fromScale(1, 1); f.BorderSizePixel = 0
		f.BackgroundColor3 = Config.COL_OK; f.BackgroundTransparency = Config.HITBOX_TR
		table.insert(self.faceFrames, f)
	end

	-- plus an outline along the edges, so the cube reads on top of the semi-transparent faces
	local sb = Instance.new("SelectionBox")
	sb.Adornee = hb; sb.LineThickness = 0.05; sb.Color3 = Config.COL_OK
	sb.SurfaceTransparency = 1; sb.Parent = hb
	self.hitbox = hb; self.selbox = sb
end

-- recolor all faces and the outline at once: green - can build, red - can't
function Placement:_setColor(col: Color3): ()
	for _, f in self.faceFrames do f.BackgroundColor3 = col end
	self.selbox.Color3 = col
end

--[[
	start placing. if moveCtx was passed - we're not placing a new object,
	we're relocating an existing one (so it'll send MoveObject instead of PlaceObject)
]]
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

	-- relocating an existing one - hide the original so only the ghost follows the mouse
	if self.moveModel then setLocalHidden(self.moveModel, true) end
	self:_prepPreview()
	-- compute the grounding metrics and params once here, _step just reuses them
	self.metrics = Grounding.prepare(self.template)
	self.params  = Grounding.surfaceParams()
	-- when relocating, skip the original itself, otherwise its hitbox would block itself
	self.ignoreModel = self.moveModel or self.preview

	--[[
		the ground ray needs to pass through already-placed builds and our own preview,
		otherwise we'd hit them instead of the grass under them. so we build a separate filter
	]]
	local gp = RaycastParams.new()
	gp.FilterType = Enum.RaycastFilterType.Exclude
	gp.FilterDescendantsInstances = { workspace:FindFirstChild(Config.BUILDS_ROOT), self.preview }
	self.groundParams = gp

	BindsHud.show(self.moveId and {
		{ "LMB", "Confirm" }, { "R", "Rotate" }, { "X", "Cancel" },
	} or {
		{ "LMB", "Place" }, { "R", "Rotate" }, { "1-8 / X", "Exit" },
	})
	self.stepConn  = RunService.PreRender:Connect(function(dt) self:_step(dt) end)
	self.inputConn = UserInputService.InputBegan:Connect(function(inp, gpe) self:_input(inp, gpe) end)
end

--[[
	main preview loop (every frame): ray under the cursor -> snap to grid -> check the spot ->
	smoothly pull the ghost toward the target and tilt it a bit
]]
function Placement:_step(dt: number): ()
	local ray = mouseRay()
	if not ray then return end -- no camera - just skip this frame
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 5000, self.groundParams)
	local gp  = hit and hit.Position or nil

	if gp then
		local sx, sz = GridUtil.snap(gp.X), GridUtil.snap(gp.Z)
		--[[
			the validity check is the heaviest thing here (raycasts + overlap),
			so we only recompute it when the grid cell or rotation actually changed
		]]
		if sx ~= self.cx or sz ~= self.cz or self.rot ~= self.crot then
			self.cx, self.cz, self.crot = sx, sz, self.rot
			self.gridX, self.gridZ = sx / Config.GRID, sz / Config.GRID
			self.lastTarget = Grounding.solveFrom(self.metrics, sx, sz, self.rot * Config.ROT_STEP, self.params, gp.Y)
			self.valid = Validator.isValid(self.lastTarget * self.relBBox, self.hbSize, self.ignoreModel)
			self:_setColor(self.valid and Config.COL_OK or Config.COL_BAD)
		end
	end

	-- moved the cursor into the sky and the ray hit nothing - stay on the last target, no jump
	local target = self.lastTarget or self.current
	if not target then return end
	if not self.current then self.current = target end
	self.current = self.current:Lerp(target, 1 - math.exp(-Config.MOVE_RESPONSE * dt))

	--[[
		a light "inertia" tilt: take the ghost's own speed and lean it toward the movement.
		standing still - almost no tilt, moving fast - more. purely visual, doesn't affect placement
	]]
	local cvel = (self.current.Position - (self.prevCurrent or self.current.Position)) / math.max(dt, 1 / 240)
	self.prevCurrent = self.current.Position
	self.smoothVel = self.smoothVel:Lerp(cvel, 1 - math.exp(-Config.TILT_SMOOTH * dt))
	local tiltX = math.clamp(self.smoothVel.Z * Config.TILT_FACTOR, -Config.TILT_MAX, Config.TILT_MAX)
	local tiltZ = math.clamp(-self.smoothVel.X * Config.TILT_FACTOR, -Config.TILT_MAX, Config.TILT_MAX)

	-- the tilt goes on top, but we keep the rotation the player picked
	local rotOnly   = self.current - self.current.Position
	local displayCF = CFrame.new(self.current.Position) * CFrame.Angles(tiltX, 0, tiltZ) * rotOnly
	self.preview:PivotTo(displayCF)
	self.hitbox.CFrame = displayCF * self.relBBox
end

-- input while placing: R - rotate, X - cancel, LMB - place/confirm
function Placement:_input(inp: InputObject, gpe: boolean): ()
	if gpe then return end
	if inp.KeyCode == Enum.KeyCode.R then
		self.rot = (self.rot + 1) % 4
	elseif inp.KeyCode == Enum.KeyCode.X then
		self:stop()
	elseif inp.UserInputType == Enum.UserInputType.MouseButton1 then
		-- if this click was part of a camera rotation, or the spot is red - ignore it
		if cameraDragging() or not self.valid then return end
		if self.moveId then
			-- confirm relocating the existing one
			remotes.MoveObject:FireServer(self.moveId, self.gridX, self.gridZ, self.rot)
			self:stop()
		else
			-- place a new one and DON'T close the preview - handy to spam several in a row
			remotes.PlaceObject:FireServer(self.category, self.name, self.gridX, self.gridZ, self.rot)
		end
	end
end

--[[
	wind down placement: drop the connections, delete the preview and restore the original's visibility.
	called both on confirm and on cancel - so we clean everything up carefully through if's
]]
function Placement:stop(): ()
	if self.stepConn then self.stepConn:Disconnect(); self.stepConn = nil end
	if self.inputConn then self.inputConn:Disconnect(); self.inputConn = nil end
	if self.preview then self.preview:Destroy(); self.preview = nil end
	if self.moveModel then setLocalHidden(self.moveModel, false); self.moveModel = nil end
	if self.active then BindsHud.hide() end
	self.active = false; self.slot = nil
end

--[[
	Edit - two modes on top of already-placed builds:
	move (grab and relocate via Placement) and delete (remove it)
]]
local Edit = {}
Edit.__index = Edit

-- keep a reference to Placement so we can switch it off when entering a mode
function Edit.new(placement)
	return setmetatable({ mode = nil, placement = placement }, Edit)
end

--[[
	create the hover highlight lazily - only the first time we enter a mode.
	no point keeping a Highlight in memory just in case
]]
function Edit:_ensureHL(): ()
	if self.hl then return end
	local hl = Instance.new("Highlight")
	hl.FillTransparency = 0.55; hl.OutlineColor = Color3.fromRGB(230, 230, 255)
	hl.Enabled = false; hl.Parent = workspace
	self.hl = hl
end

-- highlight the build under the cursor in the mode's color: red - delete, blue - move
function Edit:_hover(): ()
	local m = self.mode and modelUnderMouse() or nil
	if self.hl then
		self.hl.Adornee  = m
		self.hl.Enabled  = m ~= nil
		self.hl.FillColor = (self.mode == "delete") and Config.COL_BAD or MOVE_BLUE
	end
end

--[[
	turn a mode on/off. tap the same one again - turns it off (toggle).
	placing and editing don't work together, so entering a mode kills Placement
]]
function Edit:setMode(mode: string?): ()
	if self.mode == mode then mode = nil end
	self.mode = mode
	Toolbar.setActive(mode)
	if mode and self.placement.active then self.placement:stop() end

	if mode then
		self:_ensureHL()
		-- only hook the connections if they aren't there yet - otherwise re-entering would stack duplicates
		if not self.stepConn then self.stepConn = RunService.PreRender:Connect(function() self:_hover() end) end
		if not self.inputConn then self.inputConn = UserInputService.InputBegan:Connect(function(inp, gpe) self:_input(inp, gpe) end) end
		BindsHud.show(mode == "delete" and {
			{ "LMB", "Delete" }, { "T", "Exit mode" },
		} or {
			{ "LMB", "Pick & move" }, { "E", "Exit mode" },
		})
	else
		-- left the mode - drop the connections, kill the highlight and hide the hints
		if self.stepConn then self.stepConn:Disconnect(); self.stepConn = nil end
		if self.inputConn then self.inputConn:Disconnect(); self.inputConn = nil end
		if self.hl then self.hl.Enabled = false; self.hl.Adornee = nil end
		BindsHud.hide()
	end
end

-- click in a mode: on the build under the cursor either delete it or grab it to move
function Edit:_input(inp: InputObject, gpe: boolean): ()
	if gpe then return end
	if inp.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	-- camera rotation - skip
	if cameraDragging() then return end
	local m = modelUnderMouse()
	if not m then return end
	if self.mode == "delete" then
		remotes.DeleteObject:FireServer(m:GetAttribute("BuildId"))
	elseif self.mode == "move" then
		--[[
			hand the object back to Placement with its id and rotation -
			from there it behaves like a normal preview, and LMB will send MoveObject
		]]
		local ctx = { buildId = m:GetAttribute("BuildId"), rot = m:GetAttribute("Rot"), model = m }
		local cat, name = m:GetAttribute("Category"), m:GetAttribute("ItemName")
		self:setMode(nil)
		self.placement:begin(cat, name, nil, ctx)
	end
end

-- spin up Placement and Edit; the toolbar buttons just call setMode
local placement = Placement.new()
local edit      = Edit.new(placement)
Toolbar.onMode  = function(mode) edit:setMode(mode) end

--[[
	the hotbar sent a slot number. same slot again - turn placement off (toggle).
	otherwise, if we were in an edit mode, leave it and start the preview
]]
remotes.StartPlacement.Event:Connect(function(category: string, name: string, slot: number)
	if placement.active and not placement.moveId and placement.slot == slot then
		placement:stop()
		return
	end
	if edit.mode then edit:setMode(nil) end
	placement:begin(category, name, slot)
end)

-- edit-mode binds: E - move, T - delete
UserInputService.InputBegan:Connect(function(inp: InputObject, gpe: boolean)
	if gpe then return end
	if inp.KeyCode == KEY_MOVE then edit:setMode("move")
	elseif inp.KeyCode == KEY_DELETE then edit:setMode("delete") end
end)
