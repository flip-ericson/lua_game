# Dwarf Island V4 — Potential Items & Entities
#
# All checkboxes are intentionally UNCHECKED — even tiles that exist in code still
# need sprites, balanced stats, sound design, and full behaviour before they're "done".
#
# Notes
#   (impl) = tile ID exists in config/tiles.lua; code is in but visuals/behaviour unfinished
#   (idea) = not yet in code; design note follows the dash

# ─────────────────────────────────────────────────────────────────────────────
# BLOCKS — terrain
# ─────────────────────────────────────────────────────────────────────────────

- [X] Air           (impl) id 0  — absence tile; never rendered
- [ ] Bedrock       (impl) id 1  — indestructible floor, hardness=∞
- [ ] Grass         (impl) id 2  — topsoil surface; drops dirt_clod
- [ ] Dirt          (impl) id 3  — subsurface band 1–10 layers deep
- [ ] Sand          (impl) id 4  — beach and ocean floor surface
- [ ] Stone         (impl) id 5  — default subsurface fill below dirt
- [ ] Marble        (impl) id 6  — mid-depth horizontal ribbon bands
- [ ] Grimstone     (impl) id 7  — deep rock below per-column noise floor
- [ ] Loam          (idea) — rich dark soil variant; appears in humid lowland biomes; faster crop growth than dirt
- [ ] Gravel        (idea) — gravity-affected; falls into caves; found near riverbeds and cliff bases; drops flint
- [ ] Clay          (idea) — found in shallow ocean-floor and riverbed deposits; fired in kiln for bricks and pottery
- [ ] Sandstone     (idea) — compressed sand found below desert/beach surface; softer than stone; good early building block
- [ ] Limestone     (idea) — pale sedimentary rock; found in coastal and mid-depth zones; used in mortar and construction
- [ ] Granite       (idea) — hard igneous rock; found in deep hot zones near grimstone layer; speckled appearance
- [ ] Andesite      (idea) — dark volcanic rock; found near lava zones; harder than limestone; good decorative block
- [ ] Slate         (idea) — fine-grained dark rock; found in cool/rainy biomes; splits into flat tiles; good roofing material
- [ ] Soapstone     (idea) — soft grey-green stone; found near ocean-floor deposits; carved into bowls, pots, and decorations
- [ ] Mossy Stone   (idea) — stone variant near cave entrances and wet zones; purely aesthetic
- [ ] Ice           (idea) — forms on water surfaces in cold/high-elevation biomes; slippery movement modifier
- [ ] Snow          (idea) — thin surface cover layer in cold biomes; melts near lava/torches
- [ ] Packed Ice    (idea) — dense ice in cold biome depths; harder than regular ice; usable as building material
- [ ] Cobblestone   (idea) — dropped when mining stone without silk-touch; re-placeable rough block
- [ ] Obsidian      (idea) — created where lava meets salt water; extremely hard; used for high-tier crafting stations
- [ ] Bone Deposit  (idea) — rare deep fossil layer; yields bone fragments for tools and fertiliser

# ─────────────────────────────────────────────────────────────────────────────
# LIQUIDS
# ─────────────────────────────────────────────────────────────────────────────

- [ ] Salt Water    (impl) id 12 — ocean fill above ocean-floor sand; no flow physics yet
- [ ] Lava          (impl) id 13 — luminous liquid; contact damage; creates obsidian where it meets salt water
- [ ] Fresh Water   (idea) — inland lake/river fill; separate from ocean BFS; drinking restores stamina; flow physics
- [ ] Honey         (idea) — produced by bee hive blocks; very slow flow; harvested as food/crafting ingredient

# ─────────────────────────────────────────────────────────────────────────────
# ORES & GEMS
# ─────────────────────────────────────────────────────────────────────────────

