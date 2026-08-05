-- ============================================================
--  Anime Card Farm  –  Rayfield Edition
--  JonYueroHub  ·  Config managed via custom Settings tab.
--
--  SECURITY NOTE
--  This direct-execution check prevents simple bypasses such as
--  running this file directly without first running Loader.lua.
--  It is NOT unbreakable: a determined user can fabricate
--  getgenv().JYH_SESSION because all client-side state can be
--  modified.  For stronger protection consider a server-issued
--  short-lived launch token, backend verification from this
--  script, authenticated script delivery, or obfuscation as an
--  additional deterrent.  Do not add fake cryptography or
--  hardcoded secrets here.
-- ============================================================

-- ── URL constants (single source of truth) ───────────────────
local LOADER_URL    = "https://raw.githubusercontent.com/JonYuero/JYH-Test/refs/heads/main/Loader.lua"
local MY_SCRIPT_URL = "https://raw.githubusercontent.com/JonYuero/JYH-Test/refs/heads/main/MyScript.lua"

local VALID_LICENSE_TYPES = { FREE = true, ["30D"] = true, LIFETIME = true }

-- ── Environment ───────────────────────────────────────────────
local ENV = getgenv()

-- ── Lightweight notification (available before Rayfield) ──────
local function coreNotify(title, text)
    pcall(
        game:GetService("StarterGui").SetCore,
        game:GetService("StarterGui"),
        "SendNotification",
        { Title = title, Text = text, Duration = 5 }
    )
end

-- ── Safe Lua source fetcher ───────────────────────────────────
-- Returns a compiled function on success, or nil + reason on failure.
local function fetchLua(url)
    local ok, raw = pcall(game.HttpGet, game, url, true)
    if not ok or type(raw) ~= "string" or raw == "" then
        return nil, "HttpGet failed: " .. tostring(raw)
    end
    local head = raw:sub(1, 300):lower()
    if head:find("<!doctype", 1, true)
    or head:find("<html",     1, true)
    or head:find("404: not found", 1, true)
    or head:find("rate limit",     1, true)
    or head:find("access denied",  1, true) then
        return nil, "Server returned HTML or error page instead of Lua source"
    end
    local fn, err = loadstring(raw)
    if not fn then
        return nil, "Compile error: " .. tostring(err)
    end
    return fn
end

-- ── Return to the official loader ────────────────────────────
-- Shows the reason, clears session state, and re-executes Loader.lua.
-- A duplicate guard prevents the Loader ↔ MyScript redirect loop.
local function returnToLoader(reason)
    -- Prevent multiple concurrent redirect attempts.
    if ENV.JYH_RETURNING_TO_LOADER == true then
        return
    end
    ENV.JYH_RETURNING_TO_LOADER = true
    ENV.JYH_SESSION             = nil
    ENV.JYH_ACTIVE_SESSION      = nil

    local msg = tostring(reason or "Session validation failed")
    warn("[MyScript] Returning to Loader. Reason: " .. msg)
    coreNotify("JonYueroHub", msg .. "\nGet key first...")

    local fn, fetchErr = fetchLua(LOADER_URL)
    if not fn then
        warn("[MyScript] Could not fetch Loader: " .. tostring(fetchErr))
        coreNotify("JonYueroHub",
            "Could not load Loader automatically.\n"
            .. "Please run Loader.lua manually.")
        -- Clear the redirect guard so the user can try again.
        ENV.JYH_RETURNING_TO_LOADER = nil
        return
    end

    local execOk, execErr = pcall(fn)
    if not execOk then
        warn("[MyScript] Loader execution failed: " .. tostring(execErr))
        ENV.JYH_RETURNING_TO_LOADER = nil
    end
    -- If execOk == true, the Loader is now running; leave
    -- JYH_RETURNING_TO_LOADER = true so a stale MyScript coroutine
    -- cannot kick off another redirect.
end

-- ── Session validator ─────────────────────────────────────────
-- Validates every required field of the short-lived launch session.
-- Returns true on success; false + reason string on any failure.
-- Uses os.time() throughout — never tick() — for Unix comparisons.
local function validateSession(session)
    -- 1. Must be a table
    if type(session) ~= "table" then
        return false, "No valid key"
    end

    -- 2. authenticated must be exactly true
    if session.authenticated ~= true then
        return false, "Session is not authenticated"
    end

    -- 3. issuedAt must be numeric
    local issuedAt = tonumber(session.issuedAt)
    if not issuedAt then
        return false, "Session issuedAt is missing or non-numeric"
    end

    -- 4. Session must not be older than 120 seconds
    if math.abs(os.time() - issuedAt) > 120 then
        return false, "The loader session has expired (> 120 s old)"
    end

    -- 5. PlaceId must match
    if session.placeId ~= game.PlaceId then
        return false, "Session PlaceId does not match current game"
    end

    -- 6. UserId must match
    local LocalPlayer = game:GetService("Players").LocalPlayer
    if session.userId ~= LocalPlayer.UserId then
        return false, "Session UserId does not match current player"
    end

    -- 7. currentGame must be "Anime Card Farm"
    if session.currentGame ~= "Anime Card Farm" then
        return false, "Session currentGame mismatch"
    end

    -- 8. licenseType must be FREE, 30D, or LIFETIME
    local lt = tostring(session.licenseType or "")
    if not VALID_LICENSE_TYPES[lt] then
        return false, "Unknown license type: '" .. lt .. "'"
    end

    -- 9. loaderUrl must match the official URL when present
    if session.loaderUrl ~= nil and session.loaderUrl ~= LOADER_URL then
        return false, "Session loaderUrl does not match the official Loader"
    end

    -- 10. scriptUrl must match the official MyScript URL when present
    if session.scriptUrl ~= nil and session.scriptUrl ~= MY_SCRIPT_URL then
        return false, "Session scriptUrl does not match the official game script"
    end

    return true
end

-- ════════════════════════════════════════════════════════════════
--  SESSION VALIDATION  ← must be the first executable gate
--  Nothing below this point runs if the session is invalid.
-- ════════════════════════════════════════════════════════════════
local valid, reason = validateSession(ENV.JYH_SESSION)
if not valid then
    returnToLoader(reason)
    return   -- stop all further initialization
end

-- ── Duplicate game-script guard ───────────────────────────────
-- Validation passed.  Check for an already-running instance before
-- consuming the session token so a double-run is caught cleanly.
if ENV.JYH_GAME_SCRIPT_RUNNING == true then
    coreNotify("JonYueroHub", "Anime Card Farm is already running.")
    return
end

-- From this point the script is the single authoritative instance.
ENV.JYH_GAME_SCRIPT_RUNNING = true

-- ── Consume the one-time launch session ──────────────────────
-- Copy necessary values to the long-lived active session, then nil
-- the short-lived token.  Running MyScript again directly will fail
-- validation because JYH_SESSION is now nil.
ENV.JYH_ACTIVE_SESSION = {
    authenticated = true,
    licenseType   = ENV.JYH_SESSION.licenseType,
    expiresAt     = ENV.JYH_SESSION.expiresAt,
    issuedAt      = ENV.JYH_SESSION.issuedAt,
    userId        = ENV.JYH_SESSION.userId,
    placeId       = ENV.JYH_SESSION.placeId,
    currentGame   = ENV.JYH_SESSION.currentGame,
}

ENV.JYH_SESSION             = nil
ENV.JYH_RETURNING_TO_LOADER = nil

-- ── Derive membership from validated license type ─────────────
-- Do NOT trust a client-supplied role string; derive it here.
local licenseType = ENV.JYH_ACTIVE_SESSION.licenseType
local isPremium   = (licenseType == "30D" or licenseType == "LIFETIME")
local userRole    = isPremium and "Premium User" or "Freemium User"

local licenseLabel = licenseType == "LIFETIME" and "Lifetime"
                  or licenseType == "30D"       and "30 Days"
                  or "FREE"

-- ── Expiry check for FREE and 30D keys ───────────────────────
-- For LIFETIME allow nil / "Never" / any non-numeric sentinel.
-- Use os.time() — never tick() — for Unix timestamp comparisons.
if licenseType ~= "LIFETIME" then
    local expiry = tonumber(ENV.JYH_ACTIVE_SESSION.expiresAt)
    if expiry and expiry <= os.time() then
        returnToLoader("The license has expired")
        return
    end
end

-- ════════════════════════════════════════════════════════════════
--  Everything below this line is the original Anime Card Farm
--  game script, unchanged except for:
--    • Rayfield now loads here (after validation) instead of at line 1.
--    • The Rayfield window name includes the membership role.
--    • The `notify` helper is defined early (before setPlotNumber).
--    • Rayfield built-in saving is disabled; the Settings tab handles it.
-- ════════════════════════════════════════════════════════════════

-- ── Load Rayfield ─────────────────────────────────────────────
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
    error("[ACF] Failed to load Rayfield from all sources. Check executor HTTP settings.")
end

-- ── Services ─────────────────────────────────────────────────
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser       = game:GetService("VirtualUser")
local StarterGui        = game:GetService("StarterGui")

local player = Players.LocalPlayer
if not player.Character then player.CharacterAdded:Wait() end
local playerGui = player:WaitForChild("PlayerGui")

-- ── In-game notification (uses StarterGui, defined early so
--    setPlotNumber and other helpers can call it safely) ───────
local function notify(title, text)
    pcall(StarterGui.SetCore, StarterGui, "SendNotification", {
        Title = title, Text = text, Duration = 3,
    })
