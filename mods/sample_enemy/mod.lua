-- mods/sample_enemy/mod.lua
return {
    name = "Sample Fast Enemy",
    version = "1.2.0",
    description = "Adds a new fast-moving enemy type with custom behaviors (Multiplayer Compatible)",
    author = "Mod Author",
    dependencies = {},  -- Can specify other mods this depends on
    requiresSync = true,  -- This mod must be present on all clients
    main = "main.lua"   -- Main entry point
}