- [ ] Coal Ore      (impl) id 8  — shallow depths 2–80; cluster 6; drops coal (fuel)
- [ ] Gold Ore      (impl) id 9  — mid depths 60–300; cluster 4; drops gold (currency/alloy)
- [ ] Diamond Ore   (impl) id 10 — deep 250–450; cluster 2; drops diamond (high-tier cutting material)
- [ ] Mithril Ore   (impl) id 11 — very deep 200–511; cluster 3; drops mithril (end-game alloy)
- [ ] Iron Ore      (idea) — mid-shallow 10–200; cluster 5; workhorse crafting metal; smelts to iron bar
- [ ] Copper Ore    (idea) — shallow 5–120; cluster 5; early-game metal; alloys with tin into bronze
- [ ] Tin Ore       (idea) — shallow 5–100; cluster 4; pairs with copper; rarely useful alone
- [ ] Silver Ore    (idea) — mid depths 80–350; cluster 3; currency metal; anti-dark-magic properties
- [ ] Emerald       (idea) — mid-deep 100–400; rare; cluster 1; trading currency with certain races; bright green gem
- [ ] Sapphire      (idea) — deep 200–450; rare; cluster 1; magic conductor; used in rune crafting; blue gem
- [ ] Ruby          (idea) — deep 200–450; rare; cluster 1; fire affinity; used in forge upgrades and fire runes; red gem
- [ ] Opal          (idea) — mid depths 80–350; rare; cluster 2; iridescent; used in illusion magic and jewellery
- [ ] Saltpeter     (idea) — cave ceiling deposits; used in explosives and fertiliser; harvested with scraper tool
- [ ] Crystal Shard (idea) — rare deep veins; glows faintly (luminous); used in lanterns, scrying, and magic items

# ─────────────────────────────────────────────────────────────────────────────
# ORGANICS — trees, crops, flora, fungi
# ─────────────────────────────────────────────────────────────────────────────

## Tree parts (placed tiles)
- [ ] Oak Trunk     (impl) id 14 — placed by worldgen tree pass; drops oak log
- [ ] Oak Leaves    (impl) id 15 — canopy tile; transparent; future: drops saplings
- [ ] Palm Trunk    (impl) id 21 — tall tropical tree; drops palm log
- [ ] Palm Leaves   (impl) id 22 — tropical canopy; transparent
- [ ] Spruce Trunk  (impl) id 23 — cold/alpine tree; drops spruce log
- [ ] Spruce Leaves (impl) id 24 — dense dark canopy; transparent
- [ ] Birch Trunk   (impl) id 25 — cool-humid tree; pale bark; drops birch log
- [ ] Birch Leaves  (impl) id 26 — light airy canopy; transparent
- [ ] Oak Log Block    (idea) — whole horizontal log tile; placed by player; decorative; same drop as trunk
- [ ] Birch Log Block  (idea) — birch variant horizontal log tile
- [ ] Palm Log Block   (idea) — palm variant horizontal log tile
- [ ] Spruce Log Block (idea) — spruce variant horizontal log tile

## Ground cover & shrubs
- [ ] Bush          (impl) id 16 — solid low shrub; blocks movement; drops wood_stick
- [ ] Tulip         (impl) id 17 — non-solid flower; cool-humid zones
- [ ] Rose          (impl) id 27 — non-solid flower; warm-humid zones
- [ ] Lavender      (impl) id 28 — non-solid flower; hot-dry zones
- [ ] Daisy         (impl) id 29 — non-solid flower; cool zones
- [ ] Mushroom      (idea) — dark forest floors and caves; edible (small heal); spreads via mycelium tick behaviour
- [ ] Mushroom Cap  (idea) — giant mushroom top; deep underground; glows faintly; exotic biome marker
- [ ] Kelp          (idea) — underwater; grows upward from ocean floor; harvested for food and rope
- [ ] Coral         (idea) — shallow ocean floor clusters; decorative; several colour variants; fragile
- [ ] Cactus        (idea) — hot-arid surface; contact damage; drops cactus fiber (cloth/rope alternative)
- [ ] Dead Bush     (idea) — arid surface scatter; purely decorative; drops sticks
- [ ] Vines         (idea) — hang from overhangs and cave ceilings; climbable; slow spread
- [ ] Spider Web    (idea) — placed by spiders in dark caves; slows movement; drops silk thread

## Crops (farmable, multi-stage tick growth)
- [ ] Wheat         (idea) — tilled dirt; 4-stage growth; drops wheat grain when mature; staple food crop
- [ ] Corn          (idea) — tilled dirt; tall 2-tile stalk; drops corn cobs; grindable to cornmeal
- [ ] Carrots       (idea) — tilled dirt; 3-stage root crop; harvested from ground; cooked or raw food
- [ ] Potatoes      (idea) — tilled dirt; 3-stage root crop; cooked into a filling meal; also brewable

## Saplings
- [ ] Sapling       (idea) — planted by player; grows into full tree via tick system; requires light and soil

# ─────────────────────────────────────────────────────────────────────────────
# STRUCTURAL — building blocks and placed workstations
# ─────────────────────────────────────────────────────────────────────────────

