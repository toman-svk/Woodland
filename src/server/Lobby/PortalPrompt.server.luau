--!strict
-- Lobby: when player uses the portal prompt, open the WorldMenu UI

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local shared = ReplicatedStorage:WaitForChild("Shared")
local remotes = shared:WaitForChild("Remotes")
local lobbyUI = remotes:WaitForChild("LobbyUI") :: Folder
local openWorldMenu = lobbyUI:WaitForChild("OpenWorldMenu") :: RemoteEvent
local portal = Workspace:WaitForChild("Portal", 5) :: Instance

-- safeguard so it doesn't run outside of Lobby
local LOBBY_PLACE_ID = 131782889117139
if game.PlaceId ~= LOBBY_PLACE_ID then
	return
end

if not portal then
	warn("[PortalPrompt] Portal not found in Lobby.")
	return
end


-- Find the ProximityPrompt anywhere under Portal
local prompt = portal:FindFirstChildWhichIsA("ProximityPrompt", true)
if not prompt then
	warn("[PortalPrompt] No ProximityPrompt found under Workspace.Portal")
	return
end

-- Important: prompt MUST be under a BasePart or Attachment or it won't show.
do
	local parent = prompt.Parent
	if not parent then
		warn("[PortalPrompt] Prompt has no parent??")
		return
	end

	local okParent =
		parent:IsA("BasePart") or parent:IsA("Attachment")

	if not okParent then
		-- Try to auto-fix: move prompt under the first BasePart in the portal
		local part = portal:FindFirstChildWhichIsA("BasePart", true)
		if part then
			prompt.Parent = part
			print("[PortalPrompt] Moved ProximityPrompt under:", part:GetFullName())
		else
			warn("[PortalPrompt] Prompt is not under a BasePart/Attachment and no BasePart exists to move it to.")
		end
	end
end

prompt.Triggered:Connect(function(player)
	openWorldMenu:FireClient(player)
end)

print("[PortalPrompt] Ready.")