end

-- ── Remotes ──────────────────────────────────────────────────
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
    AutoBuyMatching   = false,
    AutoContinueSpawn = false,
    AutoBuyDebug    = false,
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

-- ── Controls table (Rayfield control references for config loading) ──
local Controls = {}

-- Playtime state is pushed by the game's client remote.
local playtimeReadyRewards = {}
local playtimeStateReceived = false

-- Forward declarations
local clickGuiButton
local startCombatBattle
local removeAllCards
local removeFirstFourCardSlots
local doEquipBestCards

-- ── Remote helpers ───────────────────────────────────────────
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
local function fireButton(part)
    if not part then return false end

    local click = part:FindFirstChildOfClass("ClickDetector")
               or part:FindFirstChild("ClickDetector")
    if click then
        if fireclickdetector then
            pcall(fireclickdetector, click)
            return true
        end
        pcall(function() click.MouseClick:Fire(player.Character) end)
        return true
    end

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
--  PLOT AUTO-DETECTION
-- ══════════════════════════════════════════════════════════════

local function setPlotNumber(n)
    if type(n) ~= "number" or n == Config.PlotNumber then return end
    Config.PlotNumber = n
    warn("[ACF] Plot auto-detected: #" .. tostring(n))
    notify("Plot Detected", "Your plot is slot #" .. tostring(n))
end

local function readPlayerPlotNumber()
    local iv = player:FindFirstChild("PlotNumber")
    if iv and iv:IsA("IntValue") then return tonumber(iv.Value) end
    local attr = player:GetAttribute("PlotNumber")
    if attr ~= nil then return tonumber(attr) end
    return nil
end

local function autoDetectMyPlotNumber()
    return readPlayerPlotNumber()
end

