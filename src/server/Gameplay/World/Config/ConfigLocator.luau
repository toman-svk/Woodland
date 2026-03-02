--!strict
-- src/server/Gameplay/World/Config/ConfigLocator.luau
-- Centralized resolver for WorldConfig and WorldHeight.
-- Prevents "unsupported path require" errors in strict mode.

local ConfigLocator = {}

-- Find the Config folder relative to this file.
-- Structure:
-- Gameplay/
--   World/
--     Config/
--       WorldConfig
--       WorldHeight
--       ConfigLocator (this file)
local configFolder = script.Parent

-- Validate structure once
if not configFolder:FindFirstChild("WorldConfig") then
	error("[ConfigLocator] WorldConfig not found under " .. configFolder:GetFullName())
end

if not configFolder:FindFirstChild("WorldHeight") then
	error("[ConfigLocator] WorldHeight not found under " .. configFolder:GetFullName())
end

local WorldConfig = require(script.Parent.WorldConfig)
local WorldHeight = require(script.Parent.WorldHeight)

ConfigLocator.WorldConfig = WorldConfig
ConfigLocator.WorldHeight = WorldHeight

return ConfigLocator