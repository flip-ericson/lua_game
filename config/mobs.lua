-- config/mobs.lua
-- Mob definitions. One table per mob type.
-- Fields:
--   name          → display name
--   hp            → base hit points
--   speed         → world-px / s (used in Step 2+)
--   sprite        → path to placeholder PNG (single static frame for now)
--   ai_type       → "passive" | "neutral" | "hostile"
--   detect_radius → hex distance that triggers AI reaction
--   drops         → { { item="item_name", count=N, chance=0..1 }, ... }

return {
    turkey = {
        name               = "turkey",
        hp                 = 8,
        speed              = 80,
        sprite             = "assests/entities/entity_turkey_static.png",
        ai_type            = "passive",
        -- Flee behavior
        -- wander speed = speed (80 px/s = 1/3 of run speed)
        -- run speed    = speed × flee_speed_mul = 240 px/s = 1.2× player (200 px/s)
        sense_radius       = 3,    -- small radius; turkeys aren't known for their senses
        awareness_interval = 2.0,  -- check every 2 s; prey but not particularly skittish
        flee_speed_mul     = 3.0,  -- 80 × 3 = 240 px/s (just faster than the player)
        shyness            = 4,    -- wants ~4 tiles of breathing room
        drops              = {},
    },

    orc = {
        name          = "orc",
        hp            = 30,
        speed         = 120,
        sprite        = "assests/entities/entity_turkey_static.png",  -- placeholder
        ai_type       = "hostile",
        detect_radius = 8,
        attack_damage = 5,
        attack_cooldown = 1.5,
        drops         = {},
    },

    wizard = {
        name          = "wizard",
        hp            = 20,
        speed         = 100,
        sprite        = "assests/entities/entity_turkey_static.png",  -- placeholder
        ai_type       = "neutral",
        detect_radius = 6,
        attack_damage = 8,
        attack_cooldown = 2.0,
        drops         = {},
    },
}
