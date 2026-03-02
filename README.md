# Woodland

Roblox game project built with Rojo. This README explains how the project is structured, how the main files are connected, and how the world generation/runtime modules are intended to work.

## Overview

The repo is split into three main Rojo-mapped code areas:

- `src/client` -> `StarterPlayer/StarterPlayerScripts/Client`
- `src/server` -> `ServerScriptService/Server`
- `src/shared` -> `ReplicatedStorage/Shared`

The most developed subsystem in this repo is the procedural world generation pipeline under:

- `src/server/Gameplay/World/Generation`
- `src/server/Gameplay/World/Config`
- `src/server/Gameplay/World/Runtime`

## Rojo Mapping (How code gets into Studio)

```mermaid
flowchart TD
    DP["default.project.json"] --> RS["ReplicatedStorage/Shared\n<- src/shared"]
    DP --> SSS["ServerScriptService/Server\n<- src/server"]
    DP --> SPS["StarterPlayer/StarterPlayerScripts/Client\n<- src/client"]

    SSS --> Gameplay["Gameplay/*"]
    SSS --> Lobby["Lobby/*"]
    SPS --> ClientScripts["Client scripts (*.client.luau)"]
```

## Project Structure (High-Level)

### Server

- `src/server/Gameplay`
  - Gameplay systems (inventory, spells, sprint, pickups, time, NPCs)
  - World generation/runtime modules
  - Persistence placeholders and helpers
- `src/server/Lobby`
  - Lobby scripts/services (currently minimal / placeholder)

### Shared

- `src/shared/Remotes/*`
  - Remote event/function containers used by client/server features
- `src/shared/GameConfig.luau`
  - Shared config values

### Client

- `src/client/*.client.luau`
  - Feature scripts for combat, dialogue, hotbar, sprint, audio, UI, etc.

## World System (Current Architecture)

The world subsystem is split into:

- `Config`: tunables and terrain height function
- `Generation`: procedural spawn/build steps
- `Runtime`: world IDs, world instance object, world service API
- `Persistence`: intended save/load modules (currently partly placeholder)

### World Module Dependency Graph

```mermaid
flowchart TD
    WS["World/Runtime/WorldService.luau"] --> WP["WorldPersistence (expected module)\nNOT in repo at this path"]
    WS --> WGM["WorldGenerationModules folder (expected)\nNOT in repo at this path"]
    WGM --> SC["SpawnCaves"]
    WGM --> SG["SpawnGems"]
    WGM --> ST["SpawnTrees"]

    WG["World/Generation/WorldGenerator.luau"] --> TG["TerrainGenerator.luau"]
    WG --> SHR["SpawnHubRuntime.luau"]
    WG --> SC2["SpawnCaves.luau"]
    WG --> SG2["SpawnGems.luau"]
    WG --> ST2["SpawnTrees.luau"]
    WG --> SCS["SpawnCaveSkeletons.luau"]

    TG --> CL["ConfigLocator.luau"]
    SC2 --> CL
    SG2 --> CL
    ST2 --> CL
    SCS --> CL

    CL --> WC["WorldConfig.luau"]
    CL --> WH["WorldHeight.luau"]
    WH --> WC
```

## World Generation Pipeline (Implemented in `WorldGenerator`)

`src/server/Gameplay/World/Generation/WorldGenerator.luau` is an orchestrator that runs world generation modules in deterministic order using a shared `rng` and `save`.

### Generation Order Flowchart

```mermaid
flowchart TD
    A["WorldGenerator.Build(root, origin, rng, save)"] --> B["Ensure folders exist:\nCaves, Gems, Trees, Enemies"]
    B --> C{"save.seed exists?"}
    C -- "No" --> D["Generate seed and write into save"]
    C -- "Yes" --> E["Keep existing seed"]
    D --> E
    E --> F["1. TerrainGenerator.Build"]
    F --> G["2. SpawnHubRuntime.Build"]
    G --> H["3. SpawnCaves.Build"]
    H --> I["4. SpawnGems.Build\n(depends on caves)"]
    I --> J["5. SpawnTrees.Build"]
    J --> K["6. SpawnCaveSkeletons.Build\n(depends on caves)"]
    K --> L["Return BuildResult counts"]
```

### What each generation file does

- `TerrainGenerator.luau`
  - Fills Roblox terrain water/ocean + land + beach
  - Uses `WorldHeight.heightAt(...)`
  - Flattens spawn-hub area around configured center/radius
- `SpawnHubRuntime.luau`
  - Clones static hub objects from `ServerStorage/Templates/SpawnHubTemplate`
  - Offsets them by world `origin`
- `SpawnCaves.luau`
  - Places cave models on terrain using config spacing/jitter/chance
  - Avoids spawn hub area and world edge margin
- `SpawnGems.luau`
  - Spawns crystals around caves in rings
  - Uses overlap checks to prevent collisions with existing objects
- `SpawnTrees.luau`
  - Dense forest generation with weighted templates and clustering
  - Avoids spawn area, steep slopes, and rocky heights
