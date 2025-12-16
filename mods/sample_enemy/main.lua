-- mods/sample_enemy/main.lua
-- Main entry point for the mod (Multiplayer Compatible)

return function(ModAPI, modPath)
    print("Loading Sample Fast Enemy mod...")

    -- Load enemy definition
    local enemy = require(modPath .. ".enemy")

    -- Register enemy with ModAPI
    ModAPI.registerEnemy(
        "sample_fast",
        enemy.enemy_class,
        enemy.enemy_data
    )

    -- Add server-side hook for enemy spawning
    ModAPI.addHook("enemy_spawned", function(enemyData)
        if enemyData.type == "sample_fast" then
            print("Server: Sample Fast Enemy spawned! ID:", enemyData.id)
            -- Server-side logic for this enemy type
        end
    end, 5, true)  -- Priority 5, server-side

    -- Add client-side hook for enemy death effects
    ModAPI.addHook("enemy_died", function(enemyData)
        if enemyData.type == "sample_fast" then
            print("Client: Sample Fast Enemy died! ID:", enemyData.id)
            -- Client-side effects for this enemy death
        end
    end, 5, false)  -- Priority 5, client-side

    print("Sample Fast Enemy mod loaded successfully!")
end