## Wall / floor blocks
- [ ] Oak Planks    (impl) id 18 — crafted from oak log; basic building block
- [ ] Stone Bricks  (impl) id 19 — crafted from stone chunk; solid construction
- [ ] Marble Bricks (impl) id 20 — crafted from marble chunk; decorative high-tier construction
- [ ] Cobblestone   (idea) — raw stone drop; also craftable into cobblestone bricks
- [ ] Clay Bricks   (idea) — kiln-fired clay; warm terracotta tones; good insulation
- [ ] Sandstone Bricks (idea) — cut sandstone; desert aesthetic; mid-tier
- [ ] Limestone Bricks (idea) — pale smooth wall block; coastal building style
- [ ] Granite Bricks   (idea) — hard speckled block; prestige construction material
- [ ] Colored Bricks   (idea) — dyed clay or stone bricks; multiple colour variants using mineral pigments
- [ ] Thatch        (idea) — woven palm leaves; cheap roofing; flammable; fast to place
- [ ] Glass Pane    (idea) — smelted from sand; transparent window block

## Furniture & utilities
- [ ] Chest         (idea) — storage; holds item stacks; saved with chunk
- [ ] Door          (idea) — 2-tile-tall opening/closing block; wood or metal variants
- [ ] Ladder        (idea) — climbable vertical tile; placed on walls
- [ ] Rope          (idea) — deployable downward from above; climbable; harvested from kelp or cactus fiber
- [ ] Fence         (idea) — half-height barrier; encloses livestock; wood or iron
- [ ] Sign          (idea) — player-written text tile; stores short arbitrary text
- [ ] Drawbridge    (idea) — retractable floor; toggled by lever; spans gaps
- [ ] Torch         (idea) — luminous tile; placed on walls/floors; radius 4 light; fuelled by coal
- [ ] Lantern       (idea) — brighter permanent light; crafted from crystal shard + iron cage
- [ ] Bed           (idea) — sets respawn point; skips night if all players sleep

## Workstations
- [ ] Campfire      (idea) — basic outdoor cooking; no smelting; placed with flint + wood; 3-slot cooker
- [ ] Crafting Bench (idea) — unlocks full recipe crafting; 3×3 grid; central progression hub
- [ ] Furnace       (idea) — smelts ores and cooks food; fuelled by coal/wood; tick-based processing
- [ ] Kiln          (idea) — fires clay into bricks and pottery; requires higher heat than furnace; uses coal
- [ ] Forge         (idea) — crafts metal tools and weapons; requires bellows + coal; upgrades to mithril-tier items
- [ ] Anvil         (idea) — repairs and upgrades existing metal items; requires iron ingots to use
- [ ] Alchemy Table (idea) — combines gems, herbs, and runes into potions and enchanted items; magic progression

# ─────────────────────────────────────────────────────────────────────────────
# WEAPONS
# ─────────────────────────────────────────────────────────────────────────────

- [ ] Sword         (idea) — primary melee weapon; wood/stone/iron/gold/diamond/mithril tiers; scales damage and speed
- [ ] Bow           (idea) — ranged weapon; fires arrows; draw time varies by material; requires crafted arrows
- [ ] Spear         (idea) — longer reach melee; slower attack; throwable for ranged; good vs large creatures
- [ ] Dagger        (idea) — fast short melee; weak per-hit but high attack speed; bonus backstab damage
- [ ] Staff         (idea) — magic weapon; channels rune power; low physical damage but triggers spell effects
- [ ] Crossbow      (idea) — slow-loading ranged; higher damage than bow; fires bolts; usable in tight caves

# ─────────────────────────────────────────────────────────────────────────────
# ARMOR
# ─────────────────────────────────────────────────────────────────────────────

- [ ] Plate Armor   (idea) — full metal suit; highest defence; heavy (movement penalty); iron/gold/mithril tiers
- [ ] Scale Armor   (idea) — overlapping metal scales; balanced defence/mobility; mid-tier; crafted from ore scales + leather
- [ ] Chainmail     (idea) — interlocked rings; flexible; good against slashing; weak against piercing; iron/mithril
- [ ] Shield        (idea) — off-hand block item; absorbs % of incoming damage; wood/iron/mithril variants
- [ ] Leather Armor (idea) — early-game light armour; low defence but no movement penalty; crafted from animal hide
- [ ] Helmet        (idea) — head slot; minor defence + some protection from falling debris in caves
- [ ] Boots         (idea) — foot slot; reduce fall damage; some variants grant swim speed bonus

