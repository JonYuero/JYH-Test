-- ============================================================
--  Anime Card Farm  –  Rayfield Edition
--  Config auto-saves via Rayfield's built-in ConfigurationSaving
-- ============================================================

-- Try multiple Rayfield sources in case one is down
local Rayfield
local rayfieldUrls = {
    "https://sirius.menu/rayfield",
    "https://raw.githubusercontent.com/UI-Hub/Rayfield/main/source",
    "https://raw.githubusercontent.com/shlexware/Rayfield/main/source",
}
for _, url in ipairs(rayfieldUrls) do
    local ok, result = pcall(function()
        return loadstring(game:HttpGet(url, true))()
    end)
    if ok and result then
        Rayfield = result
        break
    end
end
if not Rayfield then
    error("[ACF] Failed to load Rayfield from all sources. Check your executor's HTTP settings.")
end

-- ── Services ─────────────────────────────────────────────────
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser       = game:GetService("VirtualUser")
local StarterGui        = game:GetService("StarterGui")

local player = Players.LocalPlayer
if not player.Character then player.CharacterAdded:Wait() end
local playerGui = player:WaitForChild("PlayerGui")

-- ── Remotes ──────────────────────────────────────────────────
-- CONFIRMED: ReplicatedStorage.Remotes.ConveyorRE
-- Purchase: ConveyorRE:FireServer("TryBuy", { ItemId = X })
local Remotes    = ReplicatedStorage:WaitForChild("Remotes")
local ConveyorRE = Remotes:WaitForChild("ConveyorRE")
local PlayTimeRewardRE = Remotes:FindFirstChild("PlayTimeRewardRE")
local DailyRewardRE    = Remotes:FindFirstChild("DailyRewardRE")
local UpgradesRE       = Remotes:FindFirstChild("UpgradesRE")
local BossRaidRE = Remotes:FindFirstChild("BossRaidRE")
local Modules    = ReplicatedStorage:FindFirstChild("Modules")
local BossRaidConfig
if Modules and Modules:FindFirstChild("BossRaidConfig") then
    pcall(function()
        BossRaidConfig = require(Modules.BossRaidConfig)
    end)
end
local currentRaidBossId = ""

-- ── Data lists ───────────────────────────────────────────────
local RARITIES = {
    "Common", "Uncommon", "Rare", "Epic",
    "Legendary", "Mythic", "Secret", "Divine",
    "Transcendent", "Shadow", "Emperor", "Demon",
    "Manga", "Celestial", "Heavenly", "Corrupted",
    "Striker", "Sacred", "Paradox", "Founder",
    "Evolved", "Magic", "Oni", "Chaos",
    "Ruin", "Limited",
}

local MUTATIONS = {
    "Normal", "Golden", "Venomous", "Diamond",
    "Rainbow", "Sakura", "Candy", "Blessed",
    "Radioactive", "Glitch", "Starfallen", "Admin",
}

local PACKS = {
    "Ice Pack", "Sand Pack", "Inferno Pack", "Lightning Pack",
    "Hightech Pack", "Dark Pack", "Eclipse Pack", "Isekai Pack",
    "Slayer Pack", "Monarch Pack", "Pirate King Pack", "Demon Pack",
    "Manga Pack", "Galaxy Pack", "Heaven Pack", "Void Pack",
    "Soccer Pack", "Empyrean Pack", "Bizarre Pack", "Titan Pack",
    "Evolved Pack", "Grimoire Pack", "Oni Pack", "Chaos Pack",
    "Ruin Pack", "Royal Pack", "Mage Pack", "Beast Pack", "Viking Pack",
    "Hunter Pack", "Soul Pack", "Swordsman Pack", "Gamer Pack",
    "Revenge Pack", "Chainsaw Pack", "Eternity Pack", "Academy Pack",
    "Dynasty Pack", "Grail Pack", "Conquest Pack", "Blaze Pack",
    "Devour Pack",
}

local POTIONS = {
    "LuckPotion1", "LuckPotion2", "LuckPotion3",
    "CashPotion1", "CashPotion2", "CashPotion3",
    "TimePotion1", "TimePotion2",
    "MutationPotion1",
    "ProductionPotion1", "ProductionPotion2",
}

local BOOSTS = {
    { label = "Base Expansion", id = "base" },
    { label = "Luck Boost",     id = "luck" },
    { label = "Cash Boost",     id = "cash" },
    { label = "Time Boost",     id = "time" },
    { label = "Speed Boost",    id = "speed" },
}

local function selectionIncludes(selection, wanted)
    if type(selection) ~= "table" then
        return selection == nil or tostring(selection) == "All"
            or tostring(selection) == wanted
    end
    if #selection == 0 then
        return true
    end
    for _, value in ipairs(selection) do
        if tostring(value) == "All" or tostring(value) == wanted then
            return true
        end
    end
    return false
end

local function collapseFullSelection(selection, options)
    if type(selection) ~= "table" or #selection == 0 then
        return { "All" }
    end
    for _, value in ipairs(selection) do
        if tostring(value) == "All" then return { "All" } end
    end
    local selected = {}
    for _, value in ipairs(selection) do selected[tostring(value)] = true end
    local allSelected = true
    for _, option in ipairs(options) do
        if not selected[option] then
            allSelected = false
            break
        end
    end
    if allSelected then return { "All" } end
    return selection
end

local MAX_CARD_LEVEL = 50
local CARD_REMOVAL_DELAY = 0.5

local RARITY_RANK = {}
for index, rarity in ipairs(RARITIES) do
    RARITY_RANK[string.lower(rarity)] = index
end

local MUTATION_RANK = {}
for index, mutation in ipairs(MUTATIONS) do
    MUTATION_RANK[string.lower(mutation)] = index
end

-- ── Config ───────────────────────────────────────────────────
local Config = {
    -- Spawn
    AutoSpawnPack   = false,
    SpawnDelay      = 0.5,
    AutoStopSpawn   = false,
    AutoBuyMatching = false,
    AutoBuyDebug    = true,
    AutoCarryBox    = false,
    AutoSellBox     = false,
    AutoSellDelay   = 30,
    PlotNumber      = 1,    -- will be overwritten by auto-detect at startup

    -- Filter
    SelectedRarities  = {},
    SelectedMutations = {},
    SelectedPacks     = {},

    -- Cards
    AutoUpgrade       = false,
    UpgradeDelay      = 0.15,
    CardActionDelay   = 0.5,
    AutoSell          = false,
    AutoTraitRoll     = false,
    AutoClaimPlaytime = false,
    AutoClaimDaily    = false,
    AutoPlacePack     = false,
    AutoOpenPack      = false,
    AutoBuyBoost      = false,

    -- Combat
    AutoInfinityEquip = false,
    AutoInfinityTower = false,
    AutoInfinityHide  = false,
    RaidDifficulties  = { "Easy" },
    AutoRaidEquip     = false,
    AutoRaid          = false,
    AutoRaidHide      = false,
    AutoTeamCardCycle = false,

    -- Misc
    AutoPotion = false,
    SelectedPotions = {},
    SelectedBoosts = {},
    AntiAfk    = true,
}

-- Playtime state is pushed by the game's client remote. Keep only ready,
-- unclaimed indexes so Auto Claim does not spam all 12 rewards every cycle.
local playtimeReadyRewards = {}
local playtimeStateReceived = false

-- Forward declarations used by the combat loops, which are intentionally
-- started before the optional GUI controls are resolved.
local clickGuiButton
local startCombatBattle
local removeAllCards
local removeFirstFourCardSlots
local doEquipBestCards

-- ── Remote helpers ───────────────────────────────────────────
-- Used for non-ConveyorRE remotes only.
local function findRemote(name)
    local directRemote = Remotes and Remotes:FindFirstChild(name)
    if directRemote then return directRemote end
    return ReplicatedStorage:FindFirstChild(name, true)
end

local function fireRemote(name, ...)
    local remote = findRemote(name)
    if not remote then
        warn("[ACF] Remote not found: " .. name)
        return false
    end

    local ok, err
    if remote:IsA("RemoteEvent") then
        ok, err = pcall(remote.FireServer, remote, ...)
    elseif remote:IsA("RemoteFunction") then
        ok, err = pcall(remote.InvokeServer, remote, ...)
    else
        warn("[ACF] " .. name .. " is not a RemoteEvent or RemoteFunction")
        return false
    end

    if not ok then
        warn("[ACF] " .. name .. " failed: " .. tostring(err))
    end
    return ok
end

-- ── Button firing ────────────────────────────────────────────
-- CONFIRMED: spawn button = ButtonPart with a ClickDetector child.
-- Priority order: fireclickdetector → fireproximityprompt → MouseClick:Fire
local function fireButton(part)
    if not part then return false end

    -- ClickDetector (CONFIRMED method for ButtonPart)
    local click = part:FindFirstChildOfClass("ClickDetector")
               or part:FindFirstChild("ClickDetector")
    if click then
        if fireclickdetector then
            pcall(fireclickdetector, click)
            return true
        end
        -- Fallback: fire the MouseClick signal directly
        pcall(function() click.MouseClick:Fire(player.Character) end)
        return true
    end

    -- ProximityPrompt (fallback for other buttons)
    local prompt = part:FindFirstChildOfClass("ProximityPrompt")
    if prompt then
        if fireproximityprompt then
            pcall(fireproximityprompt, prompt)
            return true
        end
        if firetouchinterest then
            pcall(firetouchinterest, part, player.Character, 0)
            return true
        end
    end

    return false
end

