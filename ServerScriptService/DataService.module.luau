local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config).Build

local sessions = {}
local DataService = {}

local store, available
do
	local ok, res = pcall(function() return DataStoreService:GetDataStore("Builds") end)
	store = ok and res or nil
	local probed = ok and pcall(function() return store:GetAsync("__probe__") end)
	available = ok and probed
	if not available then
		warn("[DataService] DataStore unavailable (place not published / API access off). Running in-memory; saves won't persist.")
	end
end

local function retry(fn)
	for attempt = 1, 3 do
		local ok, res = pcall(fn)
		if ok then return true, res end
		warn(`[DataService] attempt {attempt} failed: {res}`)
		task.wait(attempt)
	end
	return false
end

function DataService.load(userId)
	local d
	if available then
		local ok, data = retry(function() return store:GetAsync(`{Config.DATA_KEY}{userId}`) end)
		if ok and type(data) == "table" then d = data end
	end
	if type(d) ~= "table" then d = { v = 1, b = {} } end
	d.b = d.b or {}
	sessions[userId] = { data = d, dirty = false, loaded = true }
	return d
end

function DataService.get(userId)
	local s = sessions[userId]
	return s and s.data or nil
end

function DataService.markDirty(userId)
	local s = sessions[userId]
	if s then s.dirty = true end
end

function DataService.save(userId, force)
	local s = sessions[userId]
	if not s or not s.loaded then return false end
	if not s.dirty and not force then return true end
	if not available then s.dirty = false; return false end
	local ok = retry(function()
		store:UpdateAsync(`{Config.DATA_KEY}{userId}`, function() return s.data end)
	end)
	if ok then s.dirty = false end
	return ok
end

function DataService.release(userId)
	DataService.save(userId, true)
	sessions[userId] = nil
end

task.spawn(function()
	while true do
		task.wait(Config.AUTOSAVE_INTERVAL)
		for uid, s in sessions do
			if s.dirty then DataService.save(uid) end
		end
	end
end)

game:BindToClose(function()
	for uid in sessions do
		task.spawn(DataService.save, uid, true)
	end
	task.wait(2)
end)

return DataService
