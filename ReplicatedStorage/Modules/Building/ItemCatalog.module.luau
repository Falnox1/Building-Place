local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(script.Parent.Parent.Config).Build
local ItemCatalog = {}

function ItemCatalog.getTemplate(category, name)
	local inv = ReplicatedStorage:FindFirstChild("Inventory")
	local folder = inv and inv:FindFirstChild(category)
	local m = folder and folder:FindFirstChild(name)
	if m and m:IsA("Model") then return m end
	return nil
end

function ItemCatalog.computeHitbox(model)
	local cf, size = model:GetBoundingBox()
	return cf, size + Vector3.new(Config.HITBOX_PAD, 0, Config.HITBOX_PAD)
end

return ItemCatalog
