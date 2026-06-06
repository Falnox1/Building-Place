local Config = require(script.Parent.Parent.Config).Build
local GridUtil = {}

function GridUtil.snap(n)
	return math.round(n / Config.GRID) * Config.GRID
end

return GridUtil
