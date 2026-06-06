local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService   = game:GetService("CollectionService")

local Config      = require(ReplicatedStorage.Modules.Config).Build
local ItemCatalog = require(ReplicatedStorage.Modules.Building.ItemCatalog)
local Grounding   = require(ReplicatedStorage.Modules.Building.Grounding)
local Validator   = require(ReplicatedStorage.Modules.Building.PlacementValidator)
local DataService = require(ServerScriptService.DataService)

local remotes = ReplicatedStorage.Remotes
local root = workspace:WaitForChild(Config.BUILDS_ROOT)

local nextId = 0
local registry = {}

local function makeHitbox(model)
	local cf, size = ItemCatalog.computeHitbox(model)
	local hb = Instance.new("Part")
	hb.Name = "Hitbox"; hb.Size = size; hb.CFrame = cf
	hb.Anchored = true; hb.CanCollide = false; hb.CanQuery = true
	hb.CanTouch = false; hb.Transparency = 1
	CollectionService:AddTag(hb, Config.HITBOX_TAG)
	hb.Parent = model
end

local function anchorAll(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then d.Anchored = true end
	end
end

local function serialize(userId)
	local d = DataService.get(userId)
	if not d then return end
	local list = {}
	for _, info in registry do
		local m = info.model
		table.insert(list, {
			c = m:GetAttribute("Category"), n = m:GetAttribute("ItemName"),
			x = m:GetAttribute("GX"), z = m:GetAttribute("GZ"), r = m:GetAttribute("Rot"),
		})
	end
	d.b = list
	DataService.markDirty(userId)
end

local function spawnBuild(category, name, gx, gz, rot, validate)
	local template = ItemCatalog.getTemplate(category, name)
	if not template then return nil end
	rot = rot % 4
	local model = template:Clone()
	model.Parent = root

	local cf = Grounding.solve(template, gx * Config.GRID, gz * Config.GRID, rot * Config.ROT_STEP, Grounding.surfaceParams(), 0)
	model:PivotTo(cf)

	if validate then
		local bcf, bsize = model:GetBoundingBox()
		if not Validator.isValid(bcf, bsize, model) then
			model:Destroy()
			return nil
		end
	end

	anchorAll(model)
	nextId += 1
	local id = nextId
	model:SetAttribute("BuildId", id)
	model:SetAttribute("Category", category)
	model:SetAttribute("ItemName", name)
	model:SetAttribute("Rot", rot)
	model:SetAttribute("GX", gx)
	model:SetAttribute("GZ", gz)
	makeHitbox(model)
	registry[id] = { model = model }
	return id
end

remotes.PlaceObject.OnServerEvent:Connect(function(player, category, name, gx, gz, rot)
	if type(category) ~= "string" or type(name) ~= "string" then return end
	if type(gx) ~= "number" or type(gz) ~= "number" or type(rot) ~= "number" then return end
	if spawnBuild(category, name, gx, gz, rot, true) then
		serialize(player.UserId)
	end
end)

remotes.MoveObject.OnServerEvent:Connect(function(player, buildId, gx, gz, rot)
	local info = registry[buildId]
	if not info then return end
	if type(gx) ~= "number" or type(gz) ~= "number" or type(rot) ~= "number" then return end
	rot = rot % 4
	local model = info.model
	local template = ItemCatalog.getTemplate(model:GetAttribute("Category"), model:GetAttribute("ItemName"))
	if not template then return end
	local oldPivot = model:GetPivot()
	local cf = Grounding.solve(template, gx * Config.GRID, gz * Config.GRID, rot * Config.ROT_STEP, Grounding.surfaceParams(), 0)
	model:PivotTo(cf)
	local bcf, bsize = model:GetBoundingBox()
	if not Validator.isValid(bcf, bsize, model) then
		model:PivotTo(oldPivot)
		return
	end
	model:SetAttribute("GX", gx)
	model:SetAttribute("GZ", gz)
	model:SetAttribute("Rot", rot)
	serialize(player.UserId)
end)

remotes.DeleteObject.OnServerEvent:Connect(function(player, buildId)
	local info = registry[buildId]
	if not info then return end
	info.model:Destroy()
	registry[buildId] = nil
	serialize(player.UserId)
end)

local function onPlayerAdded(player)
	local data = DataService.load(player.UserId)
	for _, e in data.b do
		spawnBuild(e.c, e.n, e.x, e.z, e.r or 0, false)
	end
end

local function onPlayerRemoving(player)
	for id, info in registry do
		info.model:Destroy()
		registry[id] = nil
	end
	DataService.release(player.UserId)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, p in Players:GetPlayers() do task.spawn(onPlayerAdded, p) end
