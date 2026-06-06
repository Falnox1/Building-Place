local CollectionService = game:GetService("CollectionService")
local Config = require(script.Parent.Parent.Config).Build
local Grounding = require(script.Parent.Grounding)
local PlacementValidator = {}

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function grassUnder(point, p)
	local hit = workspace:Raycast(point + Vector3.new(0, 6, 0), Vector3.new(0, -Config.RAY_LEN, 0), p)
	return hit ~= nil and hit.Instance.Name == Config.SURFACE
end

function PlacementValidator.isValid(hitboxCFrame, size, ignoreModel)
	local p = Grounding.surfaceParams()
	local hx, hz = size.X/2 - 0.1, size.Z/2 - 0.1
	if not grassUnder(hitboxCFrame.Position, p) then return false end
	if not grassUnder(hitboxCFrame * Vector3.new( hx, 0,  hz), p) then return false end
	if not grassUnder(hitboxCFrame * Vector3.new(-hx, 0,  hz), p) then return false end
	if not grassUnder(hitboxCFrame * Vector3.new( hx, 0, -hz), p) then return false end
	if not grassUnder(hitboxCFrame * Vector3.new(-hx, 0, -hz), p) then return false end

	overlapParams.FilterDescendantsInstances = ignoreModel and {ignoreModel} or {}
	local parts = workspace:GetPartBoundsInBox(hitboxCFrame, size - Vector3.new(0.6, 0.6, 0.6), overlapParams)
	for _, part in parts do
		if CollectionService:HasTag(part, Config.HITBOX_TAG) then return false end
	end
	return true
end

return PlacementValidator