-- Prefer executor interaction helpers, but also support games that expose the
-- same action through a RemoteEvent/RemoteFunction. This matters on tablets
-- and on executors that do not implement fireproximityprompt/fireclickdetector.
local function firePrompt(prompt)
    if not prompt then return false end
    if fireproximityprompt then
        local ok = pcall(fireproximityprompt, prompt)
        if ok then return true end
    end
    local remote = prompt:FindFirstChild("Remote")
        or prompt:FindFirstChild("RemoteEvent")
        or prompt:FindFirstChild("RemoteFunction")
    if remote and (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction")) then
        if remote:IsA("RemoteEvent") then
            return pcall(remote.FireServer, remote)
        end
        return pcall(remote.InvokeServer, remote)
    end
    return false
end

local function fireClickDetector(detector)
    if not detector then return false end
    if fireclickdetector then
        local ok = pcall(fireclickdetector, detector)
        if ok then return true end
    end
    return pcall(function() detector.MouseClick:Fire(player) end)
end

local function refreshPlaytimeReadyRewards(state)
    if type(state) ~= "table" then return end
    playtimeStateReceived = true
    table.clear(playtimeReadyRewards)
    local rewards = state.Rewards or state
    if type(rewards) ~= "table" then return end
    for index = 1, 12 do
        local reward = rewards[index] or rewards[tostring(index)]
        if type(reward) == "table"
            and reward.Claimed ~= true
            and reward.Ready == true then
            playtimeReadyRewards[index] = true
        end
    end
end

if PlayTimeRewardRE and PlayTimeRewardRE:IsA("RemoteEvent") then
    PlayTimeRewardRE.OnClientEvent:Connect(function(eventName, payload)
        if eventName == "State" then
            refreshPlaytimeReadyRewards(payload)
        elseif eventName == "ClaimSuccess" and type(payload) == "table" then
            local index = tonumber(payload.RewardIndex)
            if index then playtimeReadyRewards[index] = nil end
        end
    end)
end

-- ══════════════════════════════════════════════════════════════
--  PLOT AUTO-DETECTION  (fully automatic, no UI controls)
--
--  CONFIRMED (from in-game Explorer): the game stores the assigned plot
--  number as an IntValue named "PlotNumber" directly under each Player
--  object in game.Players.  e.g. Players.Hayju76.PlotNumber = 3
--
--  The script waits for workspace.MAP to exist and for the server to
--  assign the IntValue before proceeding.  No slider or button needed.
-- ══════════════════════════════════════════════════════════════

-- Internal setter — updates Config.PlotNumber and prints a log line.
-- No UI references; the plot is managed entirely in the background.
local function setPlotNumber(n)
    if type(n) ~= "number" or n == Config.PlotNumber then return end
    Config.PlotNumber = n
    warn("[ACF] Plot auto-detected: #" .. tostring(n))
    notify("Plot Detected", "Your plot is slot #" .. tostring(n))
end

-- Read the IntValue the game puts on the Player object.
local function readPlayerPlotNumber()
    local iv = player:FindFirstChild("PlotNumber")
    if iv and iv:IsA("IntValue") then return tonumber(iv.Value) end
    local attr = player:GetAttribute("PlotNumber")
    if attr ~= nil then return tonumber(attr) end
    return nil
end

-- Re-exported for the spawn loop's fallback re-detection call.
local function autoDetectMyPlotNumber()
    return readPlayerPlotNumber()
end

-- Wait for the game world and server assignment, then set the plot number.
-- Runs in a background task so it never blocks the main thread.
task.spawn(function()
    -- 1. Wait for workspace.MAP to exist (game is still loading without it).
    local map = workspace:FindFirstChild("MAP")
    if not map then
        map = workspace:WaitForChild("MAP", 30)
    end
    if not map then
        warn("[ACF] workspace.MAP not found after 30 s — game may use a different structure.")
    end

    -- 2. Wait for the server to assign PlotNumber on the player object.
    --    This is typically an IntValue added within the first 1–3 seconds.
    local iv = player:FindFirstChild("PlotNumber")
    if not iv then
        -- Block up to 15 s for the IntValue to appear.
        iv = player:WaitForChild("PlotNumber", 15)
    end

    if iv and iv:IsA("IntValue") then
        local n = tonumber(iv.Value)
        if n and n > 0 then
            setPlotNumber(n)
        end

        -- Watch for server-side reassignments (e.g. player changes slot).
        iv.Changed:Connect(function(newVal)
            local num = tonumber(newVal)
            if num and num > 0 then
                Config.PlotNumber = num
                warn("[ACF] Plot reassigned by server: #" .. tostring(num))
                notify("Plot Updated", "Moved to slot #" .. tostring(num))
                -- Clear the sell station cache so it rescans on the new plot.
                sellBoxPartCache = nil
            end
        end)
    else
        -- Attribute fallback (some server builds store it as an Attribute).
        local attr = player:GetAttribute("PlotNumber")
        if attr ~= nil then
            local n = tonumber(attr)
            if n and n > 0 then setPlotNumber(n) end
        else
            warn("[ACF] PlotNumber not found on player after 15 s. "
                .. "Carry/Sell will not work correctly until the plot is assigned.")
        end
        -- Watch attribute version.
        player:GetAttributeChangedSignal("PlotNumber"):Connect(function()
            local num = tonumber(player:GetAttribute("PlotNumber"))
            if num and num > 0 then
                Config.PlotNumber = num
                sellBoxPartCache  = nil
                warn("[ACF] Plot (attr) assigned: #" .. tostring(num))
            end
        end)
    end
end)

-- CONFIRMED path (from in-game dump):
--   workspace.MAP.Plots.<plotNumber>.Plot_N0.ButtonPart.ClickDetector
--
-- findPlot returns the Plot_N0 model for the given plot number.
local function findPlot(plotNumber)
    -- Primary confirmed path
    local map   = workspace:FindFirstChild("MAP")
    local plots = map and map:FindFirstChild("Plots")
    if plots then
        local slot = plots:FindFirstChild(tostring(plotNumber))
        if slot then
            -- Plot_N0 is the actual plot model inside the numbered slot
            local plotN0 = slot:FindFirstChild("Plot_N0")
            if plotN0 then return plotN0 end
            -- Fallback: return the slot itself if no Plot_N0
            return slot
        end
    end

    -- Fallback: search all of workspace for Plot_N0 near a ButtonPart
    -- (handles edge cases if MAP folder is renamed)
    local fallbackPlots = workspace:FindFirstChild("Plots")
    if fallbackPlots then
        local slot = fallbackPlots:FindFirstChild(tostring(plotNumber))
                  or fallbackPlots:FindFirstChild("Plot" .. tostring(plotNumber))
        if slot then
            return slot:FindFirstChild("Plot_N0") or slot
        end
    end

    return nil
end

-- Find spawn / place button parts inside a plot.
-- CONFIRMED: workspace.MAP.Plots.<N>.Plot_N0.ButtonPart  (has ClickDetector child)
local function getPlotButtons(plotNumber)
    local plot = findPlot(plotNumber)
    if not plot then return nil, nil end

    -- Confirmed spawn button name
    local spawnBtn = plot:FindFirstChild("ButtonPart", true)
               or plot:FindFirstChild("ButtonSelect", true)

    -- Place button — not yet confirmed; try common names recursively
    local placeBtn = plot:FindFirstChild("PlaceButton",    true)
               or plot:FindFirstChild("ConveyorButton", true)
               or plot:FindFirstChild("ButtonPlace",    true)

    return spawnBtn, placeBtn
end

local function notify(title, text)
    pcall(StarterGui.SetCore, StarterGui, "SendNotification", {
        Title = title, Text = text, Duration = 3,
    })
end

-- ── Filter logic ─────────────────────────────────────────────
local function normalizeFilterValue(value)
    if value == nil then return nil end
    return string.lower(string.gsub(tostring(value), "^%s*(.-)%s*$", "%1"))
end

local function normalizeFilterSelection(value)
    local selected = {}

    if type(value) ~= "table" then
        value = value == nil and {} or { value }
    end

    local function add(option)
        local normalized = normalizeFilterValue(option)
        if normalized and normalized ~= "any" then
            selected[normalized] = true
        end
    end

    -- Rayfield normally returns an array, while older saved configurations
    -- may restore a dictionary or a single string. Accept all three forms.
    local hadArrayValues = false
    for _, option in ipairs(value) do
        hadArrayValues = true
        add(option)
    end
    if not hadArrayValues then
        for option, enabled in pairs(value) do
            if enabled then add(option) end
        end
    end

    return selected
end

local function filterCompareKey(value)
    local normalized = normalizeFilterValue(value)
    if not normalized then return nil end
    -- Pack names can be replicated as "IcePack" or "Ice Pack" depending on
    -- which client object supplied the metadata.
    return string.gsub(normalized, "[^%w]", "")
end

local function filterValueMatches(value, selected)
    if next(selected) == nil then return true end
    local valueKey = filterCompareKey(value)
    if not valueKey then return false end

    for wanted in pairs(selected) do
        local wantedKey = filterCompareKey(wanted)
        if wantedKey == valueKey
            or (wantedKey and string.find(valueKey, wantedKey, 1, true))
            or (wantedKey and string.find(wantedKey, valueKey, 1, true)) then
            return true
        end
    end
    return false
end

-- Metadata is read from live replicated objects, but the hierarchy itself
-- does not need to be traversed on every poll.
local metadataCache = setmetatable({}, { __mode = "k" })

local function readBoxValue(box, names)
    for _, name in ipairs(names) do
        local attribute = box:GetAttribute(name)
        if attribute ~= nil then
            return attribute
        end
    end

    -- Some game revisions put the metadata on a child model rather than the
    -- conveyor container itself. Check descendant attributes before using the
    -- cached value-object lookup.
    for _, descendant in ipairs(box:GetDescendants()) do
        for _, name in ipairs(names) do
            local attribute = descendant:GetAttribute(name)
            if attribute ~= nil then
                return attribute
            end
        end
    end

    local metadata = metadataCache[box]
    if not metadata then
        metadata = {}
        for _, descendant in ipairs(box:GetDescendants()) do
            local key = string.lower(descendant.Name)
            if not metadata[key] then
                metadata[key] = descendant
            end
        end
        metadataCache[box] = metadata
    end

    for _, name in ipairs(names) do
        local valueObject = metadata[string.lower(name)]
        if valueObject then
            if valueObject:IsA("ValueBase") then
                return valueObject.Value
            end
            if valueObject:IsA("TextLabel") or valueObject:IsA("TextButton") then
                return valueObject.Text
            end
        end
    end

    return nil
end

local function getBoxInfo(box)
    if not box then return nil end

    local packValue = readBoxValue(box, { "Pack", "PackName", "pack" })

    -- CONFIRMED (from logs): the game does not store pack name as an Attribute or
    -- ValueBase. The model is simply named after the pack (e.g. "Ice Pack",
    -- "Sand Pack"). Fall back to the model name when no attribute is found.
    if packValue == nil and box:IsA("Model") then
        local name = box.Name
        if string.find(string.lower(name), "pack", 1, true) then
            packValue = name
        end
    end

    -- If the container is a generic BoxBaseModel, the pack name is often on a
    -- nearby ancestor or child model. Prefer a known pack name over a generic
    -- object name so a matching pack is not discarded during replication.
    if packValue == nil then
        local function findKnownPackName(value)
            local key = filterCompareKey(value)
            if not key then return nil end
            for _, packName in ipairs(PACKS) do
                local packKey = filterCompareKey(packName)
                if packKey and (key == packKey
                    or string.find(key, packKey, 1, true)
                    or string.find(packKey, key, 1, true)) then
                    return packName
                end
            end
            return nil
        end

        local current = box
        for _ = 1, 6 do
            if not current then break end
            packValue = findKnownPackName(current.Name)
            if packValue then break end
            current = current.Parent
        end

        if not packValue then
            for _, descendant in ipairs(box:GetDescendants()) do
                packValue = findKnownPackName(descendant.Name)
                if packValue then break end
            end
        end
    end

    return {
        rarity   = readBoxValue(box, { "Rarity",   "rarit",        "rarity"   }),
        mutation = readBoxValue(box, { "Mutation",  "MutationName", "mutation" }),
        pack     = packValue,
    }
end

-- CONFIRMED: ItemId is sequential per session, starting from 1.
-- It may live as an Attribute or ValueBase on the pack model or any ancestor
-- up the conveyor hierarchy (e.g. LocalConveyorModels or Plot_N0 level).
local function getItemId(container)
    -- First check the container itself.
    local value = readBoxValue(container, { "ItemId", "ItemID", "itemId" })
    if value ~= nil then return tonumber(value) or value end

    -- Walk up ancestors (up to 6 levels) to find the ItemId on a parent model.
    local current = container.Parent
    for _ = 1, 6 do
        if not current or current == workspace then break end
        local parentValue = nil
        for _, name in ipairs({ "ItemId", "ItemID", "itemId" }) do
            parentValue = current:GetAttribute(name)
            if parentValue ~= nil then break end
        end
        if parentValue == nil then
            -- Try ValueBase child on this ancestor.
            local child = current:FindFirstChild("ItemId")
                       or current:FindFirstChild("ItemID")
                       or current:FindFirstChild("itemId")
            if child and child:IsA("ValueBase") then
                parentValue = child.Value
            end
        end
        if parentValue ~= nil then return tonumber(parentValue) or parentValue end
        current = current.Parent
    end

    return nil
end

local function isPackContainer(container, info)
    if not container then return false end

    local name = string.lower(container.Name)
    if name == "boxbasemodel"
        or string.find(name, "pack", 1, true)
        or string.find(name, "box", 1, true) then
        return true
    end

    -- ItemId or Pack metadata on this model is stronger evidence than a
    -- generic ancestor name. Rarity/mutation alone is not enough.
    return getItemId(container) ~= nil
        or info and info.pack ~= nil
end

-- ── Conveyor container registry ──────────────────────────────
-- Single shared tracking table used by both Auto Stop and Auto Buy.
-- Model → { itemId, info, stage, timeCreated }
-- "stage" values: "spawned", "reachedB" (purchasable), "buying", "gone"
local conveyorState = {}          -- model → state record
local itemIdIndex   = {}          -- itemId (number) → model (for fast O(1) lookup)
local watchedModels = setmetatable({}, { __mode = "k" })
local registerConveyorContainer
local watchAllPromptsOnPack
local isBuyPrompt
local tryBuyConveyorPack
local passesFilter
local debugAutoBuy
local describePack
local boxHandlingActive = false

local function hasItemIdAttribute(instance)
    for _, name in ipairs({ "ItemId", "ItemID", "itemId" }) do
        if instance:GetAttribute(name) ~= nil then
            return true
        end
    end
    return false
end

local function hasConveyorAncestor(model)
    if not model or not model:IsA("Model") then return false end

    local current = model
    for _ = 1, 10 do
        if not current then break end
        local name = string.lower(current.Name)
        if name == "conveyor"
            or string.find(name, "conveyor", 1, true) then
            return true
        end
        current = current.Parent
    end
    return false
end

local function shouldWatchModel(model)
    if not model or not model:IsA("Model") then return false end
    return hasConveyorAncestor(model)
end

local function getOwningModel(instance)
    return instance and instance:FindFirstAncestorOfClass("Model")
end

local function findPackContainer(instance)
    local current = instance
    if current and not current:IsA("Model") then
        current = getOwningModel(current)
    end

    for _ = 1, 10 do
        if not current then break end
        if shouldWatchModel(current)
            and isPackContainer(current, getBoxInfo(current)) then
            return current
        end
        current = current.Parent
        while current and not current:IsA("Model") do
            current = current.Parent
        end
    end

    return nil
end

local function watchModel(model)
    if not shouldWatchModel(model) or watchedModels[model] then return end
    watchedModels[model] = true

    for _, name in ipairs({ "ItemId", "ItemID", "itemId" }) do
        model:GetAttributeChangedSignal(name):Connect(function()
            if model:GetAttribute(name) ~= nil then
                registerConveyorContainer(model)
            end
        end)
    end
end

registerConveyorContainer = function(container)
    local pack = findPackContainer(container)
    if not pack then return end

    watchModel(pack)

    if conveyorState[pack] then
        -- Already registered; refresh ItemId in case it was just assigned.
        local itemId = getItemId(pack)
        if itemId ~= nil and conveyorState[pack].itemId == nil then
            conveyorState[pack].itemId = itemId
            itemIdIndex[itemId] = pack
            if Config.AutoBuyDebug then
                warn(string.format(
                    "[Conveyor] ItemId %s assigned to %s  pack=%s rarity=%s mutation=%s",
                    tostring(itemId),
                    pack:GetFullName(),
                    tostring(conveyorState[pack].info and conveyorState[pack].info.pack),
                    tostring(conveyorState[pack].info and conveyorState[pack].info.rarity),
                    tostring(conveyorState[pack].info and conveyorState[pack].info.mutation)
                ))
            end
        end
        return
    end

    local itemId  = getItemId(pack)
    local info    = getBoxInfo(pack)
    local record  = {
        model       = pack,
        itemId      = itemId,
        info        = info,
        stage       = "spawned",
        timeCreated = os.clock(),
    }
    conveyorState[pack] = record
    if itemId ~= nil then
        itemIdIndex[itemId] = pack
    end

    if Config.AutoBuyDebug then
        warn(string.format(
            "[Conveyor] Registered ItemId=%s  model=%s  pack=%s  rarity=%s  mutation=%s  time=%.2f",
            tostring(itemId),
            pack:GetFullName(),
            tostring(info and info.pack),
            tostring(info and info.rarity),
            tostring(info and info.mutation),
            record.timeCreated
        ))
    end
end

local function unregisterConveyorContainer(container)
    if not container then return end
    local record = conveyorState[container]
    if record and record.itemId ~= nil then
        itemIdIndex[record.itemId] = nil
    end
    conveyorState[container] = nil
    metadataCache[container] = nil
end

-- Build the candidate set once, then maintain it as replicated objects enter
-- and leave workspace. This replaces repeated full-workspace scans.
for _, descendant in ipairs(workspace:GetDescendants()) do
    if descendant:IsA("Model") then
        if shouldWatchModel(descendant) then
            watchModel(descendant)
            if hasItemIdAttribute(descendant)
                or descendant:FindFirstChildWhichIsA("ProximityPrompt", true) then
                registerConveyorContainer(descendant)
            end
        end
    elseif string.lower(descendant.Name) == "itemid"
        and descendant:IsA("ValueBase") then
        registerConveyorContainer(getOwningModel(descendant))
    end
end

-- ── Event-driven buy on prompt enable ────────────────────────
-- Instead of (only) polling every second, hook each ProximityPrompt's
-- Enabled signal so we react the instant the pack reaches the buy zone.
-- tryBuyConveyorPack / passesFilter / isBuyPrompt are declared later but
-- this function is only *called* at runtime, so forward references are fine.
local watchedPrompts = setmetatable({}, { __mode = "k" })

local function watchPromptForBuy(prompt, packModel)
    if not prompt or not packModel then return end
    if watchedPrompts[prompt] then return end
    watchedPrompts[prompt] = true
    local trackedPack = findPackContainer(packModel) or packModel

    prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
        if not prompt.Enabled then return end
        if not Config.AutoBuyMatching then return end
        if boxHandlingActive then return end

        -- Find the state record for this pack.
        local record = conveyorState[trackedPack]
        if not record then return end
        if record.stage == "bought" then return end
        record.info = getBoxInfo(trackedPack)

        -- Only act on prompts that look like buy prompts.
        if not isBuyPrompt(prompt) then
            -- If there is only one prompt on this pack, treat it as the buy prompt.
            local count = 0
            for _, d in ipairs(packModel:GetDescendants()) do
                if d:IsA("ProximityPrompt") then count += 1 end
            end
            if count ~= 1 then return end
        end

        if passesFilter(record.info) then
            debugAutoBuy(
                "Prompt enabled (event) — immediate buy attempt  " ..
                describePack(record)
            )
            tryBuyConveyorPack(record)
        end
    end)