task.spawn(function()
    local map = workspace:FindFirstChild("MAP")
    if not map then
        map = workspace:WaitForChild("MAP", 30)
    end
    if not map then
        warn("[ACF] workspace.MAP not found after 30 s — game may use a different structure.")
    end

    local iv = player:FindFirstChild("PlotNumber")
    if not iv then
        iv = player:WaitForChild("PlotNumber", 15)
    end

    if iv and iv:IsA("IntValue") then
        local n = tonumber(iv.Value)
        if n and n > 0 then
            setPlotNumber(n)
        end

        iv.Changed:Connect(function(newVal)
            local num = tonumber(newVal)
            if num and num > 0 then
                Config.PlotNumber = num
                warn("[ACF] Plot reassigned by server: #" .. tostring(num))
                notify("Plot Updated", "Moved to slot #" .. tostring(num))
                sellBoxPartCache = nil
            end
        end)
    else
        local attr = player:GetAttribute("PlotNumber")
        if attr ~= nil then
            local n = tonumber(attr)
            if n and n > 0 then setPlotNumber(n) end
        else
            warn("[ACF] PlotNumber not found on player after 15 s. "
                .. "Carry/Sell will not work correctly until the plot is assigned.")
        end
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

local function findPlot(plotNumber)
    local map   = workspace:FindFirstChild("MAP")
    local plots = map and map:FindFirstChild("Plots")
    if plots then
        local slot = plots:FindFirstChild(tostring(plotNumber))
        if slot then
            local plotN0 = slot:FindFirstChild("Plot_N0")
            if plotN0 then return plotN0 end
            return slot
        end
    end

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

local function getPlotButtons(plotNumber)
    local plot = findPlot(plotNumber)
    if not plot then return nil, nil end

    local spawnBtn = plot:FindFirstChild("ButtonPart", true)
               or plot:FindFirstChild("ButtonSelect", true)

    local placeBtn = plot:FindFirstChild("PlaceButton",    true)
               or plot:FindFirstChild("ConveyorButton", true)
               or plot:FindFirstChild("ButtonPlace",    true)

    return spawnBtn, placeBtn
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

local metadataCache = setmetatable({}, { __mode = "k" })

local function readBoxValue(box, names)
    for _, name in ipairs(names) do
        local attribute = box:GetAttribute(name)
        if attribute ~= nil then
            return attribute
        end
    end

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

    if packValue == nil and box:IsA("Model") then
        local name = box.Name
        if string.find(string.lower(name), "pack", 1, true) then
            packValue = name
        end
    end

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

local function getItemId(container)
    local value = readBoxValue(container, { "ItemId", "ItemID", "itemId" })
    if value ~= nil then return tonumber(value) or value end

    local current = container.Parent
    for _ = 1, 6 do
        if not current or current == workspace then break end
        local parentValue = nil
        for _, name in ipairs({ "ItemId", "ItemID", "itemId" }) do
            parentValue = current:GetAttribute(name)
            if parentValue ~= nil then break end
        end
        if parentValue == nil then
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

    return getItemId(container) ~= nil
        or info and info.pack ~= nil
end

-- ════════════════════════════════════════════════════════════════════════
--  OPTIMIZED CONVEYOR & AUTO-BUY SYSTEM
--  State machine per pack:
--    Detected → WaitingForItemId / WaitingForPrompt → ReadyToBuy
--            → Buying → Purchased → Removed
--  One registry entry per pack. Event-driven discovery.
--  Purchase queue prevents double-activation.
--  Filter cache rebuilt only on config change.
--  Debug output rate-limited; no string work when debug is off.
-- ════════════════════════════════════════════════════════════════════════

-- ── Shared gate used by box handling and combat loops ────────────────
local boxHandlingActive = false

-- ── Single canonical registry ─────────────────────────────────────────
local ConveyorRecords = {}              -- [packModel] = record
local ItemIdIndex     = {}              -- [itemId]    = packModel

-- ── Purchase queue ────────────────────────────────────────────────────
local PurchaseQueue  = {}               -- ordered list of records
local PurchaseQueued = {}               -- [record] = true (dedup set)

-- ── Per-prompt watcher guard ──────────────────────────────────────────
local WatchedPrompts = setmetatable({}, { __mode = "k" })

-- ── Debug helpers ─────────────────────────────────────────────────────
local DebugCooldowns   = {}
local DEBUG_COOLDOWN   = 3             -- seconds between identical debug keys

local function autoBuyDebug(message)
    -- Centralized debug helper — does nothing when debug is disabled.
    if Config.AutoBuyDebug then
        warn("[ACF][AutoBuy] " .. tostring(message))
    end
end

local function debugOnce(key, message, cooldown)
    -- Rate-limited debug print. Suppresses identical events within cooldown.
    if not Config.AutoBuyDebug then return end
    cooldown = cooldown or DEBUG_COOLDOWN
    local now = os.clock()
    if DebugCooldowns[key] and now - DebugCooldowns[key] < cooldown then return end
    DebugCooldowns[key] = now
    warn("[ACF][AutoBuy] " .. tostring(message))
end

local function conveyorLog(message)
    if Config.AutoBuyDebug then
        warn("[Conveyor] " .. tostring(message))
    end
end

-- ── Diagnostic state (also used by warnOnce throughout the script) ────
local diagnosticState = {}

local function warnOnce(key, message)
    if diagnosticState[key] then return end
    diagnosticState[key] = true
    warn("[ACF] " .. message)
end

-- ── Filter cache ──────────────────────────────────────────────────────
-- Normalized selections are rebuilt at most once per config change,
-- not on every pack evaluation.

local FilterCache = {
    Rarities  = {},
    Mutations = {},
    Packs     = {},
    dirty     = true,
}

local function rebuildFilterCache()
    FilterCache.Rarities  = normalizeFilterSelection(Config.SelectedRarities)
    FilterCache.Mutations = normalizeFilterSelection(Config.SelectedMutations)
    FilterCache.Packs     = normalizeFilterSelection(Config.SelectedPacks)
    FilterCache.dirty     = false
end

-- Call this whenever a filter dropdown value changes.
local function markFilterCacheDirty()
    FilterCache.dirty = true
end

local passesFilter = function(info)
    if FilterCache.dirty then rebuildFilterCache() end
    info = info or {}
    return filterValueMatches(info.rarity,   FilterCache.Rarities)
       and filterValueMatches(info.mutation, FilterCache.Mutations)
       and filterValueMatches(info.pack,     FilterCache.Packs)
end

-- ── Buy timing constants ──────────────────────────────────────────────
local BUY_RETRY_DELAY  = 0.75          -- min seconds between attempts on same record
local BUYING_TIMEOUT   = 2.5           -- seconds before rolling back from "Buying"
local METADATA_TTL     = 2.0           -- seconds between metadata refreshes

-- ── Forward declarations ──────────────────────────────────────────────
local tryBuyRecord
local queuePurchase
local cleanupRecord
local evaluateRecordReadiness
local refreshRecordMetadata

-- ── Connection tracker ────────────────────────────────────────────────
local function trackConnection(record, connection)
    if connection then table.insert(record.connections, connection) end
end

-- ── State-machine transition ──────────────────────────────────────────
local function transitionState(record, newState)
    if record.state == newState then return end
    record.state = newState
    if Config.AutoBuyDebug then
        -- Always log true transitions immediately (cooldown = 0)
        debugOnce(
            "state:" .. tostring(record.model) .. ":" .. newState,
            "State → " .. newState
                .. "  pack=" .. tostring(record.info and record.info.pack)
                .. "  itemId=" .. tostring(record.itemId),
            0
        )
    end
end

-- ── Conveyor topology helpers ─────────────────────────────────────────

local function hasConveyorAncestor(instance)
    local cur = instance
    for _ = 1, 10 do
        if not cur then break end
        local lname = string.lower(cur.Name)
        if lname == "conveyor" or string.find(lname, "conveyor", 1, true) then
            return true
        end
        cur = cur.Parent
    end
    return false
end

local function isConveyorModel(model)
    return model and model:IsA("Model") and hasConveyorAncestor(model)
end

-- Walk upward to identify the outermost pack model within a conveyor.
local function resolvePackModel(instance)
    local cur = instance
    if cur and not cur:IsA("Model") then
        cur = cur:FindFirstAncestorOfClass("Model")
    end
    local best = nil
    for _ = 1, 10 do
        if not cur then break end
        if isConveyorModel(cur) and isPackContainer(cur, nil) then
            best = cur
        end
        cur = cur.Parent
        while cur and not cur:IsA("Model") do cur = cur.Parent end
    end
    return best
end

local function isLikelyPackModel(model)
    if not isConveyorModel(model) then return false end
    for _, n in ipairs({ "ItemId", "ItemID", "itemId" }) do
        if model:GetAttribute(n) ~= nil then return true end
    end
    if model:FindFirstChildWhichIsA("ProximityPrompt", true) then return true end
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("ValueBase") and string.lower(child.Name) == "itemid" then
            return true
        end
    end
    return isPackContainer(model, nil)
end

-- ── Buy prompt detection ──────────────────────────────────────────────

local function normalizePromptText(value)
    if value == nil then return "" end
    return string.lower(string.gsub(tostring(value), "^%s*(.-)%s*$", "%1"))
end

local function isBuyPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return false end
    if prompt.Enabled == false then return false end
    local n = normalizePromptText(prompt.Name)
    local a = normalizePromptText(prompt.ActionText)
    local o = normalizePromptText(prompt.ObjectText)
    return string.find(n, "buy", 1, true) ~= nil
        or string.find(a, "buy", 1, true) ~= nil
        or string.find(o, "buy", 1, true) ~= nil
end

-- Scan the pack once to find the best active buy prompt.
local function findBestBuyPrompt(packModel)
    if not packModel then return nil end
    local firstEnabled = nil
    for _, desc in ipairs(packModel:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Enabled ~= false then
            if isBuyPrompt(desc) then return desc end
            if not firstEnabled then firstEnabled = desc end
        end
    end
    -- Narrow fallback: siblings under the pack's parent
    local parent = packModel.Parent
    if parent then
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("ProximityPrompt") and child.Enabled ~= false
                and isBuyPrompt(child) then
                return child
            end
        end
    end
    return firstEnabled
end

-- ── Record cleanup ────────────────────────────────────────────────────
cleanupRecord = function(record)
    if not record then return end
    if record.state == "Removed" then return end    -- idempotent
    record.state = "Removed"

    -- Disconnect all event connections attached to this record
    for _, conn in ipairs(record.connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(record.connections)

    -- Remove from all tables
    if record.model then
        ConveyorRecords[record.model] = nil
        metadataCache[record.model]   = nil
    end
    if record.itemId ~= nil then
        ItemIdIndex[record.itemId] = nil
    end
    PurchaseQueued[record] = nil
    -- Don't bother removing from PurchaseQueue list — the scheduler skips Removed records.
end

-- ── Metadata refresh (lazy, TTL-gated) ───────────────────────────────
refreshRecordMetadata = function(record, force)
    if not record or not record.model then return end
    local now = os.clock()
    if not force
        and record.lastMetadataRefresh
        and now - record.lastMetadataRefresh < METADATA_TTL then
        return
    end
    record.lastMetadataRefresh = now
    record.info = getBoxInfo(record.model)

    -- Try to fill ItemId if still missing
    if record.itemId == nil then
        local freshId = getItemId(record.model)
        if freshId ~= nil then
            record.itemId = freshId
            ItemIdIndex[freshId] = record.model
            if Config.AutoBuyDebug then
                debugOnce(
                    "itemid-fallback:" .. tostring(record.model),
                    "ItemId found via fallback scan: " .. tostring(freshId)
                        .. "  pack=" .. tostring(record.info and record.info.pack),
                    0
                )
            end
        end
    end
end

-- ── Readiness evaluation ──────────────────────────────────────────────
evaluateRecordReadiness = function(record)
    if not record then return end
    if record.state == "Purchased"
        or record.state == "Removed"
        or record.state == "Buying" then
        return
    end

    -- Refresh cached buy prompt
    if not record.buyPrompt or not record.buyPrompt.Enabled then
        record.buyPrompt = findBestBuyPrompt(record.model)
    end

    local hasId     = record.itemId ~= nil
    local hasPrompt = record.buyPrompt ~= nil and record.buyPrompt.Enabled ~= false

    if hasId and hasPrompt then
        if record.state ~= "ReadyToBuy" then
            transitionState(record, "ReadyToBuy")
        end
        if Config.AutoBuyMatching and not boxHandlingActive then
            if passesFilter(record.info) then
                queuePurchase(record)
            end
        end
    elseif not hasId then
        if record.state ~= "WaitingForItemId" then
            transitionState(record, "WaitingForItemId")
        end
    else
        if record.state ~= "WaitingForPrompt" then
            transitionState(record, "WaitingForPrompt")
        end
    end
end

-- ── Purchase queue ────────────────────────────────────────────────────
queuePurchase = function(record)
    if not record then return end
    if record.state ~= "ReadyToBuy" then return end
    if PurchaseQueued[record] then return end        -- dedup guard
    PurchaseQueued[record] = true
    table.insert(PurchaseQueue, record)
end

-- ── Buy attempt ───────────────────────────────────────────────────────
tryBuyRecord = function(record)
    if not record or not record.model then return false end
    if not record.model:IsDescendantOf(workspace) then
        cleanupRecord(record)
        return false
    end

    local now = os.clock()
    if now - record.lastBuyAttempt < BUY_RETRY_DELAY then return false end
    record.lastBuyAttempt = now
    record.buyAttempts    = record.buyAttempts + 1

    -- Refresh prompt cache once before attempting
    if not record.buyPrompt or not record.buyPrompt.Enabled then
        record.buyPrompt = findBestBuyPrompt(record.model)
    end
    if not record.buyPrompt then
        debugOnce(
            "noprompt:" .. tostring(record.model),
            "No enabled buy prompt — will retry when prompt appears"
        )
        transitionState(record, "WaitingForPrompt")
        return false
    end

    transitionState(record, "Buying")

    local itemId    = record.itemId
    local succeeded = false

    if itemId ~= nil then
        -- Primary path: fire via the game's ConveyorRE remote
        if Config.AutoBuyDebug then
            debugOnce(
                "buy:" .. tostring(itemId),
                "Purchase request  ItemId=" .. tostring(itemId)
                    .. "  pack=" .. tostring(record.info and record.info.pack),
                0
            )
        end
        local ok, err = pcall(function()
            ConveyorRE:FireServer("TryBuy", { ItemId = itemId })
        end)
        if ok then
            succeeded = true
        else
            warn("[ACF][AutoBuy] TryBuy remote failed: " .. tostring(err))
            -- Fallback: activate the prompt only when the remote fails
            if fireproximityprompt then
                task.wait(0.12)
                if record.model:IsDescendantOf(workspace)
                    and record.buyPrompt and record.buyPrompt.Enabled then
                    pcall(fireproximityprompt, record.buyPrompt)
                    succeeded = true
                    if Config.AutoBuyDebug then
                        autoBuyDebug("Prompt fallback used after remote failure")
                    end
                end
            end
        end
    else
        -- No ItemId: use the buy prompt directly
        if Config.AutoBuyDebug then
            debugOnce(
                "buy-prompt:" .. tostring(record.model),
                "Purchase via prompt (no ItemId)  pack="
                    .. tostring(record.info and record.info.pack),
                0
            )
        end
        if fireproximityprompt then
            local ok, err = pcall(fireproximityprompt, record.buyPrompt)
            if ok then
                succeeded = true
            else
                if Config.AutoBuyDebug then
                    autoBuyDebug("Prompt activation failed: " .. tostring(err))
                end
            end
        else
            warnOnce(
                "AutoBuy:no-fireproximityprompt",
                "No ItemId and fireproximityprompt unavailable — cannot buy."
            )
        end
    end

    if not succeeded then
        -- Roll back so the cooldown will allow a retry
        transitionState(record, "ReadyToBuy")
    end
    return succeeded
end

-- ── Prompt event watcher ──────────────────────────────────────────────
local function watchPromptEnabled(prompt, record)
    if not prompt or WatchedPrompts[prompt] then return end
    WatchedPrompts[prompt] = true

    local conn = prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
        if not prompt.Enabled then return end
        if record.state == "Purchased" or record.state == "Removed" then return end
        if isBuyPrompt(prompt) then record.buyPrompt = prompt end
        refreshRecordMetadata(record, false)
        evaluateRecordReadiness(record)
    end)
    trackConnection(record, conn)
end

local function attachPromptsOnPack(record)
    -- Watch all current prompts
    for _, desc in ipairs(record.model:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            watchPromptEnabled(desc, record)
        end
    end
    -- Watch for future prompts added to the model
    local conn = record.model.DescendantAdded:Connect(function(desc)
        if desc:IsA("ProximityPrompt") then
            watchPromptEnabled(desc, record)
            if isBuyPrompt(desc) and desc.Enabled then
                record.buyPrompt = desc
                evaluateRecordReadiness(record)
            end
        end
        -- Invalidate metadata cache on any structural change
        metadataCache[record.model] = nil
    end)
    trackConnection(record, conn)
end

-- ── ItemId event watcher ──────────────────────────────────────────────
local function attachItemIdWatcher(record)
    local model = record.model

    -- Watch all three attribute name variants
    for _, attrName in ipairs({ "ItemId", "ItemID", "itemId" }) do
        local conn = model:GetAttributeChangedSignal(attrName):Connect(function()
            local v = model:GetAttribute(attrName)
            if v ~= nil and record.itemId == nil then
                record.itemId = v
                ItemIdIndex[v] = model
                if Config.AutoBuyDebug then
                    debugOnce(
                        "itemid-attr:" .. tostring(model),
                        "ItemId attribute set: " .. tostring(v),
                        0
                    )
                end
                evaluateRecordReadiness(record)
            end
        end)
        trackConnection(record, conn)
    end

    -- Watch for an ItemId ValueBase child being added
    local conn2 = model.ChildAdded:Connect(function(child)
        if not child:IsA("ValueBase") then return end
        if string.lower(child.Name) ~= "itemid" then return end
        if record.itemId ~= nil then return end
        local v = child.Value
        if v ~= nil then
            record.itemId = v
            ItemIdIndex[v] = model
            evaluateRecordReadiness(record)
        end
        child.Changed:Connect(function(newV)
            if newV ~= nil and record.itemId == nil then
                record.itemId = newV
                ItemIdIndex[newV] = model
                evaluateRecordReadiness(record)
            end
        end)
    end)
    trackConnection(record, conn2)
end

-- ── Pack registration (idempotent) ────────────────────────────────────
local function registerPack(packModel)
    if not packModel then return nil end

    -- Return existing record immediately — never re-register the same model
    if ConveyorRecords[packModel] then
        return ConveyorRecords[packModel]
    end

    -- One-time metadata read at registration
    local info   = getBoxInfo(packModel)
    local itemId = getItemId(packModel)

    local record = {
        model               = packModel,
        state               = "Detected",
        itemId              = itemId,
        info                = info,
        buyPrompt           = nil,
        createdAt           = os.clock(),
        lastMetadataRefresh = os.clock(),
        lastBuyAttempt      = 0,
        buyAttempts         = 0,
        connections         = {},
    }

    ConveyorRecords[packModel] = record
    if itemId ~= nil then
        ItemIdIndex[itemId] = packModel
    end

    if Config.AutoBuyDebug then
        debugOnce(
            "register:" .. tostring(packModel),
            "Registered  pack=" .. tostring(info and info.pack)
                .. "  rarity=" .. tostring(info and info.rarity)
                .. "  ItemId=" .. tostring(itemId),
            0
        )
    end

    -- Attach watchers (runs once per model)
    attachItemIdWatcher(record)
    attachPromptsOnPack(record)

    -- Initial prompt cache fill
    record.buyPrompt = findBestBuyPrompt(packModel)

    -- Watch for removal from workspace
    local conn = packModel.AncestryChanged:Connect(function()
        if not packModel:IsDescendantOf(workspace) then
            if Config.AutoBuyDebug then
                autoBuyDebug(
                    "Pack removed  pack=" .. tostring(record.info and record.info.pack)
                )
            end
            cleanupRecord(record)
        end
    end)
    trackConnection(record, conn)

    -- Evaluate initial readiness
    evaluateRecordReadiness(record)

    return record
end

-- ── Plot-scoped conveyor container ────────────────────────────────────
local function getLocalConveyorContainer()
    local plot = findPlot(Config.PlotNumber)
    if not plot then return nil end
    local lc = plot:FindFirstChild("LocalConveyorModels")
    if lc then return lc end
    return plot:FindFirstChild("Conveyor", true)
        or plot:FindFirstChild("Conveyors", true)
end

-- ── Initial scan ──────────────────────────────────────────────────────
-- Runs once, yielding every 200 iterations to avoid hitching.
-- Prefers the local plot's conveyor container; falls back to workspace.

local function doInitialConveyorScan()
    local container = getLocalConveyorContainer() or workspace
    local descendants = container:GetDescendants()
    for index, desc in ipairs(descendants) do
        if index % 200 == 0 then task.wait() end
        if desc:IsA("Model") and isLikelyPackModel(desc) then
            registerPack(desc)
        end
    end
end

-- ── Plot-change rebind ────────────────────────────────────────────────
local conveyorContainerListener = nil

local function rebindConveyorContainer()
    if conveyorContainerListener then
        pcall(function() conveyorContainerListener:Disconnect() end)
        conveyorContainerListener = nil
    end

    -- Clean up all records from the previous plot
    for _, record in pairs(ConveyorRecords) do
        cleanupRecord(record)
    end
    table.clear(ConveyorRecords)
    table.clear(ItemIdIndex)
    table.clear(PurchaseQueue)
    table.clear(PurchaseQueued)

    -- Scan for the new plot
    task.spawn(doInitialConveyorScan)

    -- Watch the new container for additions
    local container = getLocalConveyorContainer()
    if not container then return end

    local function handleAddedDesc(desc)
        if desc:IsA("Model") and isLikelyPackModel(desc) then
            registerPack(desc)
        elseif desc:IsA("ProximityPrompt") then
            local ownerModel = desc:FindFirstAncestorOfClass("Model")
            if ownerModel then
                local record = ConveyorRecords[ownerModel]
                if record then
                    watchPromptEnabled(desc, record)
                    if isBuyPrompt(desc) and desc.Enabled then
                        record.buyPrompt = desc
                        evaluateRecordReadiness(record)
                    end
                elseif isLikelyPackModel(ownerModel) then
                    registerPack(ownerModel)
                end
            end
        end
    end

    conveyorContainerListener = container.DescendantAdded:Connect(handleAddedDesc)
end

-- ── Workspace-level DescendantAdded (broad net for non-local packs) ───
workspace.DescendantAdded:Connect(function(desc)
    if desc:IsA("Model") and isLikelyPackModel(desc) then
        registerPack(desc)
    elseif desc:IsA("ProximityPrompt") then
        local ownerModel = desc:FindFirstAncestorOfClass("Model")
        if ownerModel then
            local record = ConveyorRecords[ownerModel]
            if record then
                watchPromptEnabled(desc, record)
                if isBuyPrompt(desc) and desc.Enabled then
                    record.buyPrompt = desc
                    evaluateRecordReadiness(record)
                end
            elseif isLikelyPackModel(ownerModel) then
                registerPack(ownerModel)
            end
        end
    end
end)

workspace.DescendantRemoving:Connect(function(desc)
    if desc:IsA("Model") then
        local record = ConveyorRecords[desc]
        if record then cleanupRecord(record) end
    else
        local model = desc:FindFirstAncestorOfClass("Model")
        if model then metadataCache[model] = nil end
    end
end)

-- ── Conveyor scheduler ────────────────────────────────────────────────
-- Single lightweight loop at 0.15 s.
-- Responsibilities: process purchase queue, slow fallback for waiting records,
-- buying timeout recovery, and removal cleanup.

task.spawn(function()
    while true do
        task.wait(0.15)

        -- ── Process purchase queue ───────────────────────────────────
        if not boxHandlingActive and Config.AutoBuyMatching then
            local i = 1
            while i <= #PurchaseQueue do
                local record = PurchaseQueue[i]
                if record.state == "Removed"
                    or record.state == "Purchased"
                    or not record.model:IsDescendantOf(workspace) then
                    -- Stale entry — discard
                    PurchaseQueued[record] = nil
                    table.remove(PurchaseQueue, i)
                else
                    local attempted = tryBuyRecord(record)
                    if attempted then
                        PurchaseQueued[record] = nil
                        table.remove(PurchaseQueue, i)
                    else
                        i = i + 1
                    end
                end
            end
        end

        -- ── Slow fallback for waiting / stuck records ────────────────
        for _, record in pairs(ConveyorRecords) do
            local state = record.state
            if state == "Detected"
                or state == "WaitingForItemId"
                or state == "WaitingForPrompt" then
                -- Lazy refresh — respects METADATA_TTL
                refreshRecordMetadata(record, false)
                evaluateRecordReadiness(record)

            elseif state == "Buying" then
                -- Timeout recovery: roll back if server never confirmed
                if os.clock() - record.lastBuyAttempt > BUYING_TIMEOUT then
                    if record.model:IsDescendantOf(workspace) then
                        transitionState(record, "ReadyToBuy")
                        if Config.AutoBuyMatching
                            and not boxHandlingActive
                            and passesFilter(record.info) then
                            queuePurchase(record)
                        end
                    else
                        cleanupRecord(record)
                    end
                end
            end
        end
    end
end)

-- ── Compatibility shims (used by Auto Spawn and other loops below) ────

-- Lightweight snapshot of active records (no metadata rebuild per call).
local function getConveyorPacks()
    local packs = {}
    for model, record in pairs(ConveyorRecords) do
        if model:IsDescendantOf(workspace) then
            table.insert(packs, record)
        else
            cleanupRecord(record)
        end
    end
    return packs
end

local function getPackKey(record)
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

-- Legacy alias — kept so any remaining downstream code still compiles.
local debugAutoBuy = autoBuyDebug

local function describePack(record)
    if not record or not record.model then return "<missing pack>" end
    local info = record.info or {}
    return string.format(
        "model=%s  itemId=%s  pack=%s  state=%s",
        record.model:GetFullName(),
        tostring(record.itemId),
        tostring(info.pack),
        tostring(record.state)
    )
end

-- ── Deferred startup ─────────────────────────────────────────────────
-- Initial scan and container binding run after other startup code.

task.spawn(doInitialConveyorScan)
task.spawn(rebindConveyorContainer)

-- ── Loops ─────────────────────────────────────────────────────────────

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

-- Guard preventing multiple concurrent coroutines from firing stop/resume
local autoStopHandled = false

-- Auto Spawn Pack
task.spawn(function()
    while true do
        task.wait(math.max(0.05, Config.SpawnDelay))
        if not Config.AutoSpawnPack then continue end
        if boxHandlingActive then continue end
        if autoStopHandled then continue end

        local previousIds
        if Config.AutoStopSpawn then
            previousIds = indexPackIds(getConveyorPacks())
        end

        local spawnBtn, _ = getPlotButtons(Config.PlotNumber)
        if not spawnBtn then
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

        if Config.AutoStopSpawn then
            local capturedIds = previousIds
            task.spawn(function()
                if autoStopHandled then return end

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
                    if autoStopHandled then return end
                    autoStopHandled = true

                    Config.AutoSpawnPack = false
                    if Rayfield and Rayfield.Flags and Rayfield.Flags["AutoSpawnPack"] then
                        Rayfield.Flags["AutoSpawnPack"]:Set(false)
                    end
                    notify("Auto Spawn Pack", "Stopped — filter match found!")

                    if Config.AutoContinueSpawn and Config.AutoBuyMatching then
                        local watchedRecord = spawnedRecord
                        task.spawn(function()
                            local didAttemptBuy = false
                            for _ = 1, 50 do
                                task.wait(0.1)
                                -- New state name: "Buying" (was "buying")
                                if watchedRecord.state == "Buying" then
                                    didAttemptBuy = true
                                    break
                                end
                            end
                            if not didAttemptBuy then
                                autoStopHandled = false
                                return
                            end
                            for _ = 1, 150 do
                                task.wait(0.1)
                                if not watchedRecord.model:IsDescendantOf(workspace) then
                                    if Config.AutoContinueSpawn then
                                        Config.AutoSpawnPack = true
                                        pcall(function()
                                            if Controls.AutoSpawnPack and Controls.AutoSpawnPack.Set then
                                                Controls.AutoSpawnPack:Set(true)
                                            end
                                        end)
                                        if Rayfield.Flags and Rayfield.Flags["AutoSpawnPack"] then
                                            Rayfield.Flags["AutoSpawnPack"]:Set(true)
                                        end
                                        notify("Spawn Manager", "Resumed — pack purchased!")
                                    end
                                    autoStopHandled = false
                                    return
                                end
                            end
                            autoStopHandled = false
                        end)
                    end
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

-- Auto Buy Matching is now handled by the conveyor scheduler above.
-- queuePurchase is called from evaluateRecordReadiness when:
--   • a pack transitions to ReadyToBuy
--   • Config.AutoBuyMatching is enabled
--   • boxHandlingActive is false
--   • passesFilter returns true
-- The scheduler processes the queue at 0.15 s intervals.

-- ── Auto Carry Box helpers ───────────────────────────────────
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

local findOneCarryPromptOnPlot = findOneCarryInteractionOnPlot

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

local sellBoxPartCache = nil
local function findSellBoxPart()
    if sellBoxPartCache and sellBoxPartCache:IsDescendantOf(workspace) then
        return sellBoxPartCache
    end
    sellBoxPartCache = nil

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

    local plot = findPlot(Config.PlotNumber)
    if plot then
        local found = searchIn(plot:GetDescendants())
        if found then
            sellBoxPartCache = found
            return found
        end
    end

    local found = searchIn(workspace:GetDescendants())
    if found then
        sellBoxPartCache = found
    end
    return sellBoxPartCache
end

-- ── Teleport helpers ─────────────────────────────────────────
local function getCFrameOf(object)
    if not object then return nil end
    if object:IsA("BasePart") then return object.CFrame end
    if object:IsA("Model") then
        local primary = object.PrimaryPart
        if primary then return primary.CFrame end
        for _, child in ipairs(object:GetChildren()) do
            if child:IsA("BasePart") then return child.CFrame end
        end
    end
    return nil
end

local function teleportNear(cframe)
    if not cframe then return end
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local offset = Vector3.new(0, 0, 3)
    pcall(function()
        root.CFrame = cframe * CFrame.new(offset)
    end)
end

local function doSellAtStation()
    local station = findSellBoxPart()
    if not station then
        warnOnce("SellBox:no-station", "Sell station not found on your plot.")
        return false
    end

    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return false end

    teleportNear(getCFrameOf(station))
    task.wait(0.35)  -- increased from 0.2 so the server registers the position

    if station:IsA("ProximityPrompt") or station:IsA("ClickDetector") then
        local target = station.Parent
        if not target then return false end
        teleportNear(getCFrameOf(target))
        task.wait(0.2)  -- increased from 0.1
        if station:IsA("ProximityPrompt") then
            return firePrompt(station)
        elseif station:IsA("ClickDetector") then
            return fireClickDetector(station)
        end
    end
    local prompt = station:FindFirstChildOfClass("ProximityPrompt")
                or station:FindFirstChild("ProximityPrompt", true)
    if prompt then return firePrompt(prompt) end
    local click = station:FindFirstChildOfClass("ClickDetector")
               or station:FindFirstChild("ClickDetector", true)
    if click then return fireClickDetector(click) end
    return fireButton(station)
end

-- Auto Carry + Auto Sell loop.
task.spawn(function()
    while true do
        task.wait(math.max(1, Config.AutoSellDelay))
        if not Config.AutoCarryBox and not Config.AutoSellBox then continue end
        if boxHandlingActive then continue end

        boxHandlingActive = true

        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then
            boxHandlingActive = false
            continue
        end

        local savedCFrame = root.CFrame

        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            boxHandlingActive = false
            continue
        end

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

        local charBox = getCharacterBox()
        if charBox then
            if Config.AutoSellBox then
                doSellAtStation()
                task.wait(0.3)
            end
            pcall(function() humanoid:UnequipTools() end)
            task.wait(0.1)
        end

        local existingBoxes = getBackpackBoxes()
        if #existingBoxes > 0 then
            local boxTool = existingBoxes[1]
            if boxTool and boxTool.Parent then
                equipAndSell(boxTool)
            end

        elseif Config.AutoCarryBox then
            local carryInteraction = findOneCarryInteractionOnPlot()
            if carryInteraction then
                local interactParent = carryInteraction.Parent
                if interactParent then
                    teleportNear(getCFrameOf(interactParent))
                end
                task.wait(0.35)  -- let the server register the new position before interacting

                if carryInteraction:IsA("ProximityPrompt") then
                    firePrompt(carryInteraction)
                elseif carryInteraction:IsA("ClickDetector") then
                    fireClickDetector(carryInteraction)
                end
                task.wait(0.5)  -- increased from 0.4 to give the server time to give us the box

                local acquired = getCharacterBox()
                if acquired then
                    if Config.AutoSellBox then
                        doSellAtStation()
                        task.wait(0.3)
                    end
                    pcall(function() humanoid:UnequipTools() end)
                    task.wait(0.1)
                else
                    local newBoxes = getBackpackBoxes()
                    if #newBoxes > 0 then
                        local b = newBoxes[1]
                        if b and b.Parent then equipAndSell(b) end
                    end
                end
            end
        end

        local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if r then pcall(function() r.CFrame = savedCFrame end) end

        boxHandlingActive = false
    end
end)

-- ── Card Slot helpers ────────────────────────────────────────
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

-- Daily rewards
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

-- Auto Buy Boost
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

findSlotButton = function(slotModel, buttonName)
    if not slotModel then return nil end
    local lname = string.lower(buttonName)
    for _, desc in ipairs(slotModel:GetDescendants()) do
        if string.find(string.lower(desc.Name), lname, 1, true) then
            local cd = desc:FindFirstChildOfClass("ClickDetector")
                    or desc:FindFirstChildOfClass("ProximityPrompt")
            if cd then return cd end
            if desc:IsA("ClickDetector") or desc:IsA("ProximityPrompt") then
                return desc
            end
        end
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

local function getFilteredPacksInBackpack()
    local result = {}
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return result end
    for _, item in ipairs(backpack:GetChildren()) do
        if not item:IsA("Tool") then continue end
        local handle = item:FindFirstChild("Handle")
        if handle and handle:FindFirstChild("Box") then continue end
        local lname = string.lower(item.Name)
        local isPack = false
        for _, packName in ipairs(PACKS) do
            if string.find(lname, string.lower(packName), 1, true) then
                isPack = true ; break
            end
        end
        if not isPack then continue end
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

local function getSortedCardsInBackpack()
    local result = {}
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return result end
    for _, item in ipairs(backpack:GetChildren()) do
        if not item:IsA("Tool") then continue end
        local handle = item:FindFirstChild("Handle")
        if handle and handle:FindFirstChild("Box") then continue end
        local lname = string.lower(item.Name)
        local isPack = false
        for _, packName in ipairs(PACKS) do
            if string.find(lname, string.lower(packName), 1, true) then
                isPack = true ; break
            end
        end
        if isPack then continue end
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
            for _ = 1, 12 do
                if pack.Parent == char then break end
                task.wait(0.1)
            end
            teleportNear(getCFrameOf(slot))
            task.wait(0.2)  -- let the server register the new position
            local btn = findSlotInteraction(slot, { "Place", "Insert", "Add" })
            local fired = false
            if btn then
                fired = fireSlotButton(btn)
            end

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
            task.wait(0.2)  -- let the server register the new position
            local fired = fireSlotButton(btn)
            -- fallback: fire the remote directly if the button didn't work
            if not fired then
                local slotIndex = getCardSlotIndex(slot)
                if slotIndex then
                    fireRemote("CardSlotRE", "Open", { SlotIndex = slotIndex })
                end
            end
            task.wait(Config.CardActionDelay)
        end

        local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if r then pcall(function() r.CFrame = savedCFrame end) end
    end
end)

-- ── Equip Best Card ───────────────────────────────────────────
doEquipBestCards = function(slotLimit)
    local char     = player.Character
    local root     = char and char:FindFirstChild("HumanoidRootPart")
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not humanoid or not root then return end

    local savedCFrame = root.CFrame

    local slots = getAllCardSlots()
    for _, slot in ipairs(slots) do
        local slotIndex = getCardSlotIndex(slot)
        if not slotIndex then continue end
        if slotLimit and slotIndex > slotLimit then continue end
        if slotIsOnCooldown(slot) then continue end
        local removeBtn = findSlotButton(slot, "Remove")
        if not removeBtn then continue end
        teleportNear(getCFrameOf(slot))
        task.wait(0.2)  -- let the server register the new position
        local didRemove = fireSlotButton(removeBtn)
        if not didRemove then
            local slotIndex2 = getCardSlotIndex(slot)
            if slotIndex2 then
                fireRemote("CardSlotRE", "Remove", { SlotIndex = slotIndex2 })
            end
        end
        task.wait(CARD_REMOVAL_DELAY)
    end
    task.wait(Config.CardActionDelay)

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
        task.wait(0.2)  -- let the server register the new position
        local placeBtn = findSlotButton(slot, "Place")
        if placeBtn then
            fireSlotButton(placeBtn)
            task.wait(Config.CardActionDelay)
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

    restoreCharacterPosition(savedCFrame)
    local placedCount = cardIdx - 1
    notify("Equip Best Card", "Done! Placed " .. placedCount .. " card(s).")
    return placedCount
end

removeAllCards = function(limit)
    local char     = player.Character
    local root     = char and char:FindFirstChild("HumanoidRootPart")
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not humanoid or not root then return 0 end

    local savedCFrame = root.CFrame
    local removed = 0

    local slots = getAllCardSlots()
    for _, slot in ipairs(slots) do
        local slotIndex = getCardSlotIndex(slot)
        if not slotIndex then continue end
        if limit and slotIndex > limit then continue end
        if slotIsOnCooldown(slot) then continue end
        local removeBtn = findSlotButton(slot, "Remove")
        if not removeBtn then continue end
        teleportNear(getCFrameOf(slot))
        task.wait(0.2)  -- let the server register the new position
        local didRemove = fireSlotButton(removeBtn)
        -- fallback: fire the remote directly if the button didn't work
        if not didRemove then
            local slotIndex = getCardSlotIndex(slot)
            if slotIndex then
                didRemove = fireRemote("CardSlotRE", "Remove", { SlotIndex = slotIndex })
            end
        end
        if didRemove then
            removed = removed + 1
        end
        task.wait(CARD_REMOVAL_DELAY)
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

task.spawn(function()
    while true do
        task.wait(1.5)
        if combatBusy or Config.AutoTeamCardCycle then continue end
        if not Config.AutoInfinityTower then continue end
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
--  Config Manager State & Helper Functions
-- ══════════════════════════════════════════════════════════════
local ConfigManager = {
    ConfigName        = "",
    SelectedConfig    = nil,
    CurrentAutoload   = nil,
    IsLoading         = false,
    Dropdown          = nil,
    AutoloadParagraph = nil,
}

local CONFIG_ROOT   = "Jon Yuero Hub/Anime Card Farm"
local CONFIG_FOLDER = CONFIG_ROOT .. "/Settings"
local AUTOLOAD_FILE = CONFIG_ROOT .. "/autoload.json"

-- Check file system support
local FS_SUPPORTED = (
    type(makefolder) == "function" and
    type(isfolder)   == "function" and
    type(writefile)  == "function" and
    type(readfile)   == "function" and
    type(isfile)     == "function" and
    type(listfiles)  == "function" and
    type(delfile)    == "function"
)

local function sanitizeConfigName(name)
    name = tostring(name)
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    name = name:gsub('[\\/:*?"<>|]', "_")
    name = name:gsub("%.%.", "_")
    name = name:gsub("^%.", ""):gsub("%.$", "")
    if #name > 40 then name = name:sub(1, 40) end
    return name
end

local function ensureConfigFolders()
    if not FS_SUPPORTED then return false end
    pcall(function()
        if not isfolder("Jon Yuero Hub")     then makefolder("Jon Yuero Hub")     end
        if not isfolder(CONFIG_ROOT)         then makefolder(CONFIG_ROOT)         end
        if not isfolder(CONFIG_FOLDER)       then makefolder(CONFIG_FOLDER)       end
    end)
    return true
end

-- Safely extract a plain string from whatever the dropdown callback returns
-- (Rayfield single-select sometimes still delivers a 1-element table)
local function resolveConfigName(v)
    if type(v) == "table" then
        v = v[1]
    end
    if type(v) ~= "string" then return nil end
    v = v:gsub("^%s+", ""):gsub("%s+$", "")
    if v == "" then return nil end
    return v
end

local function buildSerializableConfig()
    return {
        AutoSpawnPack     = Config.AutoSpawnPack,
        SpawnDelay        = Config.SpawnDelay,
        AutoStopSpawn     = Config.AutoStopSpawn,
        AutoBuyMatching   = Config.AutoBuyMatching,
        AutoContinueSpawn = Config.AutoContinueSpawn,
        AutoCarryBox      = Config.AutoCarryBox,
        AutoSellBox       = Config.AutoSellBox,
        AutoSellDelay     = Config.AutoSellDelay,
        SelectedRarities  = Config.SelectedRarities,
        SelectedMutations = Config.SelectedMutations,
        SelectedPacks     = Config.SelectedPacks,
        AutoUpgrade       = Config.AutoUpgrade,
        UpgradeDelay      = Config.UpgradeDelay,
        CardActionDelay   = Config.CardActionDelay,
        AutoSell          = Config.AutoSell,
        AutoTraitRoll     = Config.AutoTraitRoll,
        AutoClaimPlaytime = Config.AutoClaimPlaytime,
        AutoClaimDaily    = Config.AutoClaimDaily,
        AutoPlacePack     = Config.AutoPlacePack,
        AutoOpenPack      = Config.AutoOpenPack,
        AutoBuyBoost      = Config.AutoBuyBoost,
        AutoInfinityEquip = Config.AutoInfinityEquip,
        AutoInfinityTower = Config.AutoInfinityTower,
        AutoInfinityHide  = Config.AutoInfinityHide,
        RaidDifficulties  = Config.RaidDifficulties,
        AutoRaidEquip     = Config.AutoRaidEquip,
        AutoRaid          = Config.AutoRaid,
        AutoRaidHide      = Config.AutoRaidHide,
        AutoTeamCardCycle = Config.AutoTeamCardCycle,
        AutoPotion        = Config.AutoPotion,
        SelectedPotions   = Config.SelectedPotions,
        SelectedBoosts    = Config.SelectedBoosts,
        AntiAfk           = Config.AntiAfk,
    }
end

local function configExists(name)
    if not FS_SUPPORTED then return false end
    return isfile(CONFIG_FOLDER .. "/" .. name .. ".json")
end

local function saveConfig(name, allowOverwrite)
    if not FS_SUPPORTED then
        Rayfield:Notify({
            Title    = "Unsupported Executor",
            Content  = "File storage is unavailable in this executor.",
            Duration = 5,
        })
        return false
    end
    ensureConfigFolders()
    local filePath = CONFIG_FOLDER .. "/" .. name .. ".json"
    if not allowOverwrite and isfile(filePath) then
        Rayfield:Notify({
            Title    = "Config Already Exists",
            Content  = name .. " already exists. Use Overwrite to replace it.",
            Duration = 4,
        })
        return false
    end
    local data = buildSerializableConfig()
    local HttpService = game:GetService("HttpService")
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
    if not ok then return false end
    pcall(writefile, filePath, encoded)
    return true
end

local function normalizeLoadedSelection(value)
    if type(value) == "table" then return value end
    if value == nil then return {} end
    return { tostring(value) }
end

local function getAutoload()
    if not FS_SUPPORTED then return nil end
    if not isfile(AUTOLOAD_FILE) then return nil end
    local ok, raw = pcall(readfile, AUTOLOAD_FILE)
    if not ok or not raw or raw == "" then return nil end
    local HttpService = game:GetService("HttpService")
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok2 or type(data) ~= "table" then return nil end
    local configName = data.config
    if type(configName) ~= "string" or configName == "" then return nil end
    return configName
end

local function refreshConfigList()
    if not FS_SUPPORTED then return end
    ensureConfigFolders()
    local files = {}
    pcall(function()
        files = listfiles(CONFIG_FOLDER) or {}
    end)
    local names = {}
    for _, filePath in ipairs(files) do
        local name = tostring(filePath):match("([^/\\]+)%.json$")
        if name then table.insert(names, name) end
    end
    table.sort(names)
    ConfigManager.ConfigNames = names

    if ConfigManager.Dropdown then
        -- Try Refresh (newer Rayfield) first, fall back to Set
        local ok = pcall(function()
            ConfigManager.Dropdown:Refresh(names, ConfigManager.SelectedConfig or "")
        end)
        if not ok then
            pcall(function()
                ConfigManager.Dropdown:Set(names)
            end)
        end
        -- Validate current selection still exists
        local current = ConfigManager.SelectedConfig
        if current then
            local found = false
            for _, n in ipairs(names) do
                if n == current then found = true ; break end
            end
            if not found then
                ConfigManager.SelectedConfig = nil
            end
        end
    end
end

local function loadConfig(name, isAutoload)
    if not FS_SUPPORTED then return false end
    if not name or name == "" then return false end
    local filePath = CONFIG_FOLDER .. "/" .. name .. ".json"
    if not isfile(filePath) then
        if not isAutoload then
            Rayfield:Notify({
                Title    = "Configuration Not Found",
                Content  = name .. " does not exist.",
                Duration = 4,
            })
        end
        return false
    end
    local ok, raw = pcall(readfile, filePath)
    if not ok or not raw or raw == "" then return false end
    local HttpService = game:GetService("HttpService")
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok2 or type(data) ~= "table" then return false end

    ConfigManager.IsLoading = true

    local knownKeys = {
        "AutoSpawnPack", "SpawnDelay", "AutoStopSpawn", "AutoBuyMatching",
        "AutoCarryBox", "AutoSellBox", "AutoSellDelay",
        "SelectedRarities", "SelectedMutations", "SelectedPacks",
        "AutoUpgrade", "UpgradeDelay", "CardActionDelay", "AutoSell",
        "AutoTraitRoll", "AutoClaimPlaytime", "AutoClaimDaily",
        "AutoPlacePack", "AutoOpenPack", "AutoBuyBoost",
        "AutoInfinityEquip", "AutoInfinityTower", "AutoInfinityHide",
        "RaidDifficulties", "AutoRaidEquip", "AutoRaid", "AutoRaidHide",
        "AutoTeamCardCycle", "AutoPotion", "SelectedPotions",
        "SelectedBoosts", "AntiAfk", "AutoContinueSpawn",
    }

    for _, key in ipairs(knownKeys) do
        if data[key] ~= nil then
            local value = data[key]
            Config[key] = value
            local control = Controls[key]
            if control and control.Set then
                pcall(function() control:Set(value) end)
            end
        end
    end

    ConfigManager.IsLoading = false

    if not isAutoload then
        Rayfield:Notify({
            Title    = "Configuration Loaded",
            Content  = name .. " was loaded successfully.",
            Duration = 4,
        })
    end
    return true
end

local function deleteConfig(name)
    if not FS_SUPPORTED then return false end
    if not name or name == "" then return false end
    local filePath = CONFIG_FOLDER .. "/" .. name .. ".json"
    if not isfile(filePath) then return false end
    pcall(delfile, filePath)

    local currentAutoload = getAutoload()
    if currentAutoload == name then
        pcall(function()
            if isfile(AUTOLOAD_FILE) then
                delfile(AUTOLOAD_FILE)
            end
        end)
        ConfigManager.CurrentAutoload = nil
        if ConfigManager.AutoloadParagraph then
            pcall(function()
                ConfigManager.AutoloadParagraph:Set({
                    Title   = "Current Autoload",
                    Content = "None",
                })
            end)
        end
    end
    return true
end

local function setAutoload(name)
    if not FS_SUPPORTED then return false end
    if not name or name == "" then return false end
    local filePath = CONFIG_FOLDER .. "/" .. name .. ".json"
    if not isfile(filePath) then return false end
    ensureConfigFolders()
    local HttpService = game:GetService("HttpService")
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, { config = name })
    if not ok then return false end
    pcall(writefile, AUTOLOAD_FILE, encoded)
    ConfigManager.CurrentAutoload = name
    if ConfigManager.AutoloadParagraph then
        pcall(function()
            ConfigManager.AutoloadParagraph:Set({
                Title   = "Current Autoload",
                Content = name,
            })
        end)
    end
    return true
end

local function resetAutoload()
    if not FS_SUPPORTED then return end
    pcall(function()
        if isfile(AUTOLOAD_FILE) then
            delfile(AUTOLOAD_FILE)
        end
    end)
    ConfigManager.CurrentAutoload = nil
    if ConfigManager.AutoloadParagraph then
        pcall(function()
            ConfigManager.AutoloadParagraph:Set({
                Title   = "Current Autoload",
                Content = "None",
            })
        end)
    end
end

-- ══════════════════════════════════════════════════════════════
--  Rayfield Window
-- ══════════════════════════════════════════════════════════════
local windowTitle = isPremium
    and "👑 Jon Yuero Hub | Anime Card Farm"
    or  "Jon Yuero Hub | Anime Card Farm"

local Window = Rayfield:CreateWindow({
    Name            = windowTitle,
    LoadingTitle    = "Anime Card Farm",
    LoadingSubtitle = "Loading...",
    Icon            = 0,
    ConfigurationSaving = {
        Enabled = false,
    },
    Discord   = { Enabled = false },
    KeySystem = false,
})

-- ══════════════════════════════════════════════════════════════
--  TAB 1 – Auto Spawn Pack
-- ══════════════════════════════════════════════════════════════
local spawnTab = Window:CreateTab("🃏 Auto Spawn Pack", 0)

spawnTab:CreateSection("Spawn Manager")

Controls.AutoSpawnPack = spawnTab:CreateToggle({
    Name         = "Auto Spawn Pack",
    CurrentValue = Config.AutoSpawnPack,
    Flag         = "AutoSpawnPack",
    Callback     = function(v)
        Config.AutoSpawnPack = v
        if v then autoStopHandled = false end   -- reset guard on manual re-enable
    end,
})

Controls.SpawnDelay = spawnTab:CreateSlider({
    Name         = "How Fast to Spawn (s)",
    Range        = { 0.05, 10 },
    Increment    = 0.05,
    Suffix       = "s",
    CurrentValue = Config.SpawnDelay,
    Flag         = "SpawnDelay",
    Callback     = function(v) Config.SpawnDelay = v end,
})

Controls.AutoStopSpawn = spawnTab:CreateToggle({
    Name         = "Auto Stop Spawn (on Filter Match)",
    CurrentValue = Config.AutoStopSpawn,
    Flag         = "AutoStopSpawn",
    Callback     = function(v) Config.AutoStopSpawn = v end,
})

Controls.AutoBuyMatching = spawnTab:CreateToggle({
    Name         = "Auto Buy Pack (Using Filter)",
    CurrentValue = Config.AutoBuyMatching,
    Flag         = "AutoBuyMatching",
    Callback     = function(v) Config.AutoBuyMatching = v end,
})

Controls.AutoContinueSpawn = spawnTab:CreateToggle({
    Name         = "Auto Continue",
    CurrentValue = Config.AutoContinueSpawn,
    Flag         = "AutoContinueSpawn",
    Callback     = function(v) Config.AutoContinueSpawn = v end,
})

spawnTab:CreateSection("Filters")

local packOptions = { "Any" }
for _, p in ipairs(PACKS) do table.insert(packOptions, p) end

Controls.SelectedPacks = spawnTab:CreateDropdown({
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

Controls.SelectedRarities = spawnTab:CreateDropdown({
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

Controls.SelectedMutations = spawnTab:CreateDropdown({
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

-- ══════════════════════════════════════════════════════════════
--  TAB 2 – Cards
-- ══════════════════════════════════════════════════════════════
local cardsTab = Window:CreateTab("⬆️ Cards", 0)

cardsTab:CreateSection("Card Management")

cardsTab:CreateParagraph({
    Title   = "Auto Place Pack Filter",
    Content = "Uses the same Pack / Rarity / Mutation filters set in the Auto Spawn Pack tab.",
})

cardsTab:CreateToggle({
    Name         = "Auto Place Pack",
    CurrentValue = Config.AutoPlacePack,
    Flag         = "AutoPlacePack",
    Callback     = function(v) Config.AutoPlacePack = v end,
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

cardsTab:CreateSection("Upgrade")

Controls.AutoUpgrade = cardsTab:CreateToggle({
    Name         = "Auto Upgrade Cards",
    CurrentValue = Config.AutoUpgrade,
    Flag         = "AutoUpgrade",
    Callback     = function(v) Config.AutoUpgrade = v end,
})

Controls.UpgradeDelay = cardsTab:CreateSlider({
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
local autoSellTab = Window:CreateTab("📦 Auto Sell", 0)

autoSellTab:CreateSection("Box Handling")

Controls.AutoCarryBox = autoSellTab:CreateToggle({
    Name         = "Auto Carry Box",
    CurrentValue = Config.AutoCarryBox,
    Flag         = "AutoCarryBox",
    Callback     = function(v) Config.AutoCarryBox = v end,
})

Controls.AutoSellBox = autoSellTab:CreateToggle({
    Name         = "Auto Sell Box",
    CurrentValue = Config.AutoSellBox,
    Flag         = "AutoSellBox",
    Callback     = function(v) Config.AutoSellBox = v end,
})

Controls.AutoSellDelay = autoSellTab:CreateSlider({
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
local combatTab = Window:CreateTab("⚔️ Combat", 0)

combatTab:CreateSection("Infinity Tower")

combatTab:CreateToggle({
    Name         = "Auto Equip Best Card",
    CurrentValue = Config.AutoInfinityEquip,
    Flag         = "AutoInfinityEquip",
    Callback     = function(v) Config.AutoInfinityEquip = v end,
})

Controls.AutoInfinityTower = combatTab:CreateToggle({
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

Controls.RaidDifficulties = combatTab:CreateDropdown({
    Name          = "Select Difficulty",
    Options       = raidDifficultyOptions,
    CurrentOption = Config.RaidDifficulties[1] or "Easy",
    MultipleOptions = false,
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

Controls.AutoRaid = combatTab:CreateToggle({
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
local rerollTab = Window:CreateTab("🔄 Reroll", 0)

rerollTab:CreateSection("Traits")

Controls.AutoTraitRoll = rerollTab:CreateToggle({
    Name         = "Auto Trait Roll",
    CurrentValue = Config.AutoTraitRoll,
    Flag         = "AutoTraitRoll",
    Callback     = function(v) Config.AutoTraitRoll = v end,
})

-- ══════════════════════════════════════════════════════════════
--  TAB 6 – Misc
-- ══════════════════════════════════════════════════════════════
local miscTab = Window:CreateTab("🧪 Misc", 0)

miscTab:CreateSection("Potions")

local potionOptions = { "All" }
for _, potion in ipairs(POTIONS) do
    table.insert(potionOptions, potion)
end

Controls.SelectedPotions = miscTab:CreateDropdown({
    Name            = "Owned Potions",
    Options         = potionOptions,
    CurrentOption   = collapseFullSelection(Config.SelectedPotions, POTIONS),
    MultipleOptions = true,
    Flag            = "SelectedPotions",
    Callback        = function(v)
        Config.SelectedPotions = collapseFullSelection(v, POTIONS)
    end,
})

Controls.AutoPotion = miscTab:CreateToggle({
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

Controls.SelectedBoosts = miscTab:CreateDropdown({
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

miscTab:CreateSection("Anti-AFK")

Controls.AntiAfk = miscTab:CreateToggle({
    Name         = "Anti-AFK",
    CurrentValue = Config.AntiAfk,
    Flag         = "AntiAfk",
    Callback     = function(v) Config.AntiAfk = v end,
})

miscTab:CreateSection("Player Rewards")

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

-- ══════════════════════════════════════════════════════════════
--  TAB 7 – Settings
-- ══════════════════════════════════════════════════════════════
local settingsTab = Window:CreateTab("⚙️ Settings", 0)

settingsTab:CreateSection("Configuration Manager")

-- Config Name input
settingsTab:CreateInput({
    Name                     = "Config Name",
    PlaceholderText          = "Enter configuration name...",
    RemoveTextAfterFocusLost = false,
    Flag                     = "ConfigManagerName",
    Callback                 = function(v)
        v = tostring(v):gsub("^%s+", ""):gsub("%s+$", "")
        ConfigManager.ConfigName = v
    end,
})

-- Save button
settingsTab:CreateButton({
    Name     = "Save",
    Callback = function()
        local rawName = ConfigManager.ConfigName or ""
        rawName = rawName:gsub("^%s+", ""):gsub("%s+$", "")
        local name = sanitizeConfigName(rawName)
        if name == "" then
            Rayfield:Notify({
                Title    = "Invalid Name",
                Content  = "Enter a valid configuration name.",
                Duration = 4,
            })
            return
        end
        if not FS_SUPPORTED then
            Rayfield:Notify({
                Title    = "Unsupported Executor",
                Content  = "File storage is unavailable in this executor.",
                Duration = 5,
            })
            return
        end
        -- saveConfig(name, false) = do NOT overwrite if already exists
        if saveConfig(name, false) then
            refreshConfigList()
            ConfigManager.SelectedConfig = name
            Rayfield:Notify({
                Title    = "Configuration Saved",
                Content  = name .. " was saved successfully.",
                Duration = 4,
            })
        end
    end,
})

-- Load initial config names for the dropdown
local function getInitialConfigNames()
    if not FS_SUPPORTED then return {} end
    ensureConfigFolders()
    local files = {}
    pcall(function() files = listfiles(CONFIG_FOLDER) or {} end)
    local names = {}
    for _, filePath in ipairs(files) do
        local name = tostring(filePath):match("([^/\\]+)%.json$")
        if name then table.insert(names, name) end
    end
    table.sort(names)
    return names
end

-- Select Config dropdown
ConfigManager.Dropdown = settingsTab:CreateDropdown({
    Name            = "Select Config",
    Options         = getInitialConfigNames(),
    CurrentOption   = {},
    MultipleOptions = false,
    Flag            = "ConfigManagerSelected",
    Callback        = function(v)
        -- Rayfield single-select may still deliver a table; normalize to string
        ConfigManager.SelectedConfig = resolveConfigName(v)
    end,
})

-- Refresh List button
settingsTab:CreateButton({
    Name     = "Refresh List",
    Callback = function()
        refreshConfigList()
        Rayfield:Notify({
            Title    = "Config List Refreshed",
            Content  = "The configuration list has been updated.",
            Duration = 3,
        })
    end,
})

-- Load button
settingsTab:CreateButton({
    Name     = "Load",
    Callback = function()
        local name = resolveConfigName(ConfigManager.SelectedConfig)
        if not name then
            Rayfield:Notify({
                Title    = "No Configuration Selected",
                Content  = "Select a saved configuration first.",
                Duration = 4,
            })
            return
        end
        loadConfig(name, false)
    end,
})

-- Overwrite button
settingsTab:CreateButton({
    Name     = "Overwrite",
    Callback = function()
        local name = resolveConfigName(ConfigManager.SelectedConfig)
        if not name then
            Rayfield:Notify({
                Title    = "No Configuration Selected",
                Content  = "Select a saved configuration first.",
                Duration = 4,
            })
            return
        end
        if not FS_SUPPORTED then
            Rayfield:Notify({
                Title    = "Unsupported Executor",
                Content  = "File storage is unavailable in this executor.",
                Duration = 5,
            })
            return
        end
        -- saveConfig(name, true) = allow overwrite
        if saveConfig(name, true) then
            refreshConfigList()
            Rayfield:Notify({
                Title    = "Configuration Overwritten",
                Content  = name .. " was overwritten successfully.",
                Duration = 4,
            })
        end
    end,
})

-- Delete button
settingsTab:CreateButton({
    Name     = "Delete",
    Callback = function()
        local name = resolveConfigName(ConfigManager.SelectedConfig)
        if not name then
            Rayfield:Notify({
                Title    = "No Configuration Selected",
                Content  = "Select a saved configuration first.",
                Duration = 4,
            })
            return
        end
        if deleteConfig(name) then
            ConfigManager.SelectedConfig = nil
            refreshConfigList()
            Rayfield:Notify({
                Title    = "Configuration Deleted",
                Content  = name .. " was deleted.",
                Duration = 4,
            })
        end
    end,
})

-- Set as Autoload button
settingsTab:CreateButton({
    Name     = "Set as Autoload",
    Callback = function()
        local name = resolveConfigName(ConfigManager.SelectedConfig)
        if not name then
            Rayfield:Notify({
                Title    = "No Configuration Selected",
                Content  = "Select a saved configuration first.",
                Duration = 4,
            })
            return
        end
        if not FS_SUPPORTED then
            Rayfield:Notify({
                Title    = "Unsupported Executor",
                Content  = "File storage is unavailable in this executor.",
                Duration = 5,
            })
            return
        end
        if setAutoload(name) then
            Rayfield:Notify({
                Title    = "Autoload Enabled",
                Content  = name .. " will load automatically.",
                Duration = 4,
            })
        end
    end,
})

-- Reset Autoload button
settingsTab:CreateButton({
    Name     = "Reset Autoload",
    Callback = function()
        resetAutoload()
        Rayfield:Notify({
            Title    = "Autoload Reset",
            Content  = "No configuration will load automatically.",
            Duration = 4,
        })
    end,
})

-- Current Autoload paragraph
ConfigManager.AutoloadParagraph = settingsTab:CreateParagraph({
    Title   = "Current Autoload",
    Content = "None",
})

-- ── Post-UI startup: refresh config list and run autoload ─────
task.spawn(function()
    if not FS_SUPPORTED then
        Rayfield:Notify({
            Title    = "Unsupported Executor",
            Content  = "File storage is unavailable. Config saving is disabled.",
            Duration = 6,
        })
        return
    end

    refreshConfigList()

    local autoloadName = getAutoload()
    if autoloadName and autoloadName ~= "" then
        ConfigManager.CurrentAutoload = autoloadName
        if ConfigManager.AutoloadParagraph then
            pcall(function()
                ConfigManager.AutoloadParagraph:Set({
                    Title   = "Current Autoload",
                    Content = autoloadName,
                })
            end)
        end
        task.wait(1)
        if loadConfig(autoloadName, true) then
            notify("Configuration Loaded", autoloadName .. " loaded automatically.")
        end
    end
end)

-- ── Done ─────────────────────────────────────────────────────
task.wait(1)
notify("Anime Card Farm", "Loaded! (" .. userRole .. ")")