- `SpawnCaveSkeletons.luau`
  - Spawns enemies around caves
  - Uses terrain height and unanchors humanoid rigs

## Runtime World Objects (Planned / Partially Wired)

### `WorldIds.luau`

Utility module for world identifiers:

- `solo_<userId>` for player-owned worlds
- `world_<GUID>` for general/shared worlds
- parsing + validation helpers

### `WorldInstance.luau`

Defines a runtime object shape for a world:

- `WorldId`, `OwnerUserId`
- `Root`, `Generated`, `Origin`
- `Save`, `Seed`
- `Dirty`, `CreatedAt`

This is a good abstraction for a future `WorldService`, but the current `WorldService` file does not use it yet.

### `WorldService.luau` (Current state)

`src/server/Gameplay/World/Runtime/WorldService.luau` currently implements a per-player world service that:

- creates `workspace.Worlds`
- creates `ReplicatedStorage.Shared.ResetWorld` remote if missing
- tracks in-memory `saves`, `dirty`, and `roots`
- builds a world per player using `SpawnCaves`, `SpawnGems`, `SpawnTrees`
- teleports player to their world origin
- autosaves dirty worlds every 30s

However, it references modules/folders that do not exist at the paths used in the file:

- `script.Parent.WorldPersistence`
- `script.Parent.Parent.WorldGenerationModules`

So this runtime service looks like a legacy or in-progress version that has not yet been updated to the newer `World/Generation/*` layout.

## Player World Lifecycle (as implemented in current `WorldService`)

```mermaid
flowchart TD
    A["LoadPlayer(player)"] --> B["WorldPersistence.Load(userId)"]
    B --> C["Cache save in memory"]
    C --> D["BuildWorldForPlayer(player)"]
    D --> E["Create/replace workspace.Worlds/<userId>"]
    E --> F["Create root/Generated folder"]
    F --> G["SpawnCaves -> SpawnGems -> SpawnTrees"]
    G --> H["Teleport player to origin"]

    I["Gameplay systems modify save/diffs"] --> J["WorldService.MarkDirty(userId)"]
    J --> K["Autosave loop every 30s"]
    K --> L["WorldPersistence.Save(userId, save)"]

    M["UnloadPlayer(player)"] --> N["Save immediately"]
    N --> O["Destroy world folder + clear caches"]

    P["ResetPlayerWorld(player)"] --> Q["WorldPersistence.Reset(userId)"]
    Q --> R["Rebuild world from reset save"]
```

## Configuration Flow (`WorldConfig` + `WorldHeight`)

`src/server/Gameplay/World/Config/WorldConfig.luau` stores generation constants (sizes, radii, heights, spawn clear zones, cave/tree tuning, etc).

`src/server/Gameplay/World/Config/WorldHeight.luau` computes terrain height using:

- noise layers (`math.noise`)
- deterministic mountain centers (based on a seed stored in `workspace` attribute `WorldSeed`)
- mountain boost added on top of base noise terrain

Important note:

- `WorldHeight` currently uses a workspace-level seed (`workspace.WorldSeed`)
- `WorldGenerator` and runtime save data also contain `save.seed`
- those are not fully unified yet, so per-world deterministic terrain may need refactoring if multiple worlds are generated in one server

## Assets / Templates Required in Studio

Several generation modules expect templates to exist in `ServerStorage`:

- `ServerStorage/Templates/SpawnHubTemplate` (Folder)
- `ServerStorage/Templates/Caves/Cave` (Model)
- `ServerStorage/Templates/Gems/Crystal` (Model)
- `ServerStorage/Templates/Trees/Tree1..Tree4` (Models)
- `ServerStorage/Templates/Characters/Skeleton` (Model)

If these are missing, world generation modules will error.

## Current Gaps / In-Progress Areas

These files are present but are placeholders or not yet connected:

- `src/server/Gameplay/Persistence/WorldStore.luau`
- `src/server/Gameplay/Persistence/Schema.luau`
- `src/server/Gameplay/World/Content/Tags.luau`
- `src/server/Gameplay/World/Content/AssetIds.luau`
- `src/server/Lobby/LobbyBootstrap.server.luau`

Also, `src/server/Gameplay/GameplayBootstrap.server.luau` currently contains a blacksmith animation proximity script rather than a true gameplay bootstrap orchestrator.

## Recommended Wiring Direction (next step)

To align the repo with the newer module structure:

1. Update `WorldService` to require `WorldGenerator`, `WorldInstance`, `WorldIds`, and persistence modules from current paths.
2. Implement `WorldStore` + `Schema` (versioned save format).
3. Add an actual gameplay bootstrap script that:
   - requires `WorldService`
   - connects `Players.PlayerAdded/PlayerRemoving`
   - routes reset remote events
4. Unify terrain seed usage (`WorldHeight`) with per-world `save.seed`.

## Getting Started (Rojo)

Build the place file:

```bash
rojo build -o "Woodland.rbxlx"
```

Or serve directly to Studio:

```bash
rojo serve
```

See [Rojo documentation](https://rojo.space/docs) for workflow details.

