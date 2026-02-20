-- ServerScriptService/WorldGeneneration/Main.server.lua

local generateTerrain = script.Parent:WaitForChild("GenerateTerrain")
local spawnTrees = script.Parent:WaitForChild("SpawnTrees")
local spawnCaves = script.Parent:WaitForChild("SpawnCaves")
local spawnCaveSkeletons = script.Parent:WaitForChild("SpawnCaveSkeletons")
local setupEnvironment = script.Parent:WaitForChild("SetupEnvironment")

generateTerrain.Disabled = false
task.wait()

--setupEnvironment.Disabled = false
task.wait()


spawnTrees.Disabled = false
task.wait()

spawnCaves.Disabled = false
task.wait()

spawnCaveSkeletons.Disabled = false