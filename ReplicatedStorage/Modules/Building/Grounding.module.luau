local Config = require(script.Parent.Parent.Config).Build
local Grounding = {}

local cachedParams

local function params()
	if not cachedParams then
		local p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Include
		local bm = workspace:FindFirstChild("Build Model")
		p.FilterDescendantsInstances = bm and {bm} or {}
		cachedParams = p
	end
	return cachedParams
end

function Grounding.surfaceParams()
	return params()
end

function Grounding.grassTopAt(x, z, p)
	local hit = workspace:Raycast(Vector3.new(x, 1000, z), Vector3.new(0, -Config.RAY_LEN, 0), p)
	if hit and hit.Instance.Name == Config.SURFACE then
		return hit.Position.Y
	end
	return nil
end

function Grounding.prepare(template)
	local pivot = template:GetPivot()
	local bcf, bsize = template:GetBoundingBox()
	return {
		deltaToBottom = pivot.Position.Y - (bcf.Position.Y - bsize.Y/2),
		rotOnly = pivot.Rotation,
	}
end

function Grounding.solveFrom(metrics, x, z, yaw, p, fallbackY)
	local grassY = Grounding.grassTopAt(x, z, p)
	local groundY = grassY or fallbackY or 0
	local cf = CFrame.new(x, groundY + metrics.deltaToBottom, z) * CFrame.Angles(0, yaw, 0) * metrics.rotOnly
	return cf, (grassY ~= nil)
end

function Grounding.solve(template, x, z, yaw, p, fallbackY)
	return Grounding.solveFrom(Grounding.prepare(template), x, z, yaw, p, fallbackY)
end

return Grounding
