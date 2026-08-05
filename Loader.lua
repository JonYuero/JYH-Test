-- ============================================================
--  Anime Card Farm — Loader
--  Rayfield key-system + per-game script launcher.
-- ============================================================

-- ── Services ─────────────────────────────────────────────────
local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local StarterGui  = game:GetService("StarterGui")

local player = Players.LocalPlayer

-- ── Core notify (fallback before Rayfield is ready) ──────────
local function coreNotify(title, text)
    pcall(StarterGui.SetCore, StarterGui, "SendNotification", {
        Title = title, Text = text, Duration = 4,
    })
end

-- ── Load Rayfield ─────────────────────────────────────────────
local Rayfield
for _, url in ipairs({
    "https://sirius.menu/rayfield",
    "https://raw.githubusercontent.com/UI-Hub/Rayfield/main/source",
    "https://raw.githubusercontent.com/shlexware/Rayfield/main/source",
}) do
    local ok, result = pcall(function()
        return loadstring(game:HttpGet(url, true))()
    end)
    if ok and result then Rayfield = result ; break end
end
if not Rayfield then
    error("[Loader] Could not load Rayfield. Check your executor's HTTP settings.")
end

-- ── Game ID → hosted script URL ──────────────────────────────
-- Add one entry per game.  The loader fetches and runs the correct
-- script after a successful authentication.
local GAME_SCRIPTS = {
    -- Anime Card Farm (replace with your real raw-file URL)
    [125039473548047] = "https://raw.githubusercontent.com/JonYuero/Anime-Card-Farm/8adba7bd78100261180663e7e3c4541ccd2eea48/JYHub.lua",

    -- Add more games:
    -- [PLACE_ID] = "https://...",
}

-- ── Auth constants ────────────────────────────────────────────
local AUTH_ENDPOINT = "https://animecardfarm-api.jonyuerohub-api.workers.dev/api/v1/key/authenticate"
local FREE_KEY_URL  = "https://work.ink/2O9J/jonyuerohub-free-key"
-- clientId is built from the Roblox user ID — never entered by the user.
local CLIENT_ID     = "ROBLOX-USER-" .. tostring(player.UserId)

-- ── Cross-executor HTTP helper ────────────────────────────────
local function httpRequest(opts)
    if syn and syn.request       then return syn.request(opts)   end
    if request                   then return request(opts)        end
    if http and http.request     then return http.request(opts)   end
    if http_request              then return http_request(opts)   end
    return nil
end

-- ── Script launcher ───────────────────────────────────────────
local function launchScript(url)
    local ok, raw = pcall(game.HttpGet, game, url, true)
    if not ok or not raw or raw == "" then
        coreNotify("Loader Error", "Could not fetch game script. Check the URL in Loader.lua.")
        warn("[Loader] HttpGet failed: " .. tostring(raw))
        return
    end
    local fn, err = loadstring(raw)
    if not fn then
        coreNotify("Loader Error", "Script compile error — see output.")
        warn("[Loader] loadstring error: " .. tostring(err))
        return
    end
    task.spawn(fn)
end

-- ── Expiry display helper ─────────────────────────────────────
-- Returns a human-readable expiry string.
-- Accepts an ISO-8601 date string, a Unix timestamp string, or "Never".
local function formatExpiry(expiresAt, licenseType)
    local t = tostring(expiresAt or "")

    if licenseType == "LIFETIME" or t == "" or t == "Never" or t == "never" then
        return "Never"
    end

    -- Try Unix timestamp (seconds since epoch)
    local unix = tonumber(t)
    if unix then
        -- os.time() is not available in Roblox; approximate with tick()
        local remaining = unix - tick()
        if remaining <= 0 then return "Expired" end
        local days    = math.floor(remaining / 86400)
        local hours   = math.floor((remaining % 86400) / 3600)
        if days > 0 then
            return t .. "  (" .. days .. "d " .. hours .. "h remaining)"
        else
            return t .. "  (" .. hours .. "h remaining)"
        end
    end

    -- ISO-8601 rough parse: "2025-08-05T12:00:00Z"
    local y, mo, d, h, mi = t:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
    if y then
        local display = d .. "/" .. mo .. "/" .. y .. " " .. h .. ":" .. mi .. " UTC"
        return display
    end

    -- Unknown format — show as-is
    return t
end

-- ══════════════════════════════════════════════════════════════
--  Rayfield Window  (key system only; farming UI loads after auth)
-- ══════════════════════════════════════════════════════════════
local Window = Rayfield:CreateWindow({
    Name                = "Anime Card Farm",
    LoadingTitle        = "Anime Card Farm",
    LoadingSubtitle     = "License Required",
    ConfigurationSaving = { Enabled = false },
    Discord             = { Enabled = false },
    KeySystem           = false,
})

local KeyTab = Window:CreateTab("🔑 Key System", 4483362458)

-- ── Status area (single message, updated in-place) ───────────
-- One status message shown at a time, as required.
local statusParagraph = KeyTab:CreateParagraph({
    Title   = "Status",
    Content = "Enter your license key and click Authenticate.",
})

local function setStatus(title, content)
    pcall(function()
        statusParagraph:Set({ Title = title, Content = content })
    end)
end

-- ── Authentication section ────────────────────────────────────
KeyTab:CreateSection("Authentication")

-- Key input — sits directly above the Authenticate button.
local keyInput = ""
KeyTab:CreateInput({
    Name                     = "License Key",
    PlaceholderText          = "Paste your key here...",
    RemoveTextAfterFocusLost = false,
    Flag                     = "LicenseKey",
    Callback = function(v)
        keyInput = tostring(v or ""):match("^%s*(.-)%s*$")
    end,
})