end

-- Hook all existing prompts on a pack model.
watchAllPromptsOnPack = function(packModel)
    for _, descendant in ipairs(packModel:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") then
            watchPromptForBuy(descendant, packModel)
        end
    end
end

-- The initial model scan happens before the prompt watcher was declared.
-- Hook existing prompts here as well as in DescendantAdded so packs that are
-- already on the conveyor are not missed.
for _, descendant in ipairs(workspace:GetDescendants()) do
    if descendant:IsA("ProximityPrompt") then
        local promptModel = getOwningModel(descendant)
        if promptModel and shouldWatchModel(promptModel) then
            registerConveyorContainer(promptModel)
            watchPromptForBuy(descendant, promptModel)
        end
    end
end

workspace.DescendantAdded:Connect(function(descendant)
    local model = descendant:IsA("Model")
        and descendant
        or getOwningModel(descendant)

    if descendant:IsA("Model") then
        if shouldWatchModel(descendant) then
            watchModel(descendant)
            if hasItemIdAttribute(descendant)
                or descendant:FindFirstChildWhichIsA("ProximityPrompt", true) then
                registerConveyorContainer(descendant)
                watchAllPromptsOnPack(descendant)
            end
        end
    elseif descendant:IsA("ProximityPrompt") then
        local promptModel = getOwningModel(descendant)
        if promptModel and shouldWatchModel(promptModel) then
            registerConveyorContainer(promptModel)
            watchPromptForBuy(descendant, promptModel)
        end
    elseif string.lower(descendant.Name) == "itemid"
        and descendant:IsA("ValueBase") then
        registerConveyorContainer(model)
    end

    if model then
        metadataCache[model] = nil
    end
end)

workspace.DescendantRemoving:Connect(function(descendant)
    if descendant:IsA("Model") then
        unregisterConveyorContainer(descendant)
    else
        local model = getOwningModel(descendant)
        if model then metadataCache[model] = nil end
    end
end)

-- ── Conveyor stage helpers ────────────────────────────────────
-- Returns all tracked pack records that are still in workspace.
local function getConveyorPacks()
    local packs = {}
    for model, record in pairs(conveyorState) do
        if model:IsDescendantOf(workspace) then
            -- Refresh every pass because rarity/mutation metadata can arrive
            -- after the model and ItemId have already replicated.
            record.info = getBoxInfo(model)
            -- Refresh ItemId if it wasn't available at registration time.
            if record.itemId == nil then
                local itemId = getItemId(model)
                if itemId ~= nil then
                    record.itemId = itemId
                    itemIdIndex[itemId] = model
                end
            end
            table.insert(packs, record)
        else
            unregisterConveyorContainer(model)
        end
    end
    return packs
end

-- Mark a pack as having reached the buy zone (ReachedB equivalent).
-- CONFIRMED: when the buy ProximityPrompt becomes enabled, the pack is at B
-- and is purchasable via ConveyorRE:FireServer("TryBuy", { ItemId = X }).
local function markReachedB(record)
    if record.stage == "spawned" then
        record.stage = "reachedB"
        warn(string.format(
            "[Conveyor] ItemId %s became purchasable.  pack=%s  rarity=%s  mutation=%s",
            tostring(record.itemId),
            tostring(record.info and record.info.pack),
            tostring(record.info and record.info.rarity),
            tostring(record.info and record.info.mutation)
        ))
    end
end

-- ── Pack key helpers ─────────────────────────────────────────
local function getPackKey(record)
    -- CONFIRMED: ItemId is sequential and reliable; prefer it as the key.
    if record.itemId ~= nil then
        return "id:" .. tostring(record.itemId)
    end
    return "model:" .. record.model:GetFullName()
end

local function indexPackIds(packs)
    local ids = {}
    for _, record in ipairs(packs) do
        ids[getPackKey(record)] = true
    end
    return ids
end

-- ── Diagnostic helpers ───────────────────────────────────────
local diagnosticState = {}

local function warnOnce(key, message)
    if diagnosticState[key] then return end
    diagnosticState[key] = true
    warn("[ACF] " .. message)
end

local function debugAutoBuy(message)
    if Config.AutoBuyDebug then
        warn("[ACF][AutoBuy] " .. message)
    end
end

local function describePack(record)
    if not record or not record.model then
        return "<missing pack>"
    end
    local info = record.info or {}
    return string.format(
        "model=%s  itemId=%s  pack=%s  rarity=%s  mutation=%s  stage=%s",
        record.model:GetFullName(),
        tostring(record.itemId),
        tostring(info.pack),
        tostring(info.rarity),
        tostring(info.mutation),
        tostring(record.stage)
    )
end

local function dumpPackHierarchy(record)
    if not Config.AutoBuyDebug or not record or not record.model then return end

    local key = "AutoBuy:itemid:" .. record.model:GetFullName()
    if diagnosticState[key] then return end
    diagnosticState[key] = true

    local names = {}
    for _, descendant in ipairs(record.model:GetDescendants()) do
        table.insert(names, descendant:GetFullName())
    end

    debugAutoBuy(
        "ItemId not found locally. Searched " ..
        record.model:GetFullName() ..
        " descendants:\n" ..
        table.concat(names, "\n")
    )
end

-- ── Buy prompt detection ─────────────────────────────────────
-- The buy ProximityPrompt being enabled is the client-visible indicator
-- that the pack has reached the buy zone (equivalent to ReachedB).
local function normalizePromptText(value)
    if value == nil then return "" end
    return string.lower(string.gsub(tostring(value), "^%s*(.-)%s*$", "%1"))
end

isBuyPrompt = function(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return false end
    if prompt.Enabled == false then return false end

    local promptName = normalizePromptText(prompt.Name)
    local actionText = normalizePromptText(prompt.ActionText)
    local objectText = normalizePromptText(prompt.ObjectText)

    return promptName == "buy"
        or actionText == "buy"
        or objectText == "buy"
        or string.find(promptName, "buy", 1, true) ~= nil
        or string.find(actionText, "buy", 1, true) ~= nil
        or string.find(objectText, "buy", 1, true) ~= nil
end

-- Search a model and optionally its parent for an enabled buy prompt.
-- Priority: explicit "buy" label > first enabled prompt on the pack model >
-- first enabled prompt on the parent model (in case the prompt lives one
-- level above the pack, e.g. on LocalConveyorModels).
local function findBuyPrompt(packModel)
    if not packModel then return nil end

    local function searchIn(model, onlyForPack)
        if not model then return nil, nil end
        local firstEnabled = nil
        for _, descendant in ipairs(model:GetDescendants()) do
            if descendant:IsA("ProximityPrompt") and descendant.Enabled ~= false then
                if onlyForPack and findPackContainer(descendant) ~= packModel then
                    continue
                end
                if isBuyPrompt(descendant) then
                    return descendant, nil   -- explicit match wins immediately
                end
                if not firstEnabled then
                    firstEnabled = descendant
                end
            end
        end
        return nil, firstEnabled
    end

    -- 1. Search the pack model's own descendants for an explicit buy label.
    local explicit, firstOnPack = searchIn(packModel, true)
    if explicit then return explicit end

    -- 2. Search the parent model's descendants (catches prompts one level up).
    local parent = packModel.Parent
    local explicitOnParent, firstOnParent = searchIn(parent, true)
    if explicitOnParent then return explicitOnParent end

    -- 3. No explicit label found. Fall back to the first enabled prompt:
    --    prefer one on the pack model itself; only use parent if pack has none.
    return firstOnPack or firstOnParent
end

-- ── Purchase flow ─────────────────────────────────────────────
-- CONFIRMED purchase mechanism:
--   ConveyorRE:FireServer("TryBuy", { ItemId = X })
--
-- The buy ProximityPrompt being enabled signals that the pack has reached
-- the buy zone. We use that as our ReachedB gate before firing TryBuy.
tryBuyConveyorPack = function(record)
    if not record or not record.model then return false end
    local now = os.clock()
    if record.lastBuyAttempt and now - record.lastBuyAttempt < 0.35 then
        return false
    end
    record.lastBuyAttempt = now

    -- Gate: buy ProximityPrompt must be enabled (= pack is at buy zone / ReachedB).
    local prompt = findBuyPrompt(record.model)
    if not prompt then
        debugAutoBuy("SKIP — no enabled buy prompt (not yet at B)  " .. describePack(record))
        return false
    end

    -- Mark as ReachedB if not already done, and log it.
    markReachedB(record)

    -- Refresh ItemId one last time right before purchase (it may have arrived late).
    if record.itemId == nil then
        local freshId = getItemId(record.model)
        if freshId ~= nil then
            record.itemId = freshId
            itemIdIndex[freshId] = record.model
        end
    end

    local itemId = record.itemId

    if itemId ~= nil then
        -- CONFIRMED path: ConveyorRE:FireServer("TryBuy", { ItemId = X })
        debugAutoBuy(
            "TryBuy (remote)  ItemId=" .. tostring(itemId) ..
            "  " .. describePack(record)
        )
        local ok, err = pcall(function()
            ConveyorRE:FireServer("TryBuy", { ItemId = itemId })
        end)
        if ok then
            -- A successful pcall only confirms that the client sent the
            -- request. Keep the record retryable until the server removes the
            -- pack or disables its buy prompt.
            record.stage = "buying"
            debugAutoBuy("TryBuy sent  ItemId=" .. tostring(itemId))
        else
            warn("[ACF][AutoBuy] TryBuy failed  ItemId=" .. tostring(itemId) .. "  err=" .. tostring(err))
        end
        if ok and record.model:IsDescendantOf(workspace) then
            -- Some server revisions do not accept the replicated ItemId
            -- immediately. Give the live prompt one fallback activation while
            -- it is still enabled, then let the polling loop retry normally.
            local livePrompt = findBuyPrompt(record.model)
            if livePrompt and fireproximityprompt then
                task.wait(0.12)
                if record.model:IsDescendantOf(workspace) then
                    pcall(fireproximityprompt, livePrompt)
                end
            end
        end
        return ok
    else
        -- ItemId not replicated to this client. Fall back to activating the
        -- buy ProximityPrompt directly — the server handles the rest.
        debugAutoBuy(
            "TryBuy (prompt fallback — ItemId not available)  prompt=" ..
            prompt:GetFullName() ..
            "  " .. describePack(record)
        )
        dumpPackHierarchy(record)

        if not fireproximityprompt then
            warnOnce(
                "AutoBuy:no-fireproximityprompt",
                "ItemId not available and fireproximityprompt is missing — cannot buy."
            )
            return false
        end

        local ok, err = pcall(fireproximityprompt, prompt)
        if ok then
            record.stage = "buying"
            debugAutoBuy("Prompt activated (fallback)")
        else
            warn("[ACF][AutoBuy] Prompt fallback failed: " .. tostring(err))
        end
        return ok
    end
end

-- Returns true if a card passes the current filter.
-- info = { rarity = string, mutation = string, pack = string }
passesFilter = function(info)
    info = info or {}

    local function matches(value, selected)
        return filterValueMatches(value, selected)
    end

    return matches(info.rarity,   normalizeFilterSelection(Config.SelectedRarities))
       and matches(info.mutation, normalizeFilterSelection(Config.SelectedMutations))
       and matches(info.pack,     normalizeFilterSelection(Config.SelectedPacks))
end

-- ── Loops ────────────────────────────────────────────────────

-- Anti-AFK
task.spawn(function()
    while true do
        task.wait(55)
        if Config.AntiAfk then
            VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
            task.wait(0.1)
            VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        end
    end
end)

-- Auto Spawn Pack
task.spawn(function()
    while true do
        task.wait(math.max(0.05, Config.SpawnDelay))
        if not Config.AutoSpawnPack then continue end
        if boxHandlingActive then continue end

        local previousIds
        if Config.AutoStopSpawn then
            previousIds = indexPackIds(getConveyorPacks())
        end

        local spawnBtn, _ = getPlotButtons(Config.PlotNumber)
        if not spawnBtn then
            -- Spawn button missing — try re-detecting the plot first
            local detected = autoDetectMyPlotNumber()
            if detected and detected ~= Config.PlotNumber then
                warn("[ACF] Spawn: plot " .. Config.PlotNumber
                    .. " has no spawn button; auto-detected plot " .. detected)
                setPlotNumber(detected)
                spawnBtn, _ = getPlotButtons(Config.PlotNumber)
            end
            if not spawnBtn then
                warnOnce("Spawn:no-button",
                    "Spawn button was not found for plot " ..
                    tostring(Config.PlotNumber) ..
                    ". Use 'Detect My Plot' or set the plot number manually.")
            end
        end
        fireButton(spawnBtn)

        -- Auto Stop: detect the newly spawned pack and check the filter.
        -- Runs in a background task so the spawn loop is never blocked —
        -- the next spawn fires at the configured delay without waiting for
        -- the detection to complete.
        if Config.AutoStopSpawn then
            local capturedIds = previousIds  -- close over this spawn's snapshot
            task.spawn(function()
                local spawnedRecord
                for _ = 1, 30 do
                    for _, record in ipairs(getConveyorPacks()) do
                        if not capturedIds[getPackKey(record)] then
                            spawnedRecord = record
                            break
                        end
                    end
                    if spawnedRecord then break end
                    task.wait(0.1)
                end

                if spawnedRecord and passesFilter(spawnedRecord.info) then
                    Config.AutoSpawnPack = false
                    if Rayfield and Rayfield.Flags and Rayfield.Flags["AutoSpawnPack"] then
                        Rayfield.Flags["AutoSpawnPack"]:Set(false)
                    end
                    notify("Auto Spawn Pack", "Stopped — filter match found!")
                elseif not spawnedRecord then
                    warnOnce(
                        "AutoStop:no-new-pack",
                        "Auto Stop did not detect a new conveyor pack after spawning."
                    )
                end
            end)
        end
    end
end)

-- Auto Buy Matching
-- CONFIRMED flow:
--   1. Pack spawns → registered in conveyorState with stage = "spawned".
--   2. Pack reaches buy zone → buy ProximityPrompt becomes enabled (= ReachedB).
--   3. If pack matches filter → ConveyorRE:FireServer("TryBuy", { ItemId = X }).
--   4. Pack is destroyed → removed from conveyorState.
--
-- Deduplication is by ItemId (confirmed sequential from 1). A pack remains
-- retryable after a request is sent; the server's removal of the model is the
-- success signal.
task.spawn(function()
    -- lastBuyAttempt is keyed by ItemId string for fast lookup.
    -- It throttles retries in case the pack survives after TryBuy.
    local lastBuyAttempt = {}

    while true do
        task.wait(0.25)
        if not Config.AutoBuyMatching then continue end
        if boxHandlingActive then continue end

        local packs = getConveyorPacks()
        if #packs == 0 then
            warnOnce(
                "AutoBuy:no-packs",
                "Auto Buy is enabled, but no interactive conveyor packs were detected."
            )
        end

        local now = os.clock()
        for _, record in ipairs(packs) do
            -- "buying" is intentionally not skipped: the server may reject a
            -- request while the prompt remains enabled, so retry until the
            -- pack disappears.
            if record.stage == "bought" then continue end

            if passesFilter(record.info) then
                local key = getPackKey(record)

                debugAutoBuy("Candidate " .. describePack(record))

                -- Retry quickly while the pack remains present. A request can
                -- be lost during replication, but retrying too slowly lets the
                -- pack pass the purchase zone.
                if not lastBuyAttempt[key] or now - lastBuyAttempt[key] >= 0.3 then
                    if tryBuyConveyorPack(record) then
                        lastBuyAttempt[key] = now
                    end
                end
            end
        end
    end
end)

-- ── Auto Carry Box helpers ───────────────────────────────────
-- Boxes sit on the player's own plot in workspace.  They have a "Carry"
-- ProximityPrompt while on the ground; after firing it they equip as a Tool
-- with structure Tool.Handle.Box.
--
-- findOneCarryPromptOnPlot: search ONLY the player's own plot model so we
-- never accidentally pick up boxes from other players' plots.
local function findOneCarryInteractionOnPlot()
    local plot = findPlot(Config.PlotNumber)
    if not plot then
        warnOnce("CarryBox:no-plot",
            "Auto Carry Box: could not find plot " .. tostring(Config.PlotNumber))
        return nil
    end
    for _, desc in ipairs(plot:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Enabled ~= false then
            local name   = string.lower(desc.Name)
            local action = string.lower(desc.ActionText or "")
            local obj    = string.lower(desc.ObjectText or "")
            if name == "carry"
                or action == "carry"
                or obj    == "carry"
                or string.find(name,   "carry", 1, true)
                or (string.find(name, "box", 1, true)
                    and (string.find(action, "pick", 1, true)
                        or string.find(action, "take", 1, true)
                        or string.find(action, "carry", 1, true)))
                or string.find(action, "carry", 1, true) then
                return desc
            end
        end
        if desc:IsA("ClickDetector") then
            local parentName = string.lower(desc.Parent and desc.Parent.Name or "")
            if string.find(parentName, "carry", 1, true)
                or string.find(parentName, "box", 1, true) then
                return desc
            end
        end
    end
    return nil
end

-- Backwards-compatible name used by older sections of the script.
local findOneCarryPromptOnPlot = findOneCarryInteractionOnPlot

-- findOneBoxToolInCharacter: after equipping, the box lives in Character as
-- a Tool with structure Tool.Handle.Box.  This confirms the equip worked.
local function findOneBoxToolInCharacter()
    local char = player.Character
    if not char then return nil end
    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Tool") then
            local handle = item:FindFirstChild("Handle")
            if handle and handle:FindFirstChild("Box") then
                return item
            end
        end
    end
    return nil
end

local function isBoxTool(item)
    if not item or not item:IsA("Tool") then return false end
    local handle = item:FindFirstChild("Handle")
    if handle and handle:FindFirstChild("Box") then return true end
    local name = string.lower(item.Name)
    return string.find(name, "box", 1, true) ~= nil
        and not string.find(name, "pack", 1, true)
end

-- Find the static "Sell Card Boxes!" interactable in the world.
-- Checks ProximityPrompts and ClickDetectors on all workspace parts.
local sellBoxPartCache = nil
local function findSellBoxPart()
    if sellBoxPartCache and sellBoxPartCache:IsDescendantOf(workspace) then
        return sellBoxPartCache
    end
    sellBoxPartCache = nil

    -- Inner search helper — returns the first sell interaction in a list of
    -- descendants. Checks ProximityPrompts by text first, then BasePart/Model
    -- names that contain both "sell" and "box".
    local function searchIn(descendants)
        for _, descendant in ipairs(descendants) do
            if descendant:IsA("ProximityPrompt") then
                local action = string.lower(descendant.ActionText or "")
                local obj    = string.lower(descendant.ObjectText or "")
                local name   = string.lower(descendant.Name)
                if string.find(action, "sell", 1, true)
                    or string.find(obj,    "sell", 1, true)
                    or string.find(name,   "sell", 1, true) then
                    return descendant
                end
            end
            if descendant:IsA("BasePart") or descendant:IsA("Model") then
                local name = string.lower(descendant.Name)
                if string.find(name, "sell", 1, true)
                    and string.find(name, "box", 1, true) then
                    return descendant
                end
            end
        end
        return nil
    end

    -- Always search the player's OWN plot first so we never accidentally
    -- fire another player's sell station when plots share the same workspace.
    local plot = findPlot(Config.PlotNumber)
    if plot then
        local found = searchIn(plot:GetDescendants())
        if found then
            sellBoxPartCache = found
            return found
        end
    end

    -- Fallback: global workspace scan (original behaviour, kept for edge cases
    -- where the sell station is not parented inside the plot model).
    local found = searchIn(workspace:GetDescendants())
    if found then
        sellBoxPartCache = found
    end
    return sellBoxPartCache
end

-- ── Teleport helper ─────────────────────────────────────────
-- Moves the character to within interaction range of a target position.
-- Places the character at the target's XZ position so proximity prompts
-- are always within activation distance.
local function teleportNear(targetCFrame)
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    -- Put the character at the exact XZ position of the target, keeping
    -- the character's current Y so they don't fall through the floor.
    local pos = targetCFrame.Position
    pcall(function()
        root.CFrame = CFrame.new(pos.X, root.Position.Y, pos.Z)
    end)
    task.wait(0.2)   -- the game requires a short delay after teleporting
end

-- Get the CFrame of a model or part (PrimaryPart → geometric centre → origin).
local function getCFrameOf(target)
    if target:IsA("Model") then
        if target.PrimaryPart then
            return target.PrimaryPart.CFrame
        end
        -- Fall back to geometric centre
        local ok, cf = pcall(function() return target:GetBoundingBox() end)
        if ok then return cf end
        return target:FindFirstChildOfClass("BasePart") and
               target:FindFirstChildOfClass("BasePart").CFrame or CFrame.new()
    end
    return target.CFrame
end

-- Helper: teleport to sell station and fire its interaction.
local function doSellAtStation()
    local part = findSellBoxPart()
    if not part then
        warnOnce("SellBox:not-found",
            "Auto Sell Box: could not find 'Sell Card Boxes!' part in workspace.")
        return false
    end
    local target = part
    if part:IsA("ProximityPrompt") or part:IsA("ClickDetector") then
        target = part.Parent
    end
    if not target then return false end
    teleportNear(getCFrameOf(target))
    task.wait(0.1)
    if part:IsA("ProximityPrompt") then
        return firePrompt(part)
    elseif part:IsA("ClickDetector") then
        return fireClickDetector(part)
    end
    local prompt = part:FindFirstChildOfClass("ProximityPrompt")
                or part:FindFirstChild("ProximityPrompt", true)
    if prompt then return firePrompt(prompt) end
    local click = part:FindFirstChildOfClass("ClickDetector")
                or part:FindFirstChild("ClickDetector", true)
    if click then return fireClickDetector(click) end
    return fireButton(part)
end

-- Auto Carry + Auto Sell loop.
-- ONE box per interval so the delay slider is always respected:
--   1. Save position.
--   2. If a box is already equipped in the character, sell it first.
--   3. If a box is in the backpack, sell the first one (next cycle handles the rest).
--   4. Otherwise (AutoCarryBox): pick up ONE box from the player's own plot and sell it.
--   5. Teleport back.
task.spawn(function()
    while true do
        task.wait(math.max(1, Config.AutoSellDelay))
        if not Config.AutoCarryBox and not Config.AutoSellBox then continue end
        if boxHandlingActive then continue end

        -- Box interactions temporarily take priority over conveyor work.
        boxHandlingActive = true

        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then
            boxHandlingActive = false
            continue
        end

        -- 1. Save position so we can return here at the end.
        local savedCFrame = root.CFrame

        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            boxHandlingActive = false
            continue
        end

        -- Helper: collect all box Tools currently in backpack.
        local function getBackpackBoxes()
            local boxes = {}
            local backpack = player:FindFirstChild("Backpack")
            if backpack then
                for _, item in ipairs(backpack:GetChildren()) do
                    if isBoxTool(item) then table.insert(boxes, item) end
                end
            end
            return boxes
        end

        local function getCharacterBox()
            return isBoxTool(char:FindFirstChildOfClass("Tool"))
                and char:FindFirstChildOfClass("Tool") or nil
        end

        -- Helper: equip one box and sell it, then unequip.
        local function equipAndSell(boxTool)
            pcall(function() humanoid:EquipTool(boxTool) end)
            task.wait(0.3)
            if Config.AutoSellBox then
                doSellAtStation()
                task.wait(0.3)
            end
            pcall(function() humanoid:UnequipTools() end)
            task.wait(0.1)
        end

        -- 2. If a box is already equipped in the character, sell it first.
        local charBox = getCharacterBox()
        if charBox then
            if Config.AutoSellBox then
                doSellAtStation()
                task.wait(0.3)
            end
            pcall(function() humanoid:UnequipTools() end)
            task.wait(0.1)
        end

        -- 3. Sell ONE box from backpack if any exist.
        --    Remaining boxes are handled in subsequent cycles so the delay
        --    is always honoured between each sell operation.
        local existingBoxes = getBackpackBoxes()
        if #existingBoxes > 0 then
            local boxTool = existingBoxes[1]
            if boxTool and boxTool.Parent then
                equipAndSell(boxTool)
            end

        elseif Config.AutoCarryBox then
            -- 4. No backpack box → carry ONE box from the player's own plot.
            local carryInteraction = findOneCarryInteractionOnPlot()
            if carryInteraction then
                local interactParent = carryInteraction.Parent
                if interactParent then
                    teleportNear(getCFrameOf(interactParent))
                end

                if carryInteraction:IsA("ProximityPrompt") then
                    firePrompt(carryInteraction)
                elseif carryInteraction:IsA("ClickDetector") then
                    fireClickDetector(carryInteraction)
                end
                task.wait(0.4)

                -- Confirm the equip then sell.
                local acquired = getCharacterBox()
                if acquired then
                    if Config.AutoSellBox then
                        doSellAtStation()
                        task.wait(0.3)
                    end
                    pcall(function() humanoid:UnequipTools() end)
                    task.wait(0.1)
                else
                    -- Pickup may have landed in the backpack instead.
                    local newBoxes = getBackpackBoxes()
                    if #newBoxes > 0 then
                        local b = newBoxes[1]
                        if b and b.Parent then equipAndSell(b) end
                    end
                end
            end
        end

        -- 5. Return to the original position.
        local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if r then pcall(function() r.CFrame = savedCFrame end) end

        boxHandlingActive = false
    end
end)

-- ── Card Slot helpers ────────────────────────────────────────
-- Slots are named CardSlot1–CardSlot30 inside the player's plot.
-- The first ten slots are direct children of Plot_N0. The remaining slots
-- are split across the two upper-floor containers used by the game:
-- TOP = CardSlot11..CardSlot20, TOP2 = CardSlot21..CardSlot30.

-- Forward declarations used before their definitions.
local findSlotButton
local slotIsOccupied
local findCardSlot
local getCardSlotIndex

-- Auto Upgrade
task.spawn(function()
    while true do
        local delay = math.max(0.05, Config.UpgradeDelay)
        task.wait(delay)
        if not Config.AutoUpgrade then continue end

        local plot = findPlot(Config.PlotNumber)
        if not plot then continue end

        for slotIndex = 1, 30 do
            local slot = findCardSlot(plot, slotIndex)
            if not slot then continue end
            if not slotIsOccupied(slot) then continue end

            local level = slot:FindFirstChild("CardLevel", true)
            if level and level:IsA("ValueBase")
                and tonumber(level.Value) >= MAX_CARD_LEVEL then
                continue
            end

            fireRemote("CardSlotRE", "UpgradeCard", {
                SlotIndex = slotIndex,
            })
            task.wait(delay)
        end
    end
end)

-- Auto Sell
task.spawn(function()
    while true do
        task.wait(0.75)
        if not Config.AutoSell then continue end
        local backpack = player:FindFirstChild("Backpack")
        if not backpack then continue end
        for _, item in ipairs(backpack:GetChildren()) do
            local lvl = item:FindFirstChild("CardLevel")
            if lvl and lvl.Value >= MAX_CARD_LEVEL then
                fireRemote("CardSlotRE", "Sell", item.Name)
                task.wait(0.1)
            end
        end
    end
end)

-- Auto Potions
task.spawn(function()
    while true do
        task.wait(1)
        if not Config.AutoPotion then continue end
        local backpack = player:FindFirstChild("Backpack")
        if not backpack then continue end

        -- Do not stack a second potion over an active one. The game exposes
        -- active effects as attributes/ValueBases in different releases, so
        -- check all replicated player/character effect containers.
        local active = nil
        local function inspect(container, excluded)
            if not container then return end
            for _, attributeName in ipairs({
                "ActivePotion", "ActivePotionName", "PotionActive",
                "ActiveEffect", "ActiveEffectName",
            }) do
                local value = container:GetAttribute(attributeName)
                if value ~= nil and value ~= false and tostring(value) ~= "" then
                    active = tostring(value)
                    return
                end
            end
            for _, desc in ipairs(container:GetDescendants()) do
                if excluded and desc:IsDescendantOf(excluded) then continue end
                local name = tostring(desc.Name)
                local key = string.lower(name)
                if string.find(key, "potion", 1, true)
                    or string.find(key, "boost", 1, true)
                    or string.find(key, "effect", 1, true) then
                    if desc:IsA("ValueBase") then
                        local value = desc.Value
                        if value == true or (tonumber(value) or 0) > 0
                            or (type(value) == "string" and value ~= "") then
                            active = name
                            return
                        end
                    elseif desc:GetAttribute("Active") == true
                        or desc:GetAttribute("Enabled") == true then
                        active = name
                        return
                    end
                end
            end
        end
        inspect(player, backpack)
        if not active then inspect(player.Character) end
        if active then continue end

        local selected = Config.SelectedPotions
        for _, potion in ipairs(POTIONS) do
            local allowed = selectionIncludes(selected, potion)
            if allowed and backpack:FindFirstChild(potion) then
                if fireRemote("UseItem", potion) then
                    -- Give the server time to replicate the active effect
                    -- before the next poll can choose another potion.
                    task.wait(0.75)
                end
                break
            end
        end
    end
end)

-- Auto Claim Playtime
task.spawn(function()
    local nextStateRequest = 0
    while true do
        task.wait(0.5)
        if not Config.AutoClaimPlaytime or not PlayTimeRewardRE then continue end
        local now = os.clock()
        if not playtimeStateReceived or now >= nextStateRequest then
            pcall(function() PlayTimeRewardRE:FireServer("RequestState") end)
            nextStateRequest = now + 10
        end
        for rewardIndex = 1, 12 do
            if playtimeReadyRewards[rewardIndex] then
                playtimeReadyRewards[rewardIndex] = nil
                pcall(function()
                    PlayTimeRewardRE:FireServer("ClaimReward", {
                        RewardIndex = rewardIndex,
                    })
                end)
                break
            end
        end
    end
end)

-- Daily rewards use a separate remote and the client confirms the exact
-- action is simply "Claim" (the current day is selected server-side).
task.spawn(function()
    if DailyRewardRE then
        pcall(function() DailyRewardRE:FireServer("RequestState") end)
    end
    while true do
        task.wait(5)
        if Config.AutoClaimDaily and DailyRewardRE then
            pcall(function() DailyRewardRE:FireServer("Claim") end)
        end
    end
end)

-- Cash upgrades and boosts share UpgradesRE. The base upgrade id is confirmed
-- by the supplied client trace: UpgradesRE:FireServer("BuyCash", {Id="base"}).
task.spawn(function()
    while true do
        task.wait(3)
        if UpgradesRE and Config.AutoBuyBoost then
            for _, boost in ipairs(BOOSTS) do
                local chosen = false
                chosen = selectionIncludes(Config.SelectedBoosts, boost.label)
                if chosen then
                    pcall(function()
                        UpgradesRE:FireServer("BuyCash", { Id = boost.id })
                    end)
                    task.wait(0.2)
                end
            end
        end
    end
end)

-- Auto Trait Roll
task.spawn(function()
    while true do
        task.wait(0.25)
        if Config.AutoTraitRoll then fireRemote("TraitRollRE", "Roll") end
    end
end)

-- ── Card Slot helper implementations ────────────────────────
findCardSlot = function(plot, slotIndex)
    if not plot or not slotIndex then return nil end
    local name = "CardSlot" .. tostring(slotIndex)
    local container = plot
    if slotIndex >= 11 and slotIndex <= 20 then
        container = plot:FindFirstChild("TOP")
    elseif slotIndex >= 21 and slotIndex <= 30 then
        container = plot:FindFirstChild("TOP2")
    end
    local slot = container and container:FindFirstChild(name)
    if slot then return slot end

    -- Keep a recursive fallback for older map revisions, but never use it
    -- as the primary lookup because duplicate names can exist on the floors.
    return plot:FindFirstChild(name, true)
end

getCardSlotIndex = function(slot)
    if not slot then return nil end
    local upgradePart = slot:FindFirstChild("UpgradePart")
    local attributeIndex = upgradePart and tonumber(
        upgradePart:GetAttribute("SlotIndex")
    )
    if attributeIndex then return attributeIndex end
    return tonumber(string.match(slot.Name, "CardSlot(%d+)"))
end

local function getAllCardSlots()
    local plot = findPlot(Config.PlotNumber)
    if not plot then return {} end
    local slots = {}
    for i = 1, 30 do
        local slot = findCardSlot(plot, i)
        if slot then table.insert(slots, slot) end
    end
    return slots
end

-- Find a ClickDetector or ProximityPrompt for a named button
-- ("Place", "Remove", "Open") on or inside a slot model.
findSlotButton = function(slotModel, buttonName)
    if not slotModel then return nil end
    local lname = string.lower(buttonName)
    for _, desc in ipairs(slotModel:GetDescendants()) do
        -- Match by part/model name
        if string.find(string.lower(desc.Name), lname, 1, true) then
            local cd = desc:FindFirstChildOfClass("ClickDetector")
                    or desc:FindFirstChildOfClass("ProximityPrompt")
            if cd then return cd end
            if desc:IsA("ClickDetector") or desc:IsA("ProximityPrompt") then
                return desc
            end
        end
        -- Match ProximityPrompt by ActionText / ObjectText
        if desc:IsA("ProximityPrompt") then
            local action = string.lower(desc.ActionText or "")
            local obj    = string.lower(desc.ObjectText or "")
            if string.find(action, lname, 1, true)
                or string.find(obj, lname, 1, true) then
                return desc
            end
        end
    end
    return nil
end

local function fireSlotButton(btn)
    if not btn then return false end
    if btn:IsA("ClickDetector") then
        return fireClickDetector(btn)
    elseif btn:IsA("ProximityPrompt") then
        return firePrompt(btn)
    end
    return false
end

local function findSlotInteraction(slotModel, names)
    for _, name in ipairs(names) do
        local interaction = findSlotButton(slotModel, name)
        if interaction then return interaction end
    end
    return nil
end

-- Returns true if a slot has a TextLabel/Button containing "skip"
-- (pack on cooldown — do not remove or place here).
local function slotIsOnCooldown(slotModel)
    if not slotModel then return false end
    for _, desc in ipairs(slotModel:GetDescendants()) do
        if desc:IsA("TextLabel") or desc:IsA("TextButton") then
            if string.find(string.lower(desc.Text or ""), "skip", 1, true) then
                return true
            end
        end
    end
    return false
end

-- Returns true if a slot is occupied (has a Remove button).
slotIsOccupied = function(slotModel)
    if findSlotButton(slotModel, "Remove") ~= nil then return true end
    for _, desc in ipairs(slotModel:GetDescendants()) do
        local name = string.lower(desc.Name)
        if name == "placedcard" or name == "cardname"
            or name == "cardlevel" or name == "packname" then
            return true
        end
        if desc:GetAttribute("CardName") ~= nil
            or desc:GetAttribute("PackName") ~= nil
            or desc:GetAttribute("ItemId") ~= nil then
            return true
        end
    end
    return false
end

-- Pack Tools in backpack that pass the current filter.
local function getFilteredPacksInBackpack()
    local result = {}
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return result end
    for _, item in ipairs(backpack:GetChildren()) do
        if not item:IsA("Tool") then continue end
        -- Skip box tools
        local handle = item:FindFirstChild("Handle")
        if handle and handle:FindFirstChild("Box") then continue end
        -- Must look like a pack (name contains a known pack name)
        local lname = string.lower(item.Name)
        local isPack = false
        for _, packName in ipairs(PACKS) do
            if string.find(lname, string.lower(packName), 1, true) then
                isPack = true ; break
            end
        end
        if not isPack then continue end
        -- Apply filter (reuse same filter as Auto Buy)
        local info = {
            pack     = item.Name,
            rarity   = readBoxValue(item, { "Rarity", "rarity" }),
            mutation = readBoxValue(item, {
                "Mutation", "MutationName", "mutation",
            }),
        }
        if passesFilter(info) then table.insert(result, item) end
    end
    return result
end

-- Read the card's currency value from the common replicated shapes used by
-- the game.  Attributes are fastest, then ValueBase descendants.
local function getCardCurrencyValue(item)
    local attributeNames = {
        "CurrencyValue", "Currency", "Income", "CashPerSecond",
        "Cash", "Value", "Coins", "Money",
    }
    for _, name in ipairs(attributeNames) do
        local value = tonumber(item:GetAttribute(name))
        if value then return value end
    end

    for _, descendant in ipairs(item:GetDescendants()) do
        local name = string.lower(descendant.Name)
        if descendant:IsA("ValueBase")
            and (name == "currencyvalue" or name == "currency"
                or name == "income" or name == "cashpersecond"
                or name == "cash" or name == "value" or name == "coins"
                or name == "money") then
            local value = tonumber(descendant.Value)
            if value then return value end
        end
    end

    return 0
end

local function restoreCharacterPosition(savedCFrame)
    if not savedCFrame then return end
    local root = player.Character
        and player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    pcall(function()
        root.CFrame = savedCFrame
    end)
    -- Re-apply once after the character settles so the teleport is not lost
    -- when the game updates the root position on the same frame.
    task.wait(0.1)
    root = player.Character
        and player.Character:FindFirstChild("HumanoidRootPart")
    if root then
        pcall(function() root.CFrame = savedCFrame end)
    end
end

local function getCardInfo(item)
    local rarity = readBoxValue(item, { "Rarity", "CardRarity", "rarity" })
    local mutation = readBoxValue(item, {
        "Mutation", "MutationName", "CardMutation", "mutation",
    })

    return {
        rarity = rarity,
        mutation = mutation,
    }
end

-- Card Tools sorted by strongest mutation, then strongest rarity, then
-- highest currency value. MUTATIONS and RARITIES are ordered weakest to
-- strongest from top to bottom.
local function getSortedCardsInBackpack()
    local result = {}
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return result end
    for _, item in ipairs(backpack:GetChildren()) do
        if not item:IsA("Tool") then continue end
        -- Skip box tools
        local handle = item:FindFirstChild("Handle")
        if handle and handle:FindFirstChild("Box") then continue end
        -- Skip pack tools
        local lname = string.lower(item.Name)
        local isPack = false
        for _, packName in ipairs(PACKS) do
            if string.find(lname, string.lower(packName), 1, true) then
                isPack = true ; break
            end
        end
        if isPack then continue end
        -- Must have CardLevel to be a card
        if not item:FindFirstChild("CardLevel")
            and item:GetAttribute("CardLevel") == nil then
            continue
        end
        local info = getCardInfo(item)
        table.insert(result, {
            tool = item,
            rarityRank = RARITY_RANK[normalizeFilterValue(info.rarity)] or 0,
            mutationRank = MUTATION_RANK[normalizeFilterValue(info.mutation)] or 0,
            currencyValue = getCardCurrencyValue(item),
            level = tonumber(item:GetAttribute("CardLevel"))
                or tonumber(item:FindFirstChild("CardLevel")
                    and item.CardLevel.Value) or 0,
        })
    end
    table.sort(result, function(a, b)
        if a.mutationRank ~= b.mutationRank then
            return a.mutationRank > b.mutationRank
        end
        if a.rarityRank ~= b.rarityRank then
            return a.rarityRank > b.rarityRank
        end
        if a.level ~= b.level then
            return a.level > b.level
        end
        return a.currencyValue > b.currencyValue
    end)
    return result
end

-- ── Auto Place Pack loop ──────────────────────────────────────
task.spawn(function()
    while true do
        task.wait(1)
        if not Config.AutoPlacePack then continue end

        local char     = player.Character
        local root     = char and char:FindFirstChild("HumanoidRootPart")
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if not humanoid or not root then continue end

        local savedCFrame = root.CFrame
        local slots = getAllCardSlots()
        for _, slot in ipairs(slots) do
            if not Config.AutoPlacePack then break end
            if slotIsOccupied(slot) then continue end

            local packs = getFilteredPacksInBackpack()
            if #packs == 0 then break end

            local pack = packs[1]
            pcall(function() humanoid:EquipTool(pack) end)
            -- EquipTool is asynchronous. On slower/tablet clients the tool
            -- may still be in Backpack when the place interaction is fired.
            for _ = 1, 12 do
                if pack.Parent == char then break end
                task.wait(0.1)
            end
            teleportNear(getCFrameOf(slot))
            local btn = findSlotInteraction(slot, { "Place", "Insert", "Add" })
            local fired = false
            if btn then
                fired = fireSlotButton(btn)
            end

            -- Some revisions render the place control but handle it through
            -- the slot remote instead of a detector/prompt.
            if not fired then
                local slotIndex = getCardSlotIndex(slot)
                local cardSlotRE = findRemote("CardSlotRE")
                if slotIndex and cardSlotRE then
                    fired = fireRemote("CardSlotRE", "Place", {
                        SlotIndex = slotIndex,
                        Item = pack.Name,
                    })
                end
            end
            if fired then
                task.wait(math.max(0.5, Config.CardActionDelay))
            else
                warnOnce("AutoPlace:no-interaction",
                    "Auto Place Pack: no place interaction was found for "
                    .. tostring(slot.Name) .. ".")
            end
            pcall(function() humanoid:UnequipTools() end)
            task.wait(0.1)
        end

        local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if r then pcall(function() r.CFrame = savedCFrame end) end
    end
end)

-- ── Auto Open Pack loop ───────────────────────────────────────
task.spawn(function()
    while true do
        task.wait(2)
        if not Config.AutoOpenPack then continue end

        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then continue end

        local savedCFrame = root.CFrame
        local slots = getAllCardSlots()
        for _, slot in ipairs(slots) do
            if not Config.AutoOpenPack then break end
            if slotIsOnCooldown(slot) then continue end
            local btn = findSlotButton(slot, "Open")
            if not btn then continue end
            teleportNear(getCFrameOf(slot))
            fireSlotButton(btn)
            task.wait(Config.CardActionDelay)
        end

        local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if r then pcall(function() r.CFrame = savedCFrame end) end
    end
end)

-- ── Equip Best Card (called by button) ───────────────────────
-- Removes all non-cooldown cards from slots, then places the highest-income
-- cards from backpack into the now-empty slots.
doEquipBestCards = function(slotLimit)
    local char     = player.Character
    local root     = char and char:FindFirstChild("HumanoidRootPart")
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not humanoid or not root then return end

    local savedCFrame = root.CFrame

    -- Step 1: remove all cards (skip cooldown slots).
    local slots = getAllCardSlots()
    for _, slot in ipairs(slots) do
        local slotIndex = getCardSlotIndex(slot)
        if not slotIndex then continue end
        if slotLimit and slotIndex > slotLimit then continue end
        if slotIsOnCooldown(slot) then continue end
        local removeBtn = findSlotButton(slot, "Remove")
        if not removeBtn then continue end
        teleportNear(getCFrameOf(slot))
        fireSlotButton(removeBtn)
        task.wait(CARD_REMOVAL_DELAY)
    end
    task.wait(Config.CardActionDelay)

    -- Step 2: place best cards into empty slots.
    local bestCards = getSortedCardsInBackpack()
    local cardIdx   = 1
    slots = getAllCardSlots()
    for _, slot in ipairs(slots) do
        local slotIndex = getCardSlotIndex(slot)
        if not slotIndex then continue end
        if slotLimit and slotIndex > slotLimit then continue end
        if cardIdx > #bestCards then break end
        if slotIsOccupied(slot) then continue end
        local card = bestCards[cardIdx].tool
        pcall(function() humanoid:EquipTool(card) end)
        task.wait(Config.CardActionDelay)
        teleportNear(getCFrameOf(slot))
        local placeBtn = findSlotButton(slot, "Place")
        if placeBtn then
            fireSlotButton(placeBtn)
            task.wait(Config.CardActionDelay)
            -- Confirm the slot updated before moving to the next card. A
            -- second attempt handles the occasional delayed Place response.
            if not slotIsOccupied(slot) then
                local retryPlaceBtn = findSlotButton(slot, "Place")
                if retryPlaceBtn then
                    fireSlotButton(retryPlaceBtn)
                    task.wait(CARD_REMOVAL_DELAY)
                end
            end
            if slotIsOccupied(slot) then
                cardIdx = cardIdx + 1
            end
        end
        pcall(function() humanoid:UnequipTools() end)
        task.wait(0.1)
    end

    -- Return to original position.
    restoreCharacterPosition(savedCFrame)
    local placedCount = cardIdx - 1
    notify("Equip Best Card", "Done! Placed " .. placedCount .. " card(s).")
    return placedCount
end

-- Remove cards from the player's plot slots. The first four slots are the
-- slots needed by the combat modes; the full button removes every card.
removeAllCards = function(slotLimit)
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return 0 end

    local savedCFrame = root.CFrame
    local removed = 0
    for _, slot in ipairs(getAllCardSlots()) do
        local slotIndex = getCardSlotIndex(slot)
        if not slotIndex then continue end
        if slotLimit and slotIndex > slotLimit then continue end
        if slotIsOnCooldown(slot) then continue end
        local removeBtn = findSlotButton(slot, "Remove")
        if not removeBtn then continue end
        teleportNear(getCFrameOf(slot))
        if fireSlotButton(removeBtn) then
            removed += 1
            task.wait(CARD_REMOVAL_DELAY)
        end
    end

    restoreCharacterPosition(savedCFrame)
    return removed
end

removeFirstFourCardSlots = function()
    return removeAllCards(4)
end

-- ── Combat GUI helpers ───────────────────────────────────────
local function findGuiByName(root, wantedName)
    if not root then return nil end
    if root.Name == wantedName then return root end
    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant.Name == wantedName then
            return descendant
        end
    end
    return nil
end

local function getCombatGui(mode)
    local guiMid = playerGui:FindFirstChild("GuiMid")
    local candidates = {
        InfinityTower = { "InfinityTower", "InfinityTowerFrame" },
        BossRaid = { "BossRaid", "BossRaidFrame" },
        HideBattle = { "HideBattle" },
        HideBattleBoss = { "HideBattleBoss" },
    }
    local root
    for _, name in ipairs(candidates[mode] or { mode }) do
        root = guiMid and guiMid:FindFirstChild(name, true)
        if root then break end
        root = playerGui:FindFirstChild(name, true)
        if root then break end
    end
    return root
end

clickGuiButton = function(button)
    if not button or not button:IsA("GuiButton") then return false end
    -- Infinity Tower keeps its team controls mounted while the panel is
    -- hidden.  Try the signal first so EQUIPEBEST still runs in that state.
    if firesignal then
        local ok = pcall(firesignal, button.MouseButton1Click)
        if ok then return true end
    end
    if button:IsA("GuiObject") and not button.Visible then return false end
    return pcall(function() button:Activate() end)
end

local function clickCombatButton(mode, names)
    local root = getCombatGui(mode)
    if root then
        for _, name in ipairs(names) do
            local button = findGuiByName(root, name)
            if button and clickGuiButton(button) then
                return true
            end
        end
    end

    -- Wrapper names vary between game revisions. Search the complete GUI as
    -- a fallback instead of silently skipping the tower team button.
    for _, name in ipairs(names) do
        local button = findGuiByName(playerGui, name)
        if button and clickGuiButton(button) then
            return true
        end
    end
    return false
end

local function selectRaidDifficulty(difficulty)
    local root = getCombatGui("BossRaid")
    if not root then return false end

    local difficultyFrame = findGuiByName(root, "DifficultyFrame") or root
    local scrolling = findGuiByName(difficultyFrame, "ScrollingFrameDifficulty")
        or difficultyFrame
    local choice = scrolling:FindFirstChild(tostring(difficulty))
    if not choice then
        choice = findGuiByName(scrolling, tostring(difficulty))
    end
    if not choice then return false end

    local button = findGuiByName(choice, "FrameButton") or choice
    return clickGuiButton(button)
end

local function isCombatActive()
    return player:GetAttribute("InfinityTowerInBattle") == true
        or player:GetAttribute("BossRaidInBattle") == true
end

local function getRaidDifficultyOptions()
    local options = {}
    if BossRaidConfig and type(BossRaidConfig.DifficultyOrder) == "table" then
        for _, difficulty in ipairs(BossRaidConfig.DifficultyOrder) do
            table.insert(options, tostring(difficulty))
        end
    end

    if #options == 0 then
        local root = getCombatGui("BossRaid")
        local frame = root and (findGuiByName(root, "DifficultyFrame") or root)
        if frame then
            for _, child in ipairs(frame:GetChildren()) do
                if child:IsA("GuiObject")
                    and child.Name ~= "ScrollingFrameDifficulty" then
                    table.insert(options, child.Name)
                end
            end
        end
    end

    if #options == 0 then
        options = { "Normal" }
    end
    return options
end

-- Keep the user-facing selector stable even if BossRaidConfig has not
-- replicated yet when this script starts.
local raidDifficultyOptions = { "Easy", "Medium", "Hard", "Nightmare" }
local raidDifficultySet = {}
for _, difficulty in ipairs(raidDifficultyOptions) do
    raidDifficultySet[difficulty] = true
end
local completedRaidDifficulties = {}

local function normalizeRaidDifficulties(value)
    local selected = {}
    local selectedSet = {}
    local values = type(value) == "table" and value or { value }
    for _, difficulty in ipairs(values) do
        difficulty = tostring(difficulty or "")
        if difficulty ~= "" and not selectedSet[difficulty] then
            table.insert(selected, difficulty)
            selectedSet[difficulty] = true
        end
    end
    return selected
end

-- Sort the selected difficulties in the canonical order so the loop always
-- processes them Easy → Medium → Hard → Nightmare regardless of the order
-- even if the UI returns selections in the order they were clicked.
local function getSelectedRaidDifficulties()
    local selected = normalizeRaidDifficulties(Config.RaidDifficulties)
    local selectedSet = {}
    for _, difficulty in ipairs(selected) do
        selectedSet[difficulty] = true
    end

    local ordered = {}
    for _, difficulty in ipairs(raidDifficultyOptions) do
        if selectedSet[difficulty] then
            table.insert(ordered, difficulty)
        end
    end
    return ordered
end

local function getNextRaidDifficulty()
    for _, difficulty in ipairs(getSelectedRaidDifficulties()) do
        if not completedRaidDifficulties[difficulty] then
            return difficulty
        end
    end
    return nil
end

local function clearCompletedRaidDifficulties()
    for difficulty in pairs(completedRaidDifficulties) do
        completedRaidDifficulties[difficulty] = nil
    end
end

local function getRaidRequirement(difficulty)
    if not BossRaidConfig or not BossRaidConfig.GetBossStats then
        return nil
    end
    if currentRaidBossId == "" then return nil end
    local ok, stats = pcall(
        BossRaidConfig.GetBossStats,
        currentRaidBossId,
        difficulty
    )
    if ok and type(stats) == "table" then
        return tonumber(stats.ReferenceDamage)
    end
    return nil
end

-- The game config can change with updates, but these are the player-facing
-- per-card requirements requested for the four raid difficulties.
local RAID_DIFFICULTY_INFO = {
    Easy = {
        damage = "1.3B",
        description = "At least 1.3B damage per card.",
    },
    Medium = {
        damage = "24.4Qn",
        description = "At least 24.4Qn damage per card.",
    },
    Hard = {
        damage = "4.7O",
        description = "At least 4.7O damage per card.",
    },
    Nightmare = {
        damage = "13.1O",
        description = "At least 13.1O damage per card.",
    },
}

local raidInfoParagraph
local raidTimerText = "Searching for Boss Raid timer..."

local function getRaidDifficultyInfo(difficulty)
    local wanted = string.lower(tostring(difficulty or ""))
    for name, info in pairs(RAID_DIFFICULTY_INFO) do
        if string.lower(name) == wanted then
            return info
        end
    end
    return nil
end

local function updateRaidInfoDisplay(difficulties)
    if not raidInfoParagraph or not raidInfoParagraph.Set then return end

    -- Use the fixed difficulty order for the description even when the
    -- multi-select values arrive in the order they were clicked.
    local selected = getSelectedRaidDifficulties()

    local lines = {}
    for _, difficulty in ipairs(selected) do
        local selectedInfo = getRaidDifficultyInfo(difficulty)
        if selectedInfo then
            table.insert(
                lines,
                difficulty .. " - " .. selectedInfo.damage
                    .. " Damage per card"
            )
        end
    end
    table.insert(lines, "Timer: " .. raidTimerText)

    pcall(function()
        raidInfoParagraph:Set({
            Title = "Boss Raid",
            Content = table.concat(lines, "\n"),
        })
    end)
end

local function showRaidRequirement(difficulties)
    local selected = getSelectedRaidDifficulties()
    notify(
        "Boss Raid Difficulty",
        "Selected " .. table.concat(selected, ", ") .. "."
    )
    updateRaidInfoDisplay(selected)
end

if BossRaidRE then
    BossRaidRE.OnClientEvent:Connect(function(eventName, payload)
        if eventName == "State" and type(payload) == "table" then
            currentRaidBossId = tostring(payload.BossId or "")
        end
    end)
    -- The game client requests this state once when its own UI loads. Request
    -- it again so the difficulty helper also works when this script is loaded
    -- after the Boss Raid GUI.
    pcall(function() BossRaidRE:FireServer("RequestState") end)
end

local function readRaidTimerText(timer)
    if not timer then return nil end

    local function read(instance)
        if instance:IsA("TextLabel") or instance:IsA("TextButton")
            or instance:IsA("TextBox") then
            local text = tostring(instance.Text or "")
            if text ~= "" then return text end
        elseif instance:IsA("ValueBase") then
            return tostring(instance.Value)
        end
        return nil
    end

    local direct = read(timer)
    if direct then return direct end

    for _, attributeName in ipairs({
        "Text", "Timer", "Time", "TimeLeft", "TimeRemaining",
    }) do
        local value = timer:GetAttribute(attributeName)
        if value ~= nil then return tostring(value) end
    end

    for _, descendant in ipairs(timer:GetDescendants()) do
        local value = read(descendant)
        if value then return value end
    end
    return nil
end

local function findBossRaidTimer()
    local bossRaidModel = workspace:FindFirstChild("BossRaidModel", true)
    if not bossRaidModel then
        bossRaidModel = playerGui:FindFirstChild("BossRaidModel", true)
    end
    return bossRaidModel and bossRaidModel:FindFirstChild("Timer", true)
end

local function isBossRaidOpen()
    local timer = findBossRaidTimer()
    local text = readRaidTimerText(timer)
    if not text then return false end

    local normalized = string.lower(text)
    -- The timer has two states: "Open in ..." while closed and "End in ..."
    -- while the raid is available. Only the latter is allowed to start.
    return string.find(normalized, "end in", 1, true) ~= nil
end

task.spawn(function()
    while true do
        task.wait(0.5)
        local timer = findBossRaidTimer()
        local text = readRaidTimerText(timer)
        if text and text ~= "" then
            raidTimerText = text
        elseif timer then
            raidTimerText = "Timer found, waiting for countdown..."
        else
            raidTimerText = "Boss Raid is currently unavailable"
        end
        updateRaidInfoDisplay(Config.RaidDifficulties)
    end
end)

local function clickBackpackEquipBest()
    -- Use the synchronous slot flow instead of only clicking the Backpack
    -- button. This ensures all removals and placements finish before combat
    -- starts, and doEquipBestCards restores the saved character position.
    return doEquipBestCards(4) ~= nil
end

local function equipBestCardsWithRetry()
    for _ = 1, 2 do
        local placed = doEquipBestCards(4)
        if placed and placed > 0 then
            return true
        end
        task.wait(CARD_REMOVAL_DELAY)
    end
    return false
end

local function finishAutoRaidIfComplete()
    if getNextRaidDifficulty() then return false end
    Config.AutoRaid = false
    if Rayfield and Rayfield.Flags and Rayfield.Flags["AutoRaid"] then
        pcall(function()
            Rayfield.Flags["AutoRaid"]:Set(false)
        end)
    end
end

local function waitForBossRaidConfirmation()
    -- The server can set BossRaidInBattle shortly after the start click.
    -- Wait for that confirmation before releasing the combat lock and
    -- disabling the one-shot toggle.
    for _ = 1, 20 do
        if player:GetAttribute("BossRaidInBattle") == true then
            return true
        end
        task.wait(0.15)
    end
    return false
end

startCombatBattle = function(mode, equipBest, hideBattle, difficulty)
    if mode == "BossRaid" and not isBossRaidOpen() then
        return false
    end

    if mode == "BossRaid"
        and player:GetAttribute("InfinityTowerInBattle") == true then
        return false
    end
    if isCombatActive() then return false end

    -- Infinity Tower's client uses EQUIPEBEST to populate its internal
    -- four-card team. Always invoke it for Auto Infinity Tower, even if the
    -- optional legacy equip toggle is off.
    if equipBest or mode == "InfinityTower" then
        local names = mode == "BossRaid"
            and { "EQUIPBEST", "EquipBest", "EQUIPEBEST" }
            or { "EQUIPEBEST", "EQUIPBEST", "EquipBest" }
        clickCombatButton(mode, names)
        task.wait(0.5)
    end

    local raidDifficulty
    if mode == "BossRaid" then
        raidDifficulty = difficulty or getNextRaidDifficulty()
        if not raidDifficulty then return false end
        selectRaidDifficulty(raidDifficulty)
        task.wait(0.25)
    end

    local started = clickCombatButton(mode, { "BATTLE", "Battle" })
    if not started then return false end

    if mode == "BossRaid" then
        if waitForBossRaidConfirmation() then
            completedRaidDifficulties[raidDifficulty] = true
            finishAutoRaidIfComplete()
        else
            return false
        end
    else
        task.wait(0.75)
    end

    if hideBattle then
        clickCombatButton(
            mode == "BossRaid" and "HideBattleBoss" or "HideBattle",
            { "Hide" }
        )
    end
    return true
end

local combatBusy = false

-- When the team-card cycle is enabled it owns combat starts, so the direct
-- mode loops stay idle and do not race it.
task.spawn(function()
    while true do
        task.wait(1.5)
        if combatBusy or Config.AutoTeamCardCycle then continue end
        if not Config.AutoInfinityTower then continue end
        -- Raid is always first when both modes are enabled and the raid is
        -- open. Tower can run while waiting for the next raid window.
        if Config.AutoRaid and isBossRaidOpen() then
            continue
        end
        if not isCombatActive() then
            combatBusy = true
            startCombatBattle(
                "InfinityTower",
                Config.AutoInfinityEquip,
                Config.AutoInfinityHide
            )
            combatBusy = false
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(1.5)
        if combatBusy or Config.AutoTeamCardCycle then continue end
        if not Config.AutoRaid then continue end
        if not isBossRaidOpen() then continue end
        if not isCombatActive() then
            combatBusy = true
            startCombatBattle(
                "BossRaid",
                Config.AutoRaidEquip,
                Config.AutoRaidHide
            )
            combatBusy = false
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(2)
        if combatBusy or not Config.AutoTeamCardCycle then continue end
        if isCombatActive() then continue end

        -- Do not touch the farming card slots unless a combat mode is
        -- actually ready to start. In particular, a closed Boss Raid must
        -- not repeatedly remove and re-equip cards.
        local combatMode
        if Config.AutoRaid and isBossRaidOpen() then
            combatMode = "BossRaid"
        elseif Config.AutoInfinityTower then
            combatMode = "InfinityTower"
        end
        if not combatMode then continue end

        combatBusy = true
        if not equipBestCardsWithRetry() then
            combatBusy = false
            continue
        end

        if combatMode == "BossRaid" then
            startCombatBattle("BossRaid", Config.AutoRaidEquip, Config.AutoRaidHide)
        elseif combatMode == "InfinityTower" then
            startCombatBattle(
                "InfinityTower",
                Config.AutoInfinityEquip,
                Config.AutoInfinityHide
            )
        end
        combatBusy = false
    end
end)

-- ══════════════════════════════════════════════════════════════
--  Rayfield Window
-- ══════════════════════════════════════════════════════════════
local Window = Rayfield:CreateWindow({
    Name            = "Anime Card Farm",
    LoadingTitle    = "Anime Card Farm",
    LoadingSubtitle = "Loading...",
    ConfigurationSaving = {
        Enabled    = true,
        FolderName = "AnimeCardFarm",
        FileName   = "Config",
    },
    Discord   = { Enabled = false },
    KeySystem = false,
})

-- ══════════════════════════════════════════════════════════════
--  TAB 1 – Auto Spawn Pack
-- ══════════════════════════════════════════════════════════════
local spawnTab = Window:CreateTab("📦 Auto Spawn Pack", 4483362458)

-- ── Spawn ────────────────────────────────────────────────────
spawnTab:CreateSection("Spawn")

spawnTab:CreateToggle({
    Name         = "Auto Spawn Pack",
    CurrentValue = Config.AutoSpawnPack,
    Flag         = "AutoSpawnPack",
    Callback     = function(v) Config.AutoSpawnPack = v end,
})

spawnTab:CreateSlider({
    Name         = "How Fast to Spawn (s)",
    Range        = { 0.05, 10 },
    Increment    = 0.05,
    Suffix       = "s",
    CurrentValue = Config.SpawnDelay,
    Flag         = "SpawnDelay",
    Callback     = function(v) Config.SpawnDelay = v end,
})

spawnTab:CreateToggle({
    Name         = "Auto Stop Spawn (on Filter Match)",
    CurrentValue = Config.AutoStopSpawn,
    Flag         = "AutoStopSpawn",
    Callback     = function(v) Config.AutoStopSpawn = v end,
})

-- ── Filters ──────────────────────────────────────────────────
spawnTab:CreateSection("Filters")

local packOptions = { "Any" }
for _, p in ipairs(PACKS) do table.insert(packOptions, p) end

spawnTab:CreateDropdown({
    Name          = "Pack",
    Options       = packOptions,
    CurrentOption = #Config.SelectedPacks > 0
        and Config.SelectedPacks
        or { "Any" },
    MultipleOptions = true,
    Flag          = "FilterPack",
    Callback      = function(v)
        Config.SelectedPacks = type(v) == "table" and v or { v }
    end,
})

local rarityOptions = { "Any" }
for _, rarity in ipairs(RARITIES) do table.insert(rarityOptions, rarity) end

spawnTab:CreateDropdown({
    Name          = "Rarity",
    Options       = rarityOptions,
    CurrentOption = #Config.SelectedRarities > 0
        and Config.SelectedRarities
        or { "Any" },
    MultipleOptions = true,
    Flag          = "RarityFilter",
    Callback      = function(v)
        Config.SelectedRarities = type(v) == "table" and v or { v }
    end,
})

local mutationOptions = { "Any" }
for _, mutation in ipairs(MUTATIONS) do table.insert(mutationOptions, mutation) end

spawnTab:CreateDropdown({
    Name          = "Mutation",
    Options       = mutationOptions,
    CurrentOption = #Config.SelectedMutations > 0
        and Config.SelectedMutations
        or { "Any" },
    MultipleOptions = true,
    Flag          = "MutationFilter",
    Callback      = function(v)
        Config.SelectedMutations = type(v) == "table" and v or { v }
    end,
})

-- ── Auto Buy ─────────────────────────────────────────────────
spawnTab:CreateSection("Auto Buy Pack")

spawnTab:CreateToggle({
    Name         = "Auto Buy Pack (Using Filter)",
    CurrentValue = Config.AutoBuyMatching,
    Flag         = "AutoBuyMatching",
    Callback     = function(v) Config.AutoBuyMatching = v end,
})

-- ══════════════════════════════════════════════════════════════
--  TAB 2 – Cards
-- ══════════════════════════════════════════════════════════════
local cardsTab = Window:CreateTab("⬆️ Cards", 4483362458)

-- ── Card Management (top) ─────────────────────────────────────
cardsTab:CreateSection("Card Management")

cardsTab:CreateToggle({
    Name         = "Auto Place Pack",
    CurrentValue = Config.AutoPlacePack,
    Flag         = "AutoPlacePack",
    Callback     = function(v) Config.AutoPlacePack = v end,
})

cardsTab:CreateParagraph({
    Title   = "Auto Place Pack Filter",
    Content = "Uses the same Pack / Rarity / Mutation filters set in the Auto Spawn Pack tab.",
})

cardsTab:CreateToggle({
    Name         = "Auto Open Pack",
    CurrentValue = Config.AutoOpenPack,
    Flag         = "AutoOpenPack",
    Callback     = function(v) Config.AutoOpenPack = v end,
})

cardsTab:CreateButton({
    Name     = "Remove All Cards",
    Callback = function()
        task.spawn(function()
            local removed = removeAllCards()
            notify("Remove All Cards", "Removed " .. tostring(removed) .. " card(s).")
        end)
    end,
})

cardsTab:CreateSlider({
    Name         = "Remove / Place / Open Delay (s)",
    Range        = { 0.5, 5 },
    Increment    = 0.1,
    Suffix       = "s",
    CurrentValue = Config.CardActionDelay,
    Flag         = "CardActionDelay",
    Callback     = function(v) Config.CardActionDelay = math.max(0.5, v) end,
})

-- ── Upgrade ───────────────────────────────────────────────────
cardsTab:CreateSection("Upgrade")

cardsTab:CreateToggle({
    Name         = "Auto Upgrade Cards",
    CurrentValue = Config.AutoUpgrade,
    Flag         = "AutoUpgrade",
    Callback     = function(v) Config.AutoUpgrade = v end,
})

cardsTab:CreateSlider({
    Name         = "Upgrade Delay (s)",
    Range        = { 0, 5 },
    Increment    = 0.05,
    Suffix       = "s",
    CurrentValue = Config.UpgradeDelay,
    Flag         = "UpgradeDelay",
    Callback     = function(v) Config.UpgradeDelay = v end,
})

-- ══════════════════════════════════════════════════════════════
--  TAB 3 – Auto Sell
-- ══════════════════════════════════════════════════════════════
local autoSellTab = Window:CreateTab("📦 Auto Sell", 4483362458)

autoSellTab:CreateSection("Box Handling")

autoSellTab:CreateToggle({
    Name         = "Auto Carry Box",
    CurrentValue = Config.AutoCarryBox,
    Flag         = "AutoCarryBox",
    Callback     = function(v) Config.AutoCarryBox = v end,
})

autoSellTab:CreateToggle({
    Name         = "Auto Sell Box",
    CurrentValue = Config.AutoSellBox,
    Flag         = "AutoSellBox",
    Callback     = function(v) Config.AutoSellBox = v end,
})

autoSellTab:CreateSlider({
    Name         = "Carry & Sell Interval (s)",
    Range        = { 1, 60 },
    Increment    = 1,
    Suffix       = "s",
    CurrentValue = Config.AutoSellDelay,
    Flag         = "AutoSellDelay",
    Callback     = function(v) Config.AutoSellDelay = v end,
})

autoSellTab:CreateSection("Cards")

autoSellTab:CreateToggle({
    Name         = "Auto Sell Cards",
    CurrentValue = Config.AutoSell,
    Flag         = "AutoSell",
    Callback     = function(v) Config.AutoSell = v end,
})

-- ══════════════════════════════════════════════════════════════
--  TAB 4 – Combat
-- ══════════════════════════════════════════════════════════════
local combatTab = Window:CreateTab("⚔️ Combat", 4483362458)

combatTab:CreateSection("Infinity Tower")

combatTab:CreateToggle({
    Name         = "Auto Equip Best Card",
    CurrentValue = Config.AutoInfinityEquip,
    Flag         = "AutoInfinityEquip",
    Callback     = function(v) Config.AutoInfinityEquip = v end,
})

combatTab:CreateToggle({
    Name         = "Auto Infinity Tower",
    CurrentValue = Config.AutoInfinityTower,
    Flag         = "AutoInfinityTower",
    Callback     = function(v) Config.AutoInfinityTower = v end,
})

combatTab:CreateToggle({
    Name         = "Auto Hide Battle",
    CurrentValue = Config.AutoInfinityHide,
    Flag         = "AutoInfinityHide",
    Callback     = function(v) Config.AutoInfinityHide = v end,
})

combatTab:CreateSection("Boss Raid")

raidInfoParagraph = combatTab:CreateParagraph({
    Title   = "Boss Raid",
    Content = "Loading Boss Raid information...",
})
updateRaidInfoDisplay(Config.RaidDifficulties)

combatTab:CreateDropdown({
    Name          = "Select Difficulty",
    Options       = raidDifficultyOptions,
    CurrentOption = Config.RaidDifficulties,
    MultipleOptions = true,
    Flag          = "RaidDifficulties",
    Callback      = function(v)
        local selected = normalizeRaidDifficulties(v)
        if #selected == 0 then
            selected = { raidDifficultyOptions[1] }
        end
        Config.RaidDifficulties = selected
        clearCompletedRaidDifficulties()
        showRaidRequirement(selected)
    end,
})

combatTab:CreateToggle({
    Name         = "Auto Equip Best Card",
    CurrentValue = Config.AutoRaidEquip,
    Flag         = "AutoRaidEquip",
    Callback     = function(v) Config.AutoRaidEquip = v end,
})

combatTab:CreateToggle({
    Name         = "Auto Boss Raid",
    CurrentValue = Config.AutoRaid,
    Flag         = "AutoRaid",
    Callback     = function(v)
        Config.AutoRaid = v
        if v then
            clearCompletedRaidDifficulties()
        end
    end,
})

combatTab:CreateToggle({
    Name         = "Auto Hide Battle",
    CurrentValue = Config.AutoRaidHide,
    Flag         = "AutoRaidHide",
    Callback     = function(v) Config.AutoRaidHide = v end,
})

combatTab:CreateSection("My Team Card")

combatTab:CreateParagraph({
    Title   = "How it works",
    Content = "When enabled, cards are removed from the first four slots and the strongest available cards are equipped only before starting an Auto Boss Raid or Auto Infinity Tower battle.",
})

combatTab:CreateToggle({
    Name         = "Auto Remove / Equip Best Card",
    CurrentValue = Config.AutoTeamCardCycle,
    Flag         = "AutoTeamCardCycle",
    Callback     = function(v) Config.AutoTeamCardCycle = v end,
})

-- ══════════════════════════════════════════════════════════════
--  TAB 5 – Reroll
-- ══════════════════════════════════════════════════════════════
local rerollTab = Window:CreateTab("🔄 Reroll", 4483362458)

rerollTab:CreateSection("Traits")

rerollTab:CreateToggle({
    Name         = "Auto Trait Roll",
    CurrentValue = Config.AutoTraitRoll,
    Flag         = "AutoTraitRoll",
    Callback     = function(v) Config.AutoTraitRoll = v end,
})

-- ══════════════════════════════════════════════════════════════
--  TAB 6 – Misc (last)
-- ══════════════════════════════════════════════════════════════
local miscTab = Window:CreateTab("🧪 Misc", 4483362458)

miscTab:CreateSection("Potions")

local potionOptions = { "All" }
for _, potion in ipairs(POTIONS) do
    table.insert(potionOptions, potion)
end

miscTab:CreateDropdown({
    Name            = "Owned Potions",
    Options         = potionOptions,
    CurrentOption   = collapseFullSelection(Config.SelectedPotions, POTIONS),
    MultipleOptions = true,
    Flag            = "SelectedPotions",
    Callback        = function(v)
        Config.SelectedPotions = collapseFullSelection(v, POTIONS)
    end,
})

miscTab:CreateToggle({
    Name         = "Auto Use Potions",
    CurrentValue = Config.AutoPotion,
    Flag         = "AutoPotion",
    Callback     = function(v) Config.AutoPotion = v end,
})

miscTab:CreateParagraph({
    Title   = "Potion behavior",
    Content = "Only selected potions that you own are used. The next potion waits until no active potion effect remains.",
})

miscTab:CreateSection("Auto Buy Boost")

local boostOptions = {}
table.insert(boostOptions, "All")
for _, boost in ipairs(BOOSTS) do
    table.insert(boostOptions, boost.label)
end

miscTab:CreateDropdown({
    Name            = "Boosts to Buy",
    Options         = boostOptions,
    CurrentOption   = collapseFullSelection(Config.SelectedBoosts, {
        "Base Expansion", "Luck Boost", "Cash Boost", "Time Boost", "Speed Boost",
    }),
    MultipleOptions = true,
    Flag            = "SelectedBoosts",
    Callback        = function(v)
        Config.SelectedBoosts = collapseFullSelection(v, {
            "Base Expansion", "Luck Boost", "Cash Boost", "Time Boost", "Speed Boost",
        })
    end,
})

miscTab:CreateToggle({
    Name         = "Auto Buy",
    CurrentValue = Config.AutoBuyBoost,
    Flag         = "AutoBuyBoost",
    Callback     = function(v) Config.AutoBuyBoost = v end,
})

miscTab:CreateParagraph({
    Title   = "Boost purchase IDs",
    Content = "Base Expansion uses the confirmed BuyCash id 'base'. Other selected boosts use their matching upgrade id.",
})

miscTab:CreateSection("Anti-AFK")

miscTab:CreateToggle({
    Name         = "Anti-AFK",
    CurrentValue = Config.AntiAfk,
    Flag         = "AntiAfk",
    Callback     = function(v) Config.AntiAfk = v end,
})

miscTab:CreateSection("Playtime Rewards")

miscTab:CreateToggle({
    Name         = "Auto Claim Playtime Rewards",
    CurrentValue = Config.AutoClaimPlaytime,
    Flag         = "AutoClaimPlaytime",
    Callback     = function(v) Config.AutoClaimPlaytime = v end,
})

miscTab:CreateToggle({
    Name         = "Auto Claim Daily Rewards",
    CurrentValue = Config.AutoClaimDaily,
    Flag         = "AutoClaimDaily",
    Callback     = function(v) Config.AutoClaimDaily = v end,
})

miscTab:CreateSection("Info")

miscTab:CreateParagraph({
    Title   = "Config Saving",
    Content = "All settings save automatically.\nSaved to: workspace/AnimeCardFarm/Config.json\n\nPress [P] to hide/show the UI.",
})

miscTab:CreateButton({
    Name     = "Test Notify",
    Callback = function()
        notify("Anime Card Farm", "Script is running!")
    end,
})

-- ── Done ─────────────────────────────────────────────────────
task.wait(1)
notify("Anime Card Farm", "Loaded! Config auto-saves on every change.")
