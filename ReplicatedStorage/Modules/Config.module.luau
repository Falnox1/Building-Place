local Config = {}

Config.Build = {
	GRID = 4,
	ROT_STEP = math.pi / 2,
	SURFACE = "Grass",
	BUILDS_ROOT = "PlacedBuilds",
	HITBOX_TAG = "BuildHitbox",
	HITBOX_PAD = 0.4,
	HITBOX_TR = 0.4,
	COL_OK = Color3.fromRGB(70, 200, 90),
	COL_BAD = Color3.fromRGB(210, 60, 60),
	MOVE_RESPONSE = 11,
	TILT_FACTOR = 0.0009,
	TILT_MAX = math.rad(12),
	TILT_SMOOTH = 9,
	RAY_LEN = 2000,
	AUTOSAVE_INTERVAL = 60,
	DATA_KEY = "builds_v1_",
	KEY_MOVE = Enum.KeyCode.E,
	KEY_DELETE = Enum.KeyCode.T,
}

Config.Camera = {
	MOVE_SPEED = 80,
	BOOST_SPEED = 220,
	MOVE_ACCEL = 8,
	MIN_X = -500, MAX_X = 500,
	MIN_Z = -500, MAX_Z = 500,
	ZOOM_MIN = 20, ZOOM_MAX = 700, ZOOM_STEP = 14,
	ZOOM_RESPONSE = 10,
	PITCH_START = math.rad(63),
	PITCH_MIN = math.rad(15), PITCH_MAX = math.rad(88),
	PITCH_SENS = 0.005, YAW_SENS = 0.005,
	FOV_BASE = 70, FOV_BOOST = 12, FOV_RESPONSE = 6,
}

Config.Inventory = {
	SLOT_COUNT = 9,
	GHOST_HALF = 34,
	PANEL_OPEN_Y = -(12 + 64 + 8),
	TOGGLE_KEYS = { Enum.KeyCode.Backquote, Enum.KeyCode.Zero },
	HOTBAR_KEYS = {
		[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
		[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
		[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9,
	},
}

Config.Palette = {
	Blue = Color3.fromRGB(62, 118, 210),
	Off = Color3.fromRGB(40, 40, 60),
	SlotFill = Color3.fromRGB(35, 50, 72),
	TabOn = Color3.fromRGB(62, 118, 210),
	TabOff = Color3.fromRGB(32, 32, 50),
	ItemBg = Color3.fromRGB(38, 38, 58),
	ItemHover = Color3.fromRGB(55, 55, 78),
	InvBtn = Color3.fromRGB(62, 118, 210),
	Dim = Color3.fromRGB(120, 122, 148),
	Ok = Color3.fromRGB(72, 196, 104),
}

return Config
