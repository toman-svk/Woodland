-- ServerScriptService/WorldGeneneration/SetupEnvironment.server.lua

local Lighting = game:GetService("Lighting")
local InsertService = game:GetService("InsertService")

-- World size for fog distances
local WorldModules = script.Parent.Parent:WaitForChild("WorldModules")
local WorldConfig = require(WorldModules:WaitForChild("WorldConfig"))

local half = WorldConfig.AREA_SIZE / 2

-- ========================
-- SKYBOX (Option B)
-- ========================
-- Pick one (Creator Store assets):
-- 128155661 = Dark night skybox  (recommended)   [oai_citation:3‡create.roblox.com](https://create.roblox.com/store/asset/128155661/Dark-night-skybox?utm_source=chatgpt.com)
-- 741300412 = Night Skybox                          [oai_citation:4‡create.roblox.com](https://create.roblox.com/store/asset/741300412/Night-Skybox?utm_source=chatgpt.com)
-- 3451179493 = Starry night sky Skybox              [oai_citation:5‡create.roblox.com](https://create.roblox.com/store/asset/3451179493/Starry-night-sky-Skybox?utm_source=chatgpt.com)
local SKY_ASSET_ID = 128155661

local function ensureSky()
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		sky = Instance.new("Sky")
		sky.Parent = Lighting
	end
	return sky
end

local function applySkyboxFromAsset(assetId: number)
	local sky = ensureSky()

	local ok, assetModel = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)

	if not ok or not assetModel then
		warn("[Env] Failed to LoadAsset skybox id:", assetId, assetModel)
		return
	end

	local assetSky = assetModel:FindFirstChildOfClass("Sky") or assetModel:FindFirstChildWhichIsA("Sky", true)
	if not assetSky then
		warn("[Env] Asset loaded but no Sky found inside. id:", assetId)
		assetModel:Destroy()
		return
	end

	-- Copy textures
	sky.SkyboxBk = assetSky.SkyboxBk
	sky.SkyboxDn = assetSky.SkyboxDn
	sky.SkyboxFt = assetSky.SkyboxFt
	sky.SkyboxLf = assetSky.SkyboxLf
	sky.SkyboxRt = assetSky.SkyboxRt
	sky.SkyboxUp = assetSky.SkyboxUp

	-- Optional: keep stars, but reduce glare from sun/moon
	sky.CelestialBodiesShown = true
	sky.StarCount = 3000
	sky.SunAngularSize = 0
	sky.MoonAngularSize = 6

	assetModel:Destroy()
	print("[Env] Applied skybox from asset id:", assetId)
end

applySkyboxFromAsset(SKY_ASSET_ID)

-- ========================
-- NIGHT LIGHTING (a bit darker than before, still playable)
-- ========================
Lighting.ClockTime = 1.1
Lighting.Brightness = 3.0
Lighting.ExposureCompensation = 0.05
Lighting.ShadowSoftness = 0.75

Lighting.Ambient = Color3.fromRGB(32, 36, 52)
Lighting.OutdoorAmbient = Color3.fromRGB(55, 60, 85)

Lighting.EnvironmentDiffuseScale = 0.85
Lighting.EnvironmentSpecularScale = 0.85

-- ========================
-- FOG to hide baseplate outside generated area
-- ========================
-- Make fog start near the edge of your generated terrain.
-- With AREA_SIZE=600 => half=300, these hide outside fairly aggressively.
local FOG_START = math.clamp(half * 0.62, 140, 600)  -- ~186 for 600
local FOG_END   = math.clamp(half * 0.88, 220, 900)  -- ~264 for 600

Lighting.FogColor = Color3.fromRGB(95, 105, 135)
Lighting.FogStart = FOG_START
Lighting.FogEnd = FOG_END

-- ========================
-- ATMOSPHERE (supports fog feel, but keep horizon darker)
-- ========================
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if not atmosphere then
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Parent = Lighting
end

atmosphere.Color = Color3.fromRGB(175, 185, 210)
atmosphere.Decay = Color3.fromRGB(70, 80, 110)
atmosphere.Density = 0.22
atmosphere.Offset = -50000000    -- helps reduce bright horizon band
atmosphere.Haze = 0.8        -- lower haze = less “glowy horizon”
atmosphere.Glare = 0.00

-- ========================
-- POST FX (slightly moodier)
-- ========================
local cc = Lighting:FindFirstChild("MoonColorCorrection")
if not cc then
	cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "MoonColorCorrection"
	cc.Parent = Lighting
end

cc.Brightness = -0.03
cc.Contrast = 0.12
cc.Saturation = -0.06
cc.TintColor = Color3.fromRGB(205, 215, 255)

print(("[Env] AREA_SIZE=%d FogStart=%.1f FogEnd=%.1f"):format(WorldConfig.AREA_SIZE, Lighting.FogStart, Lighting.FogEnd))