# ─────────────────────────────────────────────────────────────────────────────
# MAGIC
# ─────────────────────────────────────────────────────────────────────────────

- [ ] Runes         (idea) — carved stone/gem tokens; single-use or rechargeable; trigger elemental effects (fire, ice, lightning, earth)
- [ ] Rune Tablet   (idea) — multi-rune combination; placed like a tile; creates persistent area effects (ward, trap, beacon)
- [ ] Scroll        (idea) — single-use magic item; found in dungeons or crafted by Wizard race; wider spell variety than runes
- [ ] Potion        (idea) — consumable flask; brewed at alchemy table from herbs + gems; health/stamina/resistance effects
- [ ] Scrying Stone (idea) — reveals terrain in a radius when activated; uses crystal shards; limited charges
- [ ] Enchanted Gear (idea) — any tool/weapon/armour with a rune socketed; adds passive effect (e.g. fire sword, swift boots)

# ─────────────────────────────────────────────────────────────────────────────
# ITEMS / DROPS — raw materials, consumables, tools
# ─────────────────────────────────────────────────────────────────────────────

## Raw materials
- [ ] Dirt Clod       (idea) — drops from grass/dirt; farming fill
- [ ] Stone Chunk     (idea) — drops from stone; basic crafting material
- [ ] Marble Chunk    (idea) — drops from marble; decorative crafting
- [ ] Grimstone Chunk (idea) — drops from grimstone; late-game defensive structures
- [ ] Wood Log        (idea) — drops from any trunk; primary crafting material
- [ ] Wood Stick      (idea) — drops from bush; tool handle
- [ ] Coal            (idea) — drops from coal ore; fuel for all fire-based workstations
- [ ] Iron Bar        (idea) — smelted from iron ore; workhorse mid-tier material
- [ ] Gold Bar        (idea) — smelted from gold ore; currency and high-conductivity alloy
- [ ] Copper Bar      (idea) — smelted from copper ore; early-game tools and wire
- [ ] Bronze Bar      (idea) — alloyed from copper + tin; stronger than either; early alloy tier
- [ ] Silver Bar      (idea) — smelted from silver ore; currency and anti-dark-magic material
- [ ] Diamond         (idea) — drops from diamond ore; top-tier cutting material
- [ ] Mithril Bar     (idea) — smelted from mithril ore; lightest strongest metal; end-game equipment
- [ ] Emerald Gem     (idea) — drops from emerald ore; trading gem; magic conductor
- [ ] Sapphire Gem    (idea) — drops from sapphire ore; magic conductor; used in rune crafting
- [ ] Ruby Gem        (idea) — drops from ruby ore; fire-affinity gem; forge upgrade ingredient
- [ ] Opal Gem        (idea) — drops from opal ore; illusion magic ingredient; jewellery
- [ ] Sand Pile       (idea) — drops from sand; smelted into glass
- [ ] Glass Pane      (idea) — smelted from sand; placed as transparent structural tile
- [ ] Bone            (idea) — drops from skeletons and bone deposits; fertiliser; early tool shaft
- [ ] Silk Thread     (idea) — drops from spider webs; light armour and bags
- [ ] Hide            (idea) — drops from animals; leather armour; bags; rope
- [ ] Wool            (idea) — shorn from sheep; cloth; bedding ingredient

## Food
- [ ] Wheat Grain   (idea) — harvested from mature wheat; ground into flour; baking ingredient
- [ ] Corn Cob      (idea) — harvested from corn; eaten raw or ground to cornmeal
- [ ] Carrot        (idea) — harvested from carrot crop; minor heal raw; better cooked
- [ ] Potato        (idea) — harvested from potato crop; cooked into filling meal; also brewable
- [ ] Bread         (idea) — baked from flour; primary staple food; restores stamina + health
- [ ] Cooked Meat   (idea) — cooked animal drop; strong health restore; requires campfire/furnace
- [ ] Fish          (idea) — caught with fishing rod; raw or cooked; several species
- [ ] Crab Claw     (idea) — dropped by crab; cooked food; also decorative trophy

## Tools
- [ ] Pickaxe       (idea) — primary mining tool; wood/stone/iron/gold/diamond/mithril tiers
- [ ] Axe           (idea) — chops trees; also melee weapon; same material tiers as pickaxe
- [ ] Shovel        (idea) — digs sand/dirt/gravel fast; terraforming tool
- [ ] Hoe           (idea) — tills dirt into farmland; required for all crop planting
- [ ] Fishing Rod   (idea) — cast into ocean/lake to catch fish; durability-based
- [ ] Torch (item)  (idea) — held item that places torch tiles; also weak melee weapon
- [ ] Shears        (idea) — harvests wool from sheep without killing; also cuts vines and web cleanly
- [ ] Map           (idea) — reveals explored chunk layout on a scrollable overlay; craftable from paper
- [ ] Compass       (idea) — points toward world origin (spawn); crafted from iron + crystal shard

# ─────────────────────────────────────────────────────────────────────────────
# ENTITIES — animals, mobs, NPCs
# ─────────────────────────────────────────────────────────────────────────────

## Passive animals
- [ ] Cow           (idea) — grazes on grass; drops hide and raw meat; milkable for food ingredient
- [ ] Sheep         (idea) — grazes on grass; drops wool and mutton; shorn for renewable wool
- [ ] Pig           (idea) — roots around forest floors; drops raw pork; can be penned and bred
- [ ] Rabbit        (idea) — small fast passive; hops around meadows; drops hide and raw rabbit meat
- [ ] Stag (Deer)   (idea) — graceful; flees on approach; drops venison and hide; found in forests
- [ ] Horse         (idea) — can be tamed and ridden; greatly increases overworld travel speed; found in open plains
- [ ] Bat           (idea) — passive cave-dweller; startles when lit; drops nothing; atmospheric
- [ ] Crab          (idea) — passive on shore; hostile when attacked; drops crab claw
- [ ] Fish (various)(idea) — passive ocean schooling creatures; several species; different loot tables
- [ ] Sea Turtle    (idea) — swims in ocean; neutral; rare; drops turtle shell (helmet ingredient)

## Hostile mobs
- [ ] Skeleton Warrior (idea) — melee undead; dark caves; drops bone and sometimes rusted sword
- [ ] Skeleton Archer  (idea) — ranged undead; fires arrows from cave ledges; drops bone + arrows
- [ ] Cave Spider      (idea) — fast; places web tiles; drops silk; dark caves
- [ ] Troll            (idea) — large slow brute; guards cave chokepoints; drops grimstone chunk and hide
- [ ] Lava Golem       (idea) — emerges from lava pools; ranged lava-spit; drops obsidian shards
- [ ] Sea Serpent      (idea) — rare ocean patrol; attacks swimmers; drops scales and rare loot
- [ ] Skeleton Captain (idea) — rare dungeon mini-boss; armoured skeleton; drops captain's sword and map fragment
- [ ] Cave Bear        (idea) — territorial; attacks if cornered; drops hide and meat

## Bosses
- [ ] Deep Drake    (idea) — large cave dragon; guards mithril; fire breath; multi-phase fight
- [ ] Kraken        (idea) — ocean mega-boss; attacks from below; requires a ship to reach; drops ink and rare materials
- [ ] Island Colossus (idea) — earth-golem world boss beneath island center; late-game quest trigger; world-altering loot

# ─────────────────────────────────────────────────────────────────────────────
# RACES — playable and NPC civilisations
# ─────────────────────────────────────────────────────────────────────────────

- [ ] Dwarf         (idea) — the protagonist race; small, stout, exceptional miners; bonus to mining speed and carry weight
- [ ] Human         (idea) — balanced generalist; no bonuses or penalties; common NPC traders and guards
- [ ] Elf           (idea) — tall, agile, long-lived; bonus to archery and magic; penalties to heavy armour
- [ ] Orc           (idea) — strong hostile faction; high melee damage; low intelligence; can be allied via quest line
- [ ] Goblin        (idea) — small cunning scavengers; appear in caves and ruins; steal items if not defended against
- [ ] Kobold        (idea) — lizard-like underground miners; semi-hostile; may trade rare ores if approached peacefully
- [ ] Argonian      (idea) — reptilian amphibious race; swim speed bonus; immune to poison; found in coastal wetlands
- [ ] Wizard        (idea) — rare NPC class of any race; trades scrolls and runes; may offer magic quests
- [ ] Mermaids      (idea) — ocean-dwelling; neutral to friendly; trade with coastal settlements; hostile if ocean is polluted
- [ ] Deep Ones     (idea) — ancient aquatic race below deep ocean; hostile by default; drops unique deep-sea materials
- [ ] Merchant NPC  (idea) — generic travelling merchant; any race; appears at spawn and ports; buys raw materials, sells tools
- [ ] Villager NPC  (idea) — settles in small coastal towns; gives quests; trades food for resources
