local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")

local localPlayer = Players.LocalPlayer

local Settings = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"))
local Config = Settings.Inventory
local COLORS = Settings.Palette

local SLOT_COUNT = Config.SLOT_COUNT
local GHOST_HALF = Config.GHOST_HALF
local PANEL_OPEN_Y = Config.PANEL_OPEN_Y
local TOGGLE_KEYS = Config.TOGGLE_KEYS
local HOTBAR_KEYS = Config.HOTBAR_KEYS

type Item = { name: string, model: Instance }
type Category = { name: string, items: { Item } }

pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false) end)

local function tween(object: Instance, props: { [string]: any }, duration: number?, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local info = TweenInfo.new(duration or 0.22, style or Enum.EasingStyle.Quart, direction or Enum.EasingDirection.Out)
	local playing = TweenService:Create(object, info, props)
	playing:Play()
	return playing
end

local function getPointer(): Vector2
	return UserInputService:GetMouseLocation()
end

local function toGuiOffset(position: Vector2): Vector2
	local inset = GuiService:GetGuiInset()
	return Vector2.new(position.X - inset.X, position.Y - inset.Y)
end

local playerGui = localPlayer:WaitForChild("PlayerGui")
local template = StarterGui:WaitForChild("ScreenGui")
local existing = playerGui:FindFirstChild("ScreenGui")
if existing then existing:Destroy() end
local screenGui = template:Clone()
screenGui.Parent = playerGui

local hud          = screenGui:WaitForChild("HUD")
local panel        = screenGui:WaitForChild("InvPanel")
local tabsScroll   = panel:WaitForChild("TabsScroll")
local itemsArea    = panel:WaitForChild("ItemsArea")
local closeButton  = panel.TitleBar:WaitForChild("CloseBtn")
local invButton    = hud:WaitForChild("InvBtn")
local ghost        = screenGui:WaitForChild("DragGhost")
local ghostLabel   = ghost:WaitForChild("GhostLbl")
local tileTemplate = itemsArea:WaitForChild("TileTemplate")
local tabTemplate  = tabsScroll:WaitForChild("TabTemplate")

local slots = {}
for i = 1, SLOT_COUNT do
	slots[i] = hud:WaitForChild(`Slot{i}`)
end

local slotIndexByButton = {}
for i = 1, SLOT_COUNT do
	slotIndexByButton[slots[i]] = i
end

local State = {
	isOpen = false,
	currentCategory = nil :: string?,
	hotbar = {} :: { [number]: Item },
	categories = {} :: { Category },
	tabs = {} :: { [string]: { button: TextButton, label: TextLabel } },
}

local StartPlacement = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StartPlacement")

local function loadData()
	local inventory = ReplicatedStorage:WaitForChild("Inventory")
	for _, folder in inventory:GetChildren() do
		if not folder:IsA("Folder") then continue end
		local items = {}
		for _, model in folder:GetChildren() do
			if model:IsA("Model") then
				table.insert(items, { name = model.Name, model = model })
			end
		end
		if #items > 0 then
			table.insert(State.categories, { name = folder.Name, items = items })
		end
	end
	table.sort(State.categories, function(a, b) return a.name < b.name end)
	if #State.categories > 0 then
		State.currentCategory = State.categories[1].name
	end
end

local function isInHotbar(itemName: string): boolean
	for _, item in State.hotbar do
		if item and item.name == itemName then return true end
	end
	return false
end

local Hud = {}

function Hud.fill(index: number, item: Item)
	local slot = slots[index]
	slot.Lbl.Text = item.name
	slot.Visible = true
	slot.BackgroundColor3 = COLORS.SlotFill
	tween(slot, { BackgroundTransparency = 0.1 }, 0.15)
	tween(slot, { BackgroundColor3 = COLORS.Ok }, 0.08).Completed:Once(function()
		tween(slot, { BackgroundColor3 = COLORS.SlotFill }, 0.28)
	end)
end

function Hud.showEmpties()
	for i = 1, SLOT_COUNT do
		if State.hotbar[i] then continue end
		task.delay(i * 0.04, function()
			local slot = slots[i]
			slot.Visible = true
			slot.BackgroundTransparency = 1
			tween(slot, { BackgroundTransparency = 0.15 }, 0.18)
		end)
	end
end

function Hud.hideEmpties()
	for i = 1, SLOT_COUNT do
		if State.hotbar[i] then continue end
		task.delay(i * 0.02, function()
			tween(slots[i], { BackgroundTransparency = 1 }, 0.14).Completed:Once(function()
				if not State.isOpen and not State.hotbar[i] then slots[i].Visible = false end
			end)
		end)
	end
end

local Inv = {}
local Drag

local function findCategory(name: string?): Category?
	for _, category in State.categories do
		if category.name == name then return category end
	end
	return nil
end

function Inv.renderItems(categoryName: string)
	State.currentCategory = categoryName
	for _, child in itemsArea:GetChildren() do
		if child:IsA("ImageButton") and child ~= tileTemplate then child:Destroy() end
	end
	itemsArea.CanvasPosition = Vector2.zero

	for name, tab in State.tabs do
		local active = name == categoryName
		tween(tab.button, { BackgroundColor3 = if active then COLORS.TabOn else COLORS.TabOff }, 0.14)
		tab.label.TextColor3 = if active then Color3.new(1, 1, 1) else COLORS.Dim
		tab.label.Font = if active then Enum.Font.GothamBold else Enum.Font.Gotham
	end

	local category = findCategory(categoryName)
	if not category then return end

	for index, item in category.items do
		local tile = tileTemplate:Clone()
		tile.Name = item.name
		tile.LayoutOrder = index
		tile.Visible = true
		tile.BackgroundTransparency = 1
		tile.Lbl.Text = item.name
		tile.Dot.Visible = isInHotbar(item.name)
		tile.MouseEnter:Connect(function() tween(tile, { BackgroundColor3 = COLORS.ItemHover, BackgroundTransparency = 0.1 }, 0.1) end)
		tile.MouseLeave:Connect(function() tween(tile, { BackgroundColor3 = COLORS.ItemBg, BackgroundTransparency = 0.25 }, 0.1) end)
		tile.MouseButton1Down:Connect(function() Drag.start(item) end)
		tile.Parent = itemsArea
		task.delay(index * 0.03, function()
			if tile.Parent then tween(tile, { BackgroundTransparency = 0.25 }, 0.12) end
		end)
	end
end

function Inv.buildTabs()
	for _, category in State.categories do
		local button = tabTemplate:Clone()
		button.Name = category.name
		button.Visible = true
		button.Lbl.Text = category.name
		State.tabs[category.name] = { button = button, label = button.Lbl }
		button.MouseButton1Click:Connect(function() Inv.renderItems(category.name) end)
		button.MouseEnter:Connect(function()
			if State.currentCategory ~= category.name then tween(button, { BackgroundTransparency = 0.1 }, 0.08) end
		end)
		button.MouseLeave:Connect(function()
			if State.currentCategory ~= category.name then tween(button, { BackgroundTransparency = 0.25 }, 0.08) end
		end)
		button.Parent = tabsScroll
	end
end

function Inv.open()
	if State.isOpen then return end
	State.isOpen = true
	panel.Visible = true
	panel.Position = UDim2.new(0.5, 0, 1, 20)
	tween(panel, { Position = UDim2.new(0.5, 0, 1, PANEL_OPEN_Y) }, 0.32, Enum.EasingStyle.Back)
	tween(invButton, { BackgroundColor3 = Color3.fromRGB(40, 82, 150) }, 0.15)
	Hud.showEmpties()
end

function Inv.close()
	if not State.isOpen then return end
	State.isOpen = false
	tween(panel, { Position = UDim2.new(0.5, 0, 1, 20) }, 0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In).Completed:Once(function()
		panel.Visible = false
	end)
	tween(invButton, { BackgroundColor3 = COLORS.InvBtn }, 0.15)
	Hud.hideEmpties()
end

function Inv.toggle()
	if State.isOpen then Inv.close() else Inv.open() end
end

Drag = { active = nil :: Item? }

local function moveGhost()
	local offset = toGuiOffset(getPointer())
	ghost.Position = UDim2.fromOffset(offset.X - GHOST_HALF, offset.Y - GHOST_HALF)
end

local function slotUnderPointer(): number?
	local pointer = getPointer()
	local inset = GuiService:GetGuiInset()
	local hits = playerGui:GetGuiObjectsAtPosition(pointer.X - inset.X, pointer.Y - inset.Y)
	for _, object in hits do
		local current = object
		while current and current ~= screenGui do
			local index = slotIndexByButton[current]
			if index and slots[index].Visible then return index end
			current = current.Parent
		end
	end
	return nil
end

function Drag.start(item: Item)
	Drag.active = item
	ghostLabel.Text = item.name
	moveGhost()
	ghost.BackgroundTransparency = 0.25
	ghost.Visible = true
end

function Drag.finish()
	if not Drag.active then return end
	local item = Drag.active
	Drag.active = nil

	local index = slotUnderPointer()
	if index then
		State.hotbar[index] = { name = item.name, model = item.model }
		Hud.fill(index, item)
		Inv.renderItems(State.currentCategory)
	end
	tween(ghost, { BackgroundTransparency = 1 }, 0.12).Completed:Once(function()
		if not Drag.active then ghost.Visible = false end
	end)
end

UserInputService.InputChanged:Connect(function(input: InputObject)
	if Drag.active and input.UserInputType == Enum.UserInputType.MouseMovement then moveGhost() end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then Drag.finish() end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	for _, key in TOGGLE_KEYS do
		if input.KeyCode == key then Inv.toggle() return end
	end
	local index = HOTBAR_KEYS[input.KeyCode]
	if not index or State.isOpen then return end
	local item = State.hotbar[index]
	if item then StartPlacement:Fire(item.model.Parent.Name, item.name, index) end
end)

invButton.MouseButton1Click:Connect(Inv.toggle)
closeButton.MouseButton1Click:Connect(Inv.close)
invButton.MouseEnter:Connect(function() tween(invButton, { BackgroundTransparency = 0 }, 0.1) end)
invButton.MouseLeave:Connect(function() tween(invButton, { BackgroundTransparency = 0.15 }, 0.1) end)
closeButton.MouseEnter:Connect(function() tween(closeButton, { BackgroundTransparency = 0 }, 0.1) end)
closeButton.MouseLeave:Connect(function() tween(closeButton, { BackgroundTransparency = 0.2 }, 0.1) end)

loadData()
Inv.buildTabs()
if State.currentCategory then Inv.renderItems(State.currentCategory) end