-- Primary Authenticate button (blue, as per requirements).
KeyTab:CreateButton({
    Name     = "Authenticate",
    Callback = function()
        local key = keyInput

        if key == "" then
            setStatus("No Key Entered", "Paste your license key into the input above first.")
            return
        end

        -- ── Loading state ─────────────────────────────────────
        setStatus("Checking license...", "Contacting authentication server — please wait.")

        task.spawn(function()

            -- Encode payload  (field is "licenseKey" per API spec)
            local payload
            local encOk, encResult = pcall(HttpService.JSONEncode, HttpService, {
                licenseKey = key,
                clientId   = CLIENT_ID,
            })
            if not encOk then
                setStatus("Internal Error", "Failed to encode request. See output log.")
                warn("[Loader] JSONEncode error: " .. tostring(encResult))
                return
            end
            payload = encResult

            -- Send HTTP auth request
            local response
            local reqOk, reqErr = pcall(function()
                response = httpRequest({
                    Url     = AUTH_ENDPOINT,
                    Method  = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body    = payload,
                })
            end)

            -- ── License server unavailable ────────────────────
            if not reqOk or not response then
                setStatus(
                    "License server unavailable",
                    "Could not reach the authentication server.\n"
                    .. "Check your executor's HTTP permissions and try again."
                )
                warn("[Loader] HTTP request error: " .. tostring(reqErr))
                return
            end

            -- ── Invalid server response ───────────────────────
            local data = {}
            local parseOk, parseErr = pcall(function()
                data = HttpService:JSONDecode(response.Body or "{}")
            end)
            if not parseOk or type(data) ~= "table" then
                setStatus(
                    "Invalid server response",
                    "The server returned an unexpected response. Try again."
                )
                warn("[Loader] JSONDecode failed: " .. tostring(parseErr)
                    .. "\nBody: " .. tostring(response.Body))
                return
            end

            -- ── Strict success check (data.success == true) ───
            if data.success ~= true then
                local errCode = tostring(data.error or data.message or ""):lower()

                if string.find(errCode, "expired") then
                    setStatus("Key expired",
                        "Your key has expired. Get a new one in the Free Key section below.")

                elseif string.find(errCode, "revok") then
                    setStatus("Key revoked",
                        "This key has been revoked. Contact support or obtain a new key.")

                elseif string.find(errCode, "device") or string.find(errCode, "bound") then
                    setStatus("Bound to another account",
                        "This key is already bound to a different Roblox account.")

                elseif string.find(errCode, "unknown") and string.find(errCode, "type") then
                    setStatus("Unknown license type",
                        "The server returned an unrecognised license type. Contact support.")

                else
                    -- Covers "invalid", "not found", and any other failure.
                    setStatus("Invalid key",
                        "The key you entered is not valid. Double-check it and try again.")
                end

                warn("[Loader] Auth failed — HTTP " .. tostring(response.StatusCode)
                    .. "  body=" .. tostring(response.Body))
                return
            end

            -- ── Auth success ──────────────────────────────────
            -- Normalise license type to uppercase (FREE / 30D / LIFETIME).
            local rawType   = tostring(data.licenseType or data.type or data.plan or "FREE")
            local licType   = rawType:upper()
            local expiresAt = data.expiresAt or data.expires_at or data.expiry
            local expiryStr = formatExpiry(expiresAt, licType)

            -- Friendly display label
            local typeLabel = licType == "LIFETIME" and "Lifetime"
                           or licType == "30D"       and "30-Day"
                           or "FREE (24h)"

            setStatus(
                "✅ License authenticated",
                "License: " .. typeLabel .. "\n"
                .. "Expires: " .. expiryStr
            )

            Rayfield:Notify({
                Title    = "Access Granted",
                Content  = "License: " .. typeLabel .. "  ·  Expires: " .. expiryStr,
                Duration = 5,
            })

            warn("[Loader] " .. player.Name .. " authenticated — Type=" .. licType
                .. "  Expires=" .. expiryStr)

            task.wait(1.5)

            -- Destroy the key window; the farming script opens its own UI.
            pcall(function() Window:Destroy() end)
            task.wait(0.3)

            -- Launch the correct game script
            local placeId   = game.PlaceId
            local scriptUrl = GAME_SCRIPTS[placeId]

            if scriptUrl then
                launchScript(scriptUrl)
            else
                coreNotify(
                    "Loader",
                    "No script configured for Place ID " .. tostring(placeId)
                    .. ". Add it to GAME_SCRIPTS in Loader.lua."
                )
                warn("[Loader] No GAME_SCRIPTS entry for PlaceId=" .. tostring(placeId))
            end
        end)
    end,
})

-- ── Free 24-Hour Key section ──────────────────────────────────
KeyTab:CreateSection("Get FREE 24H Key")

KeyTab:CreateParagraph({
    Title   = "Free Key",
    Content = "A free 24-hour key is available at no cost.\n"
        .. "Click the button below — the link is copied to your clipboard.\n"
        .. "Open it in a browser, complete the short step, and paste your key above.",
})

KeyTab:CreateButton({
    Name     = "Copy Free Key Link",
    Callback = function()
        if setclipboard then
            pcall(setclipboard, FREE_KEY_URL)
            Rayfield:Notify({
                Title    = "Link Copied",
                Content  = "Free key link copied to your clipboard.\n"
                    .. "Open a browser, visit the link, and follow the step to get your key.",
                Duration = 6,
            })
            setStatus("Free key link copied", FREE_KEY_URL)
        else
            -- Executor does not expose setclipboard — show the URL instead.
            setStatus("Your free key link", FREE_KEY_URL)
            Rayfield:Notify({
                Title    = "Free Key Link",
                Content  = FREE_KEY_URL,
                Duration = 10,
            })
        end
    end,
})
