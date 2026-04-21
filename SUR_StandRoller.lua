-- Stand Upright Rebooted | Stand Roller + Webhook

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()

local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local HttpService   = game:GetService("HttpService")
local lp            = Players.LocalPlayer

-- ─── Window ───────────────────────────────────────────────────────────────────

local Window = Fluent:CreateWindow({
    Title       = "SUR Stand Roller",
    SubTitle    = "v2.0",
    TabWidth    = 130,
    Size        = UDim2.fromOffset(460, 420),
    Acrylic     = true,
    Theme       = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

local Options = Fluent.Options

local RollTab       = Window:AddTab({Title = "Roller",    Icon = "star"})
local SpecificTab   = Window:AddTab({Title = "Specific",  Icon = "list"})
local BlacklistTab  = Window:AddTab({Title = "Blacklist", Icon = "slash"})
local WebhookTab    = Window:AddTab({Title = "Webhook",   Icon = "send"})
local ShopTab       = Window:AddTab({Title = "Shop",      Icon = "shopping-cart"})
local AutoTab       = Window:AddTab({Title = "Auto",      Icon = "clock"})
local MiscTab       = Window:AddTab({Title = "Misc",      Icon = "settings"})
local ConfigTab     = Window:AddTab({Title = "Configs",   Icon = "save"})

-- ─── Stand / Attribute data ───────────────────────────────────────────────────

local STAND_IDS = {
    ["King Crimson"]               = "KingCrimson",
    ["Crazy Diamond"]              = "CrazyDiamond",
    ["Hierophant Green"]           = "HG",
    ["Silver Chariot"]             = "SilverChariot",
    ["The World"]                  = "TheWorld",
    ["Dio's The World"]            = "DTW",
    ["Star Platinum"]              = "StarPlatinum",
    ["Killer Queen"]               = "KillerQueen",
    ["Dirty Deeds Done Dirt Cheap"]= "D4C",
    ["White Snake"]                = "WhiteSnake",
    ["Golden Experience"]          = "GE",
    ["Tusk Act1"]                  = "TA1",
    ["The Hand"]                   = "TheHand",
    ["Cream"]                      = "Cream",
    ["Diver Down"]                 = "DiverDown",
    ["Jotaro's Star Platinum"]     = "JotarosStarPlatinum",
    ["Magician's Red"]             = "MagiciansRed",
    ["Sticky Fingers"]             = "StickyFingers",
    ["Premier Macho"]              = "PM",
    ["Putrid Whine"]               = "PutridWhine",
    ["Silver Chariot OVA"]         = "SCOVA",
    ["Star Platinum OVA"]          = "StarPlatinumOVA",
    ["The World OVA"]              = "TWOVA",
    ["Stone Free"]                 = "StoneFree",
    ["The World Alternate Universe"]= "TWAU",
    ["Soft And Wet"]               = "SoftAndWet",
    ["Weather Report"]             = "WeatherReport",
    ["Emperor"]                    = "Emperor",
    ["Aerosmith"]                  = "Aerosmith",
}

local STAND_NAMES = {}
for k in pairs(STAND_IDS) do table.insert(STAND_NAMES, k) end
table.sort(STAND_NAMES)

local ATTRIBUTES = {
    "None","Strong","Tough","Sloppy","Powerful","Manic",
    "Enrage","Lethargic","Godly","Daemon","Invincible",
    "Tragic","Scourge","GlassCannon","Hacker","Legendary",
}

-- ─── State ────────────────────────────────────────────────────────────────────

local rolling        = false
local testRollTarget = 10
local webhookUrl     = ""
local rollCount      = 0
local debugMode      = false
local standDebug     = false
local extendedAttri    = false  -- slow/safe attri wait (toggle); default = fast mode
local customAttriDelay = 0.25  -- seconds; user-adjustable via input
local useCustomDelay   = false -- when true, customAttriDelay overrides everything
local specificStands = {}   -- {name=internalID, attribs={...}} — empty attribs = any attrib
local blacklistStands = {}  -- {name=internalID, attribs={...}} — always Rokaka'd
local pingUserId     = ""   -- Discord user ID for @mentions in alert webhooks
local scriptReady    = false
local shopBusy        = false  -- true while buy/sell is running
local _shopCallActive = false  -- true only while OUR own FireServer is executing

local SPECIFIC_SAVE_FILE  = "SUR_SpecificStands.json"
local BLACKLIST_SAVE_FILE = "SUR_Blacklist.json"
local AUTO_RESTART_FILE   = "SUR_AutoRestart.json"
local SCRIPT_URL          = "https://raw.githubusercontent.com/kaydn31/.scripts/refs/heads/main/SUR_StandRoller.lua"

local function saveSpecificStands()
    pcall(function()
        writefile(SPECIFIC_SAVE_FILE, HttpService:JSONEncode(specificStands))
    end)
end

local function loadSpecificStands()
    pcall(function()
        if isfile(SPECIFIC_SAVE_FILE) then
            local data = HttpService:JSONDecode(readfile(SPECIFIC_SAVE_FILE))
            if type(data) == "table" then
                specificStands = data
            end
        end
    end)
end

loadSpecificStands()

local function saveBlacklistStands()
    pcall(function()
        writefile(BLACKLIST_SAVE_FILE, HttpService:JSONEncode(blacklistStands))
    end)
end

local function loadBlacklistStands()
    pcall(function()
        if isfile(BLACKLIST_SAVE_FILE) then
            local data = HttpService:JSONDecode(readfile(BLACKLIST_SAVE_FILE))
            if type(data) == "table" then blacklistStands = data end
        end
    end)
end

loadBlacklistStands()

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function getCharacter()
    return lp.Character
end

local function notify(title, content, duration)
    Fluent:Notify({Title = title, Content = content, Duration = duration or 3})
end

local function resetCharacter()
    pcall(function() lp:LoadCharacter() end)
end

-- Fires a remote while marking it as ours so the shop blocker lets it through
local function shopFire(remote, ...)
    local args = {...}
    _shopCallActive = true
    local ok, err = pcall(function() remote:FireServer(table.unpack(args)) end)
    _shopCallActive = false
    return ok, err
end

-- Returns true if the player is currently dead or respawning
local function isDead()
    local char = lp.Character
    if not char then return true end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return not hum or hum.Health <= 0
end

-- Waits up to `timeout` seconds for the player to respawn and backpack to repopulate.
-- Returns true if they respawned in time, false if timed out.
local function waitForRespawn()
    if not isDead() then return end
    local respawned = false
    local conn = lp.CharacterAdded:Connect(function() respawned = true end)
    repeat task.wait(0.2) until respawned
    conn:Disconnect()
    task.wait(3)  -- backpack repopulates a couple seconds after spawn
end

-- Find the stand the character currently has equipped/stored.
-- Returns {name, attribute} or nil if none found.
local function getCurrentStand()
    local data = lp:FindFirstChild("Data")
    if not data then return nil end

    local standVal = data:FindFirstChild("Stand")
    if not standVal then return nil end

    local standName = tostring(standVal.Value)
    if standName == "" or standName == "None" then return nil end

    -- Attribute is stored directly in lp.Data.Attri — no GUI crawl needed
    local attriVal = data:FindFirstChild("Attri")
    local attribute = attriVal and tostring(attriVal.Value) or "Unknown"

    return {
        name      = standName,
        attribute = attribute,
    }
end

local function useItem(itemName)
    local char = getCharacter()
    if not char then return false end

    local tool = lp.Backpack:FindFirstChild(itemName)
              or char:FindFirstChild(itemName)
    if not tool then return false end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    if tool.Parent == lp.Backpack then
        humanoid:EquipTool(tool)
        -- Wait until the server acknowledges the equip (tool moves to character)
        local deadline = tick() + 2
        repeat task.wait(0.05) until tool.Parent == char or tick() > deadline
    end

    -- Never fire UseItem unless the tool is confirmed in the character
    if tool.Parent ~= char then
        return false
    end

    pcall(function()
        game:GetService("ReplicatedStorage").Events.UseItem:FireServer()
    end)
    return true
end

-- Use Rokakaka (stand remover)
local function useRokakaka()
    return useItem("Rokakaka")
end

-- Check whether the current stand matches the user's conditions
local function standMatchesCondition(stand, condition, wantedStands, wantedAttribs)
    if condition == "None" then
        return true
    elseif condition == "StandCheck" then
        return table.find(wantedStands, STAND_IDS[stand.name] or stand.name) ~= nil
            or table.find(wantedStands, stand.name) ~= nil
    elseif condition == "AttributeCheck" then
        return table.find(wantedAttribs, stand.attribute) ~= nil
    elseif condition == "StandOrAttriCheck" then
        return (table.find(wantedStands, STAND_IDS[stand.name] or stand.name) ~= nil
             or table.find(wantedStands, stand.name) ~= nil)
            or table.find(wantedAttribs, stand.attribute) ~= nil
    elseif condition == "StandAndAttriCheck" then
        return (table.find(wantedStands, STAND_IDS[stand.name] or stand.name) ~= nil
             or table.find(wantedStands, stand.name) ~= nil)
           and table.find(wantedAttribs, stand.attribute) ~= nil
    end
    return false
end

-- ─── Slot saving ─────────────────────────────────────────────────────────────

-- Returns true if slot i is unlocked (slots 1-2 always free; 3-5 check GUI locks)
local function isSlotUnlocked(i)
    if i <= 2 then return true end
    local ok, result = pcall(function()
        local storage = lp.PlayerGui.PlayerGUI.ingame.StandStorage
        if i == 3 then
            return not storage.page1.GamepassLock.Visible
        elseif i == 4 then
            return not storage.page2.LevelLock1.Visible
        elseif i == 5 then
            return not storage.page2.GamepassLock2.Visible
        end
        return false
    end)
    return ok and result == true
end

-- Returns the first unlocked empty slot name ("Slot1"…"Slot5"), or nil if all full/locked
local function findEmptyUnlockedSlot()
    local data = lp:FindFirstChild("Data")
    if not data then return nil end
    for i = 1, 5 do
        if isSlotUnlocked(i) then
            local val = data:FindFirstChild("Slot" .. i .. "Stand")
            if val and (val.Value == "" or val.Value == "None") then
                return "Slot" .. i
            end
        end
    end
    return nil
end

-- Fires SwitchStand and waits for confirmation. Returns true only if the
-- slot data actually changed — prevents silent failures and overwrite bugs.
local function saveToSlot(stand)
    local data = lp:FindFirstChild("Data")
    if not data then return false end

    local targetSlot = findEmptyUnlockedSlot()
    if not targetSlot then
        return false  -- no room left
    end

    -- Double-check the slot is still empty right before firing (race-condition guard)
    local slotKey = targetSlot .. "Stand"
    local slotVal = data:FindFirstChild(slotKey)
    if not slotVal or (slotVal.Value ~= "" and slotVal.Value ~= "None") then
        -- slot unexpectedly full
        return false
    end

    local ok, err = pcall(function()
        game:GetService("ReplicatedStorage").Events.SwitchStand:FireServer(targetSlot)
    end)
    if not ok then
        notify("Warning", "Save failed: " .. tostring(err), 5)
        return false
    end

    -- Wait for BOTH: active stand clears AND slot value fills — max 6s each
    local standVal = data:FindFirstChild("Stand")
    local activeCleared, slotFilled = false, false

    local c1 = standVal and standVal.Changed:Connect(function(v)
        if v == "None" or v == "" then activeCleared = true end
    end)
    local c2 = slotVal.Changed:Connect(function(v)
        if v ~= "None" and v ~= "" then slotFilled = true end
    end)

    local deadline = tick() + 6
    repeat task.wait(0.05) until (activeCleared and slotFilled) or tick() > deadline

    if c1 then c1:Disconnect() end
    c2:Disconnect()

    if slotFilled then
        notify("Stored", stand.name .. " → " .. targetSlot, 4)
        return true
    else
        notify("Warning", "Store unconfirmed — roller stopped to protect your slots!", 8)
        return false  -- roller will stop, stand stays equipped safely
    end
end

-- ─── Specific stand matching ─────────────────────────────────────────────────

local function matchesSpecificStand(stand)
    local internalName = STAND_IDS[stand.name] or stand.name
    for _, entry in ipairs(specificStands) do
        if entry.name == internalName or entry.name == stand.name then
            if #entry.attribs == 0 then return true end
            for _, a in ipairs(entry.attribs) do
                if stand.attribute == a then return true end
            end
        end
    end
    return false
end

local function isBlacklisted(stand)
    local internalName = STAND_IDS[stand.name] or stand.name
    for _, entry in ipairs(blacklistStands) do
        if entry.name == internalName or entry.name == stand.name then
            if #entry.attribs == 0 then return true end
            for _, a in ipairs(entry.attribs) do
                if stand.attribute == a then return true end
            end
        end
    end
    return false
end

-- ─── Webhook ──────────────────────────────────────────────────────────────────

local function getItemCount(itemName)
    local bp = lp.Backpack
    -- Check both backpack and character
    local tool = bp:FindFirstChild(itemName)
               or (lp.Character and lp.Character:FindFirstChild(itemName))
    if not tool then return 0 end
    return tool:GetAttribute("ItemAmount") or 0
end

local function fireWebhook(payload)
    if webhookUrl == "" then return end
    pcall(function()
        local req = (syn and syn.request) or (http and http.request) or request
        req({
            Url     = webhookUrl,
            Method  = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body    = HttpService:JSONEncode(payload),
        })
    end)
end

local function sendWebhook(stand, rolls)
    local itemName = Options.SelectItem.Value
    local roks  = getItemCount("Rokakaka")
    local items = getItemCount(itemName)
    fireWebhook({
        username = "SUR Stand Roller",
        embeds = {{
            title  = "Stand Found!",
            color  = 0x7CFC00,
            fields = {
                {name = "Stand",     value = stand.name,      inline = true},
                {name = "Attribute", value = stand.attribute, inline = true},
                {name = "Rolls",     value = tostring(rolls),  inline = true},
                {name = "Player",    value = lp.Name,          inline = false},
                {name = itemName,    value = tostring(items),   inline = true},
                {name = "Rokakaka",  value = tostring(roks),    inline = true},
            },
            footer    = {text = "Stand Upright Rebooted | SUR Roller"},
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }}
    })
end

local function sendAlertWebhook(message)
    local ping = pingUserId ~= "" and ("<@" .. pingUserId .. "> ") or "@here "
    fireWebhook({
        content  = ping .. message,
        username = "SUR Stand Roller",
        embeds   = {{
            title  = "⚠️ Alert",
            color  = 0xFF4444,
            fields = {
                {name = "Player",    value = lp.Name,                         inline = true},
                {name = "Rolls",     value = tostring(rollCount),              inline = true},
                {name = "Rokakaka",  value = tostring(getItemCount("Rokakaka")), inline = true},
            },
            footer    = {text = "Stand Upright Rebooted | SUR Roller"},
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }}
    })
end

local function sendStartWebhook(itemName, condition, wantedStands, wantedAttribs)
    local items = getItemCount(itemName)
    local roks  = getItemCount("Rokakaka")

    local standsStr = #wantedStands > 0 and table.concat(wantedStands, ", ") or "—"
    local attribsStr = #wantedAttribs > 0 and table.concat(wantedAttribs, ", ") or "—"

    local specificLines = {}
    for _, entry in ipairs(specificStands) do
        local a = #entry.attribs > 0 and table.concat(entry.attribs, ", ") or "Any"
        table.insert(specificLines, entry.name .. " [" .. a .. "]")
    end
    local specificStr = #specificLines > 0 and table.concat(specificLines, "\n") or "—"

    fireWebhook({
        username = "SUR Stand Roller",
        embeds = {{
            title  = "🟢 Roller Started",
            color  = 0x00BFFF,
            fields = {
                {name = "Player",         value = lp.Name,          inline = true},
                {name = "Item",           value = itemName,          inline = true},
                {name = itemName .. " Count", value = tostring(items), inline = true},
                {name = "Rokakaka",       value = tostring(roks),    inline = true},
                {name = "Condition",      value = condition,         inline = true},
                {name = "Target Stands",  value = standsStr,         inline = false},
                {name = "Target Attribs", value = attribsStr,        inline = false},
                {name = "Specific Stands (" .. #specificStands .. ")", value = specificStr, inline = false},
            },
            footer    = {text = "Stand Upright Rebooted | SUR Roller"},
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }}
    })
end

local function sendDebugWebhook(event, standName, attribute, extra)
    if not debugMode then return end
    local items = getItemCount(Options.SelectItem and Options.SelectItem.Value or "Stand Arrow")
    local roks  = getItemCount("Rokakaka")
    fireWebhook({
        username = "SUR Roller [DEBUG]",
        embeds = {{
            title  = "🔍 " .. event,
            color  = 0xAAAAAA,
            fields = {
                {name = "Stand",     value = standName or "—",  inline = true},
                {name = "Attribute", value = attribute or "—",   inline = true},
                {name = "Roll #",    value = tostring(rollCount), inline = true},
                {name = "Player",    value = lp.Name,             inline = true},
                {name = "Item Count",value = tostring(items),     inline = true},
                {name = "Rokakaka",  value = tostring(roks),      inline = true},
                {name = "Info",      value = extra or "—",        inline = false},
            },
            footer    = {text = "Stand Upright Rebooted | SUR Roller"},
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }}
    })
end

local function sendStandDebugWebhook(attriDelayMs)
    if not standDebug then return end
    local data = lp:FindFirstChild("Data")
    local stand = data and data:FindFirstChild("Stand")
    local attri  = data and data:FindFirstChild("Attri")
    local sName = stand and tostring(stand.Value) or "?"
    local aName = attri  and tostring(attri.Value)  or "?"
    local delayStr = attriDelayMs and (tostring(attriDelayMs) .. "ms") or "—"
    fireWebhook({
        username = "SUR Stand Debug",
        embeds = {{
            title  = sName .. " [" .. aName .. "]",
            color  = 0x5865F2,
            fields = {
                {name = "Roll #",      value = tostring(rollCount), inline = true},
                {name = "Player",      value = lp.Name,             inline = true},
                {name = "Attri Delay", value = delayStr,            inline = true},
            },
            footer    = {text = "Stand Upright Rebooted | SUR Roller"},
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }}
    })
end

-- ─── Rejoin ──────────────────────────────────────────────────────────────────

local function rejoinServer(saveRestart)
    if saveRestart then
        pcall(function()
            writefile(AUTO_RESTART_FILE, HttpService:JSONEncode({autoRestart = true}))
        end)
    end
    if SCRIPT_URL ~= "" then
        local ok, err = pcall(function()
            local src = game:HttpGet(SCRIPT_URL)
            queue_on_teleport(src)
        end)
        if not ok then
            notify("Warning", "queue_on_teleport failed: " .. tostring(err), 6)
        end
    end
    pcall(function()
        game:GetService("TeleportService"):Teleport(game.PlaceId, lp)
    end)
end

-- ─── Roll loop ────────────────────────────────────────────────────────────────

local function startRolling()
    rolling    = true
    rollCount  = 0

    local condition    = Options.SelectCondition.Value
    local itemName     = Options.SelectItem.Value
    local wantedStands = {}
    local wantedAttribs= {}

    -- Collect wanted stands
    for k, v in pairs(Options.SelectStands.Value) do
        if v then table.insert(wantedStands, STAND_IDS[k] or k) end
    end
    -- Collect wanted attributes
    for k, v in pairs(Options.SelectAttributes.Value) do
        if v then table.insert(wantedAttribs, k) end
    end

    local consecutiveNone = 0
    local prevAttrib      = ""  -- last stand's attribute; used to detect stale Attri replication

    sendStartWebhook(itemName, condition, wantedStands, wantedAttribs)

    task.spawn(function()
        while rolling do
            -- Always drain deaths before doing anything else
            while rolling and isDead() do
                waitForRespawn()
            end
            if not rolling then break end

            local char = getCharacter()
            if not char then
                task.wait(1)
                if not rolling then break end
                continue
            end

            local existing = getCurrentStand()
            if existing and existing.name ~= "" then
                -- Wait for Attri to replicate. Also catches stale reads where Attri still
                -- shows the previous stand's attribute because replication hasn't caught up yet.
                if existing.attribute == "None" or existing.attribute == "" or existing.attribute == "Unknown"
                   or (prevAttrib ~= "" and existing.attribute == prevAttrib) then
                    local data2 = lp:FindFirstChild("Data")
                    local av = data2 and data2:FindFirstChild("Attri")
                    if av then
                        local settled = false
                        local ac = av.Changed:Connect(function(v)
                            if v ~= "None" and v ~= "" then
                                existing.attribute = tostring(v)
                                settled = true
                            end
                        end)
                        local dl = tick() + 1.5
                        repeat task.wait(0.05) until settled or tick() > dl
                        ac:Disconnect()
                        if not settled then
                            existing.attribute = tostring(av.Value)  -- genuinely None, or timed out
                        end
                        sendDebugWebhook("Attri Settled", existing.name, existing.attribute, settled and "waited for real value" or "timed out — using current")
                    end
                end
                prevAttrib = existing.attribute
                -- Blacklist overrides everything — skip check/save entirely
                if not isBlacklisted(existing) then
                    -- Check main condition OR specific stand list
                    local isWanted = standMatchesCondition(existing, condition, wantedStands, wantedAttribs)
                                     or matchesSpecificStand(existing)
                    if isWanted then
                        sendDebugWebhook("Stand Matched — Saving", existing.name, existing.attribute, "Attempting to save to slot")
                        local saved = saveToSlot(existing)
                        if saved then
                            sendWebhook(existing, rollCount)
                            continue
                        else
                            rolling = false
                            Options.StartRoller:SetValue(false)
                            notify("Done!", existing.name .. " [" .. existing.attribute .. "] equipped — all slots full! (" .. rollCount .. " rolls)", 10)
                            sendWebhook(existing, rollCount)
                            sendAlertWebhook("All slots are full! Last stand: " .. existing.name .. " [" .. existing.attribute .. "]")
                            break
                        end
                    end
                    -- Re-read Attri right before Rokaka in case it hadn't replicated yet
                    do
                        local data2 = lp:FindFirstChild("Data")
                        local av = data2 and data2:FindFirstChild("Attri")
                        if av then
                            local freshAttrib = tostring(av.Value)
                            if freshAttrib ~= existing.attribute then
                                existing.attribute = freshAttrib
                                local recheck = standMatchesCondition(existing, condition, wantedStands, wantedAttribs)
                                                or matchesSpecificStand(existing)
                                if recheck then
                                    sendDebugWebhook("Attri Late-Update — Saving Instead", existing.name, existing.attribute, "Would have Rokaka'd incorrectly")
                                    local saved = saveToSlot(existing)
                                    if saved then
                                        sendWebhook(existing, rollCount)
                                    else
                                        rolling = false
                                        Options.StartRoller:SetValue(false)
                                        notify("Done!", existing.name .. " [" .. existing.attribute .. "] equipped — all slots full! (" .. rollCount .. " rolls)", 10)
                                        sendWebhook(existing, rollCount)
                                        sendAlertWebhook("All slots are full! Last stand: " .. existing.name .. " [" .. existing.attribute .. "]")
                                    end
                                    continue
                                end
                            end
                        end
                    end
                else
                    sendDebugWebhook("Stand Blacklisted — Skipping", existing.name, existing.attribute, "On blacklist, Rokaka'ing regardless of condition")
                end
                -- Not the one — remove with Rokakaka
                sendDebugWebhook("Stand Skipped — Using Rokakaka", existing.name, existing.attribute, "Does not match condition")
                if not lp.Backpack:FindFirstChild("Rokakaka") and not char:FindFirstChild("Rokakaka") then
                    task.wait(2)
                    if lp.Backpack:FindFirstChild("Rokakaka") or (lp.Character and lp.Character:FindFirstChild("Rokakaka")) then continue end
                    rolling = false
                    Options.StartRoller:SetValue(false)
                    notify("Warning", "Out of Rokakaka! Roller stopped.", 8)
                    sendAlertWebhook("Out of Rokakaka! Roller stopped.")
                    break
                end
                useRokakaka()
                -- Wait for stand to clear from Data.Stand, max 4s
                do
                    local data2 = lp:FindFirstChild("Data")
                    local sv = data2 and data2:FindFirstChild("Stand")
                    if sv then
                        local cleared = false
                        local c = sv.Changed:Connect(function(v)
                            if v == "None" or v == "" then cleared = true end
                        end)
                        local dl = tick() + 4
                        repeat task.wait(0.05) until cleared or tick() > dl
                        c:Disconnect()
                    end
                end
                sendDebugWebhook("Stand Cleared", "—", "—", "Rokakaka consumed, stand removed")
            end

            -- Use arrow/item
            if not lp.Backpack:FindFirstChild(itemName) and not char:FindFirstChild(itemName) then
                -- Grace period: backpack can clear a moment before death registers
                task.wait(2)
                if lp.Backpack:FindFirstChild(itemName) or (lp.Character and lp.Character:FindFirstChild(itemName)) then continue end
                rolling = false
                Options.StartRoller:SetValue(false)
                notify("Warning", "Out of " .. itemName .. "! Roller stopped.", 8)
                sendAlertWebhook("Out of " .. itemName .. "! Roller stopped.")
                break
            end

            sendDebugWebhook("Using Item", "—", "—", "Equipping " .. itemName .. " and firing UseItem")
            useItem(itemName)
            rollCount = rollCount + 1
            local standAppeared    = false
            local rolledStandName  = "—"
            local rolledStandAttrib = "—"
            do
                local data2 = lp:FindFirstChild("Data")
                local sv = data2 and data2:FindFirstChild("Stand")
                local av = data2 and data2:FindFirstChild("Attri")
                if sv then
                    local settle = useCustomDelay and customAttriDelay or (extendedAttri and 0.30 or 0.25)
                    local tStand = 0
                    local sc = sv.Changed:Connect(function(v)
                        if v ~= "None" and v ~= "" then
                            standAppeared   = true
                            rolledStandName = v
                            tStand = tick()
                        end
                    end)
                    local dl = tick() + 5
                    repeat task.wait(0.05) until standAppeared or tick() > dl
                    sc:Disconnect()
                    if standAppeared then
                        task.wait(settle)
                        rolledStandAttrib = av and tostring(av.Value) or "?"
                        local delayMs = tStand > 0 and math.floor((tick() - tStand) * 1000) or nil
                        sendStandDebugWebhook(delayMs)
                    end
                end
            end

            if standAppeared then
                sendDebugWebhook("Stand Rolled", rolledStandName, rolledStandAttrib, "Roll #" .. rollCount)
                consecutiveNone = 0
            else
                consecutiveNone = consecutiveNone + 1
                sendDebugWebhook("No Stand Received", "—", "—", "consecutiveNone = " .. consecutiveNone)
                if consecutiveNone >= 10 then
                    rolling = false
                    Options.StartRoller:SetValue(false)
                    notify("Warning", "Roller broken — rejoining server...", 10)
                    sendAlertWebhook("Roller appears broken — no stand after 10 consecutive rolls. Rejoining server.")
                    task.wait(2)
                    rejoinServer(true)
                    break
                end
            end
        end
    end)
end

local function stopRolling()
    rolling = false
end

-- ─── Roller Tab UI ────────────────────────────────────────────────────────────

RollTab:AddDropdown("SelectStands", {
    Title   = "Target Stands",
    Icon    = "star",
    Values  = STAND_NAMES,
    Multi   = true,
    Default = {},
})

RollTab:AddDropdown("SelectAttributes", {
    Title   = "Target Attributes",
    Icon    = "award",
    Values  = ATTRIBUTES,
    Multi   = true,
    Default = {},
})

RollTab:AddDropdown("SelectItem", {
    Title   = "Item to Use",
    Icon    = "tool",
    Values  = {"Stand Arrow", "Charged Arrow", "Kars Mask"},
    Default = "Stand Arrow",
})

RollTab:AddDropdown("SelectCondition", {
    Title   = "Stop Condition",
    Icon    = "check",
    Values  = {"None", "StandCheck", "AttributeCheck", "StandOrAttriCheck", "StandAndAttriCheck"},
    Default = "StandCheck",
})

RollTab:AddToggle("StartRoller", {
    Title   = "Start Rolling",
    Icon    = "play",
    Default = false,
})

Options.StartRoller:OnChanged(function()
    if Options.StartRoller.Value then
        local condition = Options.SelectCondition.Value
        if condition == "None" then
            notify("Warning", "Condition is None — roller will run forever.", 4)
        end
        startRolling()
    else
        stopRolling()
        if scriptReady then
            notify("Info", "Roller stopped after " .. rollCount .. " rolls.", 3)
        end
    end
end)

RollTab:AddToggle("ExtendedAttriWait", {
    Title       = "Extended Attri Wait (Recommended)",
    Description = "Use this if you're on a lower-end device or have bad internet. Forces 300ms — safer than tweaking delay manually.",
    Icon        = "clock",
    Default     = false,
})

Options.ExtendedAttriWait:OnChanged(function()
    extendedAttri = Options.ExtendedAttriWait.Value
end)

RollTab:AddParagraph({
    Title   = "How Attri Delay Works",
    Content = "When you roll a stand, the game sends the stand name and its attribute separately. The attribute takes a little longer to arrive depending on your device speed and internet.\n\nIf the delay is too low and your attribute hasn't arrived yet, the script might read the wrong value and Rokaka a stand it should have kept.\n\nThe worse your device or internet, the higher this should be.\nDefault (250ms) works for most people.",
})

RollTab:AddInput("CustomAttriDelay", {
    Title       = "Attri Delay (ms)",
    Default     = "250",
    Placeholder = "250",
    Numeric     = true,
    Callback    = function(v)
        local ms = tonumber(v)
        if ms and ms >= 50 and ms <= 2000 then
            customAttriDelay = ms / 1000
        end
    end,
})

RollTab:AddToggle("UseCustomDelay", {
    Title   = "Enable Custom Delay",
    Icon    = "sliders",
    Default = false,
})

Options.UseCustomDelay:OnChanged(function()
    useCustomDelay = Options.UseCustomDelay.Value
end)

RollTab:AddParagraph({
    Title   = "",
    Content = "⚠️ Only change this if stands are being Rokaka'd incorrectly. If unsure, just enable Extended Attri Wait above instead.",
})

RollTab:AddDropdown("TestRollCount", {
    Title   = "Test Sample Count",
    Icon    = "hash",
    Values  = {"10", "25", "50", "100"},
    Default = "10",
})

Options.TestRollCount:OnChanged(function()
    testRollTarget = tonumber(Options.TestRollCount.Value) or 10
end)

RollTab:AddButton({
    Title    = "Run Delay Test",
    Icon     = "activity",
    Callback = function()
        if rolling then
            notify("Delay Test", "Stop the roller first.", 3)
            return
        end
        local itemName = Options.SelectItem.Value
        local char = lp.Character
        if not char then notify("Delay Test", "No character found.", 3) return end
        if not lp.Backpack:FindFirstChild(itemName) and not char:FindFirstChild(itemName) then
            notify("Delay Test", "No " .. itemName .. " in backpack.", 4)
            return
        end
        if not lp.Backpack:FindFirstChild("Rokakaka") and not char:FindFirstChild("Rokakaka") then
            notify("Delay Test", "No Rokakaka found — needed to clear stands during the test.", 5)
            return
        end
        local target = testRollTarget
        notify("Delay Test", "Starting — collecting " .. target .. " samples. Don't roll manually!", 5)
        task.spawn(function()
            local samples  = {}
            local attempts = 0
            local data2    = lp:FindFirstChild("Data")
            if not data2 then return end
            local sv = data2:FindFirstChild("Stand")
            local av = data2:FindFirstChild("Attri")
            if not sv or not av then return end

            local function buildConditionVars()
                local cond = Options.SelectCondition.Value
                local ws, wa = {}, {}
                for k, v in pairs(Options.SelectStands.Value) do
                    if v then table.insert(ws, STAND_IDS[k] or k) end
                end
                for k, v in pairs(Options.SelectAttributes.Value) do
                    if v then table.insert(wa, k) end
                end
                return cond, ws, wa
            end

            local function rokakaAndWait()
                task.wait(0.2)
                useRokakaka()
                local cleared = (sv.Value == "None" or sv.Value == "")
                local cc = sv.Changed:Connect(function(v)
                    if v == "None" or v == "" then cleared = true end
                end)
                local dl = tick() + 6
                repeat task.wait(0.05) until cleared or tick() > dl
                cc:Disconnect()
                task.wait(0.3)
            end

            -- safety cap: target * 6 to account for ~50% None rolls plus retries
            while #samples < target and attempts < target * 6 do
                attempts = attempts + 1

                -- Wait out deaths before each roll
                while isDead() do task.wait(0.5) end

                local c2 = lp.Character
                if not c2 then task.wait(1) continue end

                if not lp.Backpack:FindFirstChild(itemName) and not c2:FindFirstChild(itemName) then
                    notify("Delay Test", "Out of " .. itemName .. " — stopped at " .. #samples .. " samples.", 5)
                    break
                end
                if not lp.Backpack:FindFirstChild("Rokakaka") and not c2:FindFirstChild("Rokakaka") then
                    notify("Delay Test", "Out of Rokakaka — stopped at " .. #samples .. " samples.", 5)
                    break
                end

                -- Pre-roll cleanup: clear any leftover stand before rolling
                if getCurrentStand() then
                    rokakaAndWait()
                    if getCurrentStand() then task.wait(1) continue end
                end

                local standTime = nil
                local attriTime = nil
                local gotStand  = false

                local sc = sv.Changed:Connect(function(v)
                    if v ~= "None" and v ~= "" and not gotStand then
                        gotStand  = true
                        standTime = tick()
                    end
                end)
                local ac = av.Changed:Connect(function(v)
                    if v ~= "None" and v ~= "" and standTime and not attriTime then
                        attriTime = tick()
                    end
                end)

                local used = useItem(itemName)
                if not used then
                    sc:Disconnect()
                    ac:Disconnect()
                    task.wait(0.5)
                    continue
                end

                local dl = tick() + 5
                repeat task.wait(0.05) until gotStand or tick() > dl
                sc:Disconnect()

                if gotStand then
                    local dl2 = standTime + 3
                    repeat task.wait(0.05) until attriTime or tick() > dl2
                end
                ac:Disconnect()

                -- Check stand against roller settings before deciding what to do with it
                local standData = getCurrentStand()
                if standData then
                    local cond, ws, wa = buildConditionVars()
                    if not isBlacklisted(standData) then
                        local isWanted = standMatchesCondition(standData, cond, ws, wa)
                                         or matchesSpecificStand(standData)
                        if isWanted then
                            local saved = saveToSlot(standData)
                            if saved then
                                notify(
                                    "Delay Test — Stand Found!",
                                    standData.name .. " [" .. standData.attribute .. "] saved! (" .. #samples .. "/" .. target .. " samples kept)\nRestarting test...",
                                    8
                                )
                            else
                                notify(
                                    "Delay Test — Stand Found!",
                                    standData.name .. " [" .. standData.attribute .. "] — no slot, Rokaka'd. (" .. #samples .. "/" .. target .. " samples kept)\nRestarting test...",
                                    8
                                )
                                rokakaAndWait()
                            end
                            samples  = {}
                            attempts = 0
                            task.wait(1)
                            continue
                        end
                    end
                end

                -- Record sample if this roll had an attribute, then Rokaka
                if attriTime and standTime then
                    local ms = math.floor((attriTime - standTime) * 1000)
                    table.insert(samples, ms)
                    notify("Delay Test", "Sample " .. #samples .. "/" .. target .. ": " .. ms .. "ms", 2)
                end

                if getCurrentStand() then
                    rokakaAndWait()
                end
            end

            if #samples == 0 then
                notify("Delay Test", "No valid samples — all rolls had no attribute. Try again.", 6)
                return
            end

            local maxDelay, sum = 0, 0
            for _, d in ipairs(samples) do
                if d > maxDelay then maxDelay = d end
                sum = sum + d
            end
            local avgDelay    = math.floor(sum / #samples)
            local recommended = maxDelay + 25

            notify(
                "Delay Test — Done!",
                #samples .. " samples collected.\n"
                .. "Highest: " .. maxDelay .. "ms  |  Avg: " .. avgDelay .. "ms\n"
                .. "→ Recommended delay: " .. recommended .. "ms\n\n"
                .. "Set Custom Delay to " .. recommended .. " and enable it.",
                20
            )

            fireWebhook({
                username = "SUR Stand Roller",
                embeds = {{
                    title  = "📊 Delay Test Results",
                    color  = 0x5865F2,
                    fields = {
                        {name = "Player",      value = lp.Name,              inline = true},
                        {name = "Samples",     value = tostring(#samples),   inline = true},
                        {name = "Highest",     value = maxDelay .. "ms",     inline = true},
                        {name = "Average",     value = avgDelay .. "ms",     inline = true},
                        {name = "Recommended", value = recommended .. "ms",  inline = true},
                    },
                    footer    = {text = "Stand Upright Rebooted | SUR Roller"},
                    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                }}
            })
        end)
    end,
})

RollTab:AddParagraph({
    Title   = "About Delay Test",
    Content = "Rolls stands until the selected sample count is reached. Only rolls that get an attribute (~50% chance) count — the rest are skipped.\n\nMeasures the exact time between the stand name arriving and its attribute arriving. Shows highest and average delay when done, and sends results to your webhook.\n\nIf a stand matches your roller settings during the test, it saves normally and the test restarts from 0.",
})

-- Auto-skip rare attribute prompt
-- Frame tweens in (Y scale ~0.66 → 0.58) then tweens out (Y > 1.0)
-- We wait until it fully settles on screen before clicking
local _promptClicked = false
pcall(function()
    local frame = lp.PlayerGui.newPromptGUI.MainFrame
    frame:GetPropertyChangedSignal("Position"):Connect(function()
        local yScale = frame.Position.Y.Scale
        if yScale < 1.0 then
            if not _promptClicked then
                _promptClicked = true
                -- Wait for the tween to finish before clicking
                task.delay(0.6, function()
                    pcall(function() frame.YesButton.MouseButton1Click:Fire() end)
                end)
            end
        else
            _promptClicked = false
        end
    end)
end)


RollTab:AddButton({
    Title    = "Open Storage Menu",
    Icon     = "archive",
    Callback = function()
        local ok, err = pcall(function()
            local done = game:GetService("Workspace").Map.NPCs.admpn.Done
            if done:IsA("RemoteEvent") then
                done:FireServer()
            elseif done:IsA("ProximityPrompt") then
                fireproximityprompt(done)
            else
                notify("Error", "admpn.Done is a " .. done.ClassName, 5)
            end
        end)
        if not ok then
            notify("Error", tostring(err), 5)
        end
    end,
})

-- ─── Specific Stands Tab ─────────────────────────────────────────────────────

local function specificStandListText()
    if #specificStands == 0 then return "(empty)" end
    local lines = {}
    for i, entry in ipairs(specificStands) do
        local a = #entry.attribs > 0 and table.concat(entry.attribs, ", ") or "Any attrib"
        table.insert(lines, i .. ". " .. entry.name .. " — " .. a)
    end
    return table.concat(lines, "\n")
end

SpecificTab:AddParagraph({
    Title   = "How it works",
    Content = "Stands added here are ALWAYS saved regardless of your stop condition.\nUse 'Show My List' to see what's currently saved.\n\nNote: This list is saved to its own file (SUR_SpecificStands.json) and is NOT part of the Configs system — saving or loading a config won't affect it.",
})

SpecificTab:AddDropdown("SpecificStandPick", {
    Title   = "Stand",
    Icon    = "star",
    Values  = STAND_NAMES,
    Multi   = false,
    Default = STAND_NAMES[1],
})

SpecificTab:AddDropdown("SpecificAttribPick", {
    Title   = "Attribute(s)",
    Icon    = "award",
    Values  = ATTRIBUTES,
    Multi   = true,
    Default = {},
})

SpecificTab:AddButton({
    Title    = "Add to List",
    Icon     = "plus",
    Callback = function()
        local standDisplay = Options.SpecificStandPick.Value
        local internalName = STAND_IDS[standDisplay] or standDisplay
        local attribs = {}
        for k, v in pairs(Options.SpecificAttribPick.Value) do
            if v then table.insert(attribs, k) end
        end

        for _, entry in ipairs(specificStands) do
            if entry.name == internalName and #entry.attribs == #attribs then
                local same = true
                for _, a in ipairs(attribs) do
                    if not table.find(entry.attribs, a) then same = false; break end
                end
                if same then
                    notify("Specific Stands", standDisplay .. " is already in the list!", 3)
                    return
                end
            end
        end

        table.insert(specificStands, {name = internalName, attribs = attribs})
        saveSpecificStands()
        local attribStr = #attribs > 0 and table.concat(attribs, ", ") or "Any"
        notify("Added!", "#" .. #specificStands .. " — " .. standDisplay .. " [" .. attribStr .. "]", 5)
    end,
})

SpecificTab:AddButton({
    Title    = "Show My List",
    Icon     = "list",
    Callback = function()
        local text = specificStandListText()
        notify("Specific Stands (" .. #specificStands .. ")", text, 8)
    end,
})

SpecificTab:AddInput("RemoveSpecificIndex", {
    Title       = "Remove Number",
    Default     = "",
    Placeholder = "e.g.  2",
    Numeric     = true,
    Callback    = function() end,
})

SpecificTab:AddButton({
    Title    = "Remove Entry",
    Icon     = "trash",
    Callback = function()
        local idx = tonumber(Options.RemoveSpecificIndex.Value)
        if not idx or idx < 1 or idx > #specificStands then
            notify("Specific Stands", "Invalid number — list has " .. #specificStands .. " entries.", 4)
            return
        end
        local removed = specificStands[idx]
        local a = #removed.attribs > 0 and table.concat(removed.attribs, ", ") or "Any"
        table.remove(specificStands, idx)
        saveSpecificStands()
        notify("Removed", "#" .. idx .. " — " .. removed.name .. " [" .. a .. "]\n\nRemaining: " .. #specificStands, 5)
    end,
})

SpecificTab:AddButton({
    Title    = "Clear All",
    Icon     = "x",
    Callback = function()
        specificStands = {}
        saveSpecificStands()
        notify("Specific Stands", "List cleared.", 3)
    end,
})

SpecificTab:AddButton({
    Title    = "Refresh from File",
    Icon     = "refresh-cw",
    Callback = function()
        local ok = pcall(function()
            if isfile(SPECIFIC_SAVE_FILE) then
                local data = HttpService:JSONDecode(readfile(SPECIFIC_SAVE_FILE))
                if type(data) == "table" then
                    specificStands = data
                end
            else
                specificStands = {}
            end
        end)
        notify("Specific Stands", "Refreshed from file — " .. #specificStands .. " entries loaded.", 4)
    end,
})

-- ─── Blacklist Tab ───────────────────────────────────────────────────────────

local function blacklistListText()
    if #blacklistStands == 0 then return "(empty)" end
    local lines = {}
    for i, entry in ipairs(blacklistStands) do
        local a = #entry.attribs > 0 and table.concat(entry.attribs, ", ") or "Any attrib"
        table.insert(lines, i .. ". " .. entry.name .. " — " .. a)
    end
    return table.concat(lines, "\n")
end

BlacklistTab:AddParagraph({
    Title   = "How it works",
    Content = "Stands added here are ALWAYS Rokaka'd regardless of your stop condition or Specific list.\nUse this to skip stands you never want to keep.\n\nNote: This list is saved to its own file (SUR_Blacklist.json) and is NOT part of the Configs system — saving or loading a config won't affect it.",
})

BlacklistTab:AddDropdown("BlacklistStandPick", {
    Title   = "Stand",
    Icon    = "star",
    Values  = STAND_NAMES,
    Multi   = false,
    Default = STAND_NAMES[1],
})

BlacklistTab:AddDropdown("BlacklistAttribPick", {
    Title   = "Attribute(s)",
    Icon    = "award",
    Values  = ATTRIBUTES,
    Multi   = true,
    Default = {},
})

BlacklistTab:AddButton({
    Title    = "Add to Blacklist",
    Icon     = "plus",
    Callback = function()
        local standDisplay = Options.BlacklistStandPick.Value
        local internalName = STAND_IDS[standDisplay] or standDisplay
        local attribs = {}
        for k, v in pairs(Options.BlacklistAttribPick.Value) do
            if v then table.insert(attribs, k) end
        end

        for _, entry in ipairs(blacklistStands) do
            if entry.name == internalName and #entry.attribs == #attribs then
                local same = true
                for _, a in ipairs(attribs) do
                    if not table.find(entry.attribs, a) then same = false; break end
                end
                if same then
                    notify("Blacklist", standDisplay .. " is already in the blacklist!", 3)
                    return
                end
            end
        end

        table.insert(blacklistStands, {name = internalName, attribs = attribs})
        saveBlacklistStands()
        local attribStr = #attribs > 0 and table.concat(attribs, ", ") or "Any"
        notify("Blacklisted!", "#" .. #blacklistStands .. " — " .. standDisplay .. " [" .. attribStr .. "]", 5)
    end,
})

BlacklistTab:AddButton({
    Title    = "Show Blacklist",
    Icon     = "list",
    Callback = function()
        notify("Blacklist (" .. #blacklistStands .. ")", blacklistListText(), 8)
    end,
})

BlacklistTab:AddInput("RemoveBlacklistIndex", {
    Title       = "Remove Number",
    Default     = "",
    Placeholder = "e.g. 1",
    Numeric     = true,
    Callback    = function() end,
})

BlacklistTab:AddButton({
    Title    = "Remove Entry",
    Icon     = "trash",
    Callback = function()
        local idx = tonumber(Options.RemoveBlacklistIndex.Value)
        if not idx or idx < 1 or idx > #blacklistStands then
            notify("Blacklist", "Invalid number — list has " .. #blacklistStands .. " entries.", 4)
            return
        end
        local removed = blacklistStands[idx]
        local a = #removed.attribs > 0 and table.concat(removed.attribs, ", ") or "Any"
        table.remove(blacklistStands, idx)
        saveBlacklistStands()
        notify("Removed", "#" .. idx .. " — " .. removed.name .. " [" .. a .. "]", 5)
    end,
})

BlacklistTab:AddButton({
    Title    = "Clear All",
    Icon     = "x",
    Callback = function()
        blacklistStands = {}
        saveBlacklistStands()
        notify("Blacklist", "Blacklist cleared.", 3)
    end,
})

-- ─── Webhook Tab UI ───────────────────────────────────────────────────────────

WebhookTab:AddInput("WebhookURL", {
    Title       = "Webhook URL",
    Default     = "",
    Placeholder = "https://discord.com/api/webhooks/...",
    Callback    = function(v)
        webhookUrl = v
    end,
})

WebhookTab:AddInput("PingUserId", {
    Title       = "Discord User ID",
    Default     = "",
    Placeholder = "e.g. 123456789012345678",
    Numeric     = true,
    Callback    = function(v)
        pingUserId = v
    end,
})

WebhookTab:AddButton({
    Title    = "Test Webhook",
    Icon     = "send",
    Callback = function()
        if webhookUrl == "" then
            notify("Error", "Enter a webhook URL first!", 5)
            return
        end
        sendWebhook({name = "Test Stand", attribute = "Godly"}, 0)
        notify("Webhook", "Test message sent!", 3)
    end,
})

WebhookTab:AddToggle("StandDebug", {
    Title       = "Stand Debug",
    Description = "Sends stand + attribute to webhook instantly on every roll — no delay, no extra info",
    Icon        = "eye",
    Default     = false,
})

Options.StandDebug:OnChanged(function()
    standDebug = Options.StandDebug.Value
    if scriptReady then
        notify("Webhook", "Stand debug " .. (standDebug and "enabled" or "disabled") .. ".", 3)
    end
end)

WebhookTab:AddToggle("DebugMode", {
    Title       = "Full Debug Mode",
    Description = "Sends verbose webhooks for every action (roll, skip, Rokaka, equip)",
    Icon        = "bug",
    Default     = false,
})

Options.DebugMode:OnChanged(function()
    debugMode = Options.DebugMode.Value
    if scriptReady then
        notify("Webhook", "Full debug mode " .. (debugMode and "enabled" or "disabled") .. ".", 3)
    end
end)

-- ─── Misc Tab ────────────────────────────────────────────────────────────────

MiscTab:AddToggle("AntiAFK", {
    Title       = "Anti-AFK",
    Description = "Prevents getting kicked for inactivity",
    Icon        = "clock",
    Default     = false,
})

Options.AntiAFK:OnChanged(function()
    if Options.AntiAFK.Value then
        lp.Idled:Connect(function()
            lp:Move(Vector3.new(0, 0, 0), false)
        end)
    end
end)

MiscTab:AddToggle("DisableRenderer", {
    Title       = "Disable 3D Renderer",
    Description = "Turns off 3D rendering so the script runs in the background with low GPU/CPU usage",
    Icon        = "monitor",
    Default     = false,
})

local blackOverlay = Instance.new("ScreenGui")
blackOverlay.Name = "SUR_BlackOverlay"
blackOverlay.ResetOnSpawn = false
blackOverlay.DisplayOrder = -99
blackOverlay.IgnoreGuiInset = true
blackOverlay.Enabled = false
blackOverlay.Parent = lp.PlayerGui

local blackFrame = Instance.new("Frame")
blackFrame.Size = UDim2.fromScale(1, 1)
blackFrame.Position = UDim2.fromScale(0, 0)
blackFrame.BackgroundColor3 = Color3.new(0, 0, 0)
blackFrame.BorderSizePixel = 0
blackFrame.ZIndex = 1
blackFrame.Parent = blackOverlay

Options.DisableRenderer:OnChanged(function()
    local disabled = Options.DisableRenderer.Value
    pcall(function()
        game:GetService("RunService"):Set3dRenderingEnabled(not disabled)
    end)
    blackOverlay.Enabled = disabled
end)

local function unloadScript()
    rolling = false
    pcall(function() game:GetService("RunService"):Set3dRenderingEnabled(true) end)
    pcall(function() blackOverlay:Destroy() end)
    pcall(function() Window:Destroy() end)
end

MiscTab:AddButton({
    Title    = "Rejoin Server",
    Icon     = "refresh-cw",
    Callback = function()
        notify("Rejoin", "Rejoining server...", 3)
        task.wait(1)
        rejoinServer(rolling)
    end,
})

MiscTab:AddButton({
    Title    = "Unload Script",
    Icon     = "x",
    Callback = unloadScript,
})

MiscTab:AddDropdown("ThemePicker", {
    Title   = "UI Theme",
    Icon    = "palette",
    Values  = {"Dark", "Light", "Aqua", "Amethyst", "Rose"},
    Default = "Dark",
})

Options.ThemePicker:OnChanged(function()
    Fluent:SetTheme(Options.ThemePicker.Value)
end)

-- ─── Remote Spy ──────────────────────────────────────────────────────────────

local spyActive = false
local _tpService = game:GetService("TeleportService")

pcall(function()
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()

        if shopBusy then
            -- Always block TeleportService calls from any script
            if self == _tpService then return end
            -- Block other scripts' remote calls; let our own through
            if not _shopCallActive and (method == "FireServer" or method == "InvokeServer") then
                return
            end
        end

        if spyActive and (method == "FireServer" or method == "InvokeServer") then
            local args = {...}
            pcall(function()
                if not (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then return end
                local parts = {}
                for _, v in ipairs(args) do
                    table.insert(parts, tostring(v))
                end
                local argStr = #parts > 0 and table.concat(parts, ", ") or "no args"
                print("[Spy] " .. method .. " | " .. self.Name .. " | " .. argStr)
            end)
        end
        return oldNamecall(self, ...)
    end)
end)

MiscTab:AddToggle("RemoteSpy", {
    Title       = "Remote Spy",
    Description = "Logs all FireServer/InvokeServer calls as notifications",
    Icon        = "radio",
    Default     = false,
})

Options.RemoteSpy:OnChanged(function()
    spyActive = Options.RemoteSpy.Value
    if scriptReady then
        notify("Remote Spy", spyActive and "Spy enabled — check console for output." or "Spy disabled.", 3)
    end
end)

-- GUI button spy — hooks all TextButton/ImageButton clicks in PlayerGui
local guiSpyActive = false
local guiSpyConns  = {}

local function refreshGuiSpy()
    for _, c in ipairs(guiSpyConns) do pcall(function() c:Disconnect() end) end
    guiSpyConns = {}
    if not guiSpyActive then return end

    local function hookGui(gui)
        for _, v in ipairs(gui:GetDescendants()) do
            if v:IsA("TextButton") or v:IsA("ImageButton") then
                local path = v.Name
                local p = v.Parent
                while p and p ~= gui do path = p.Name .. "." .. path; p = p.Parent end
                local c = v.MouseButton1Click:Connect(function()
                    print("[GUI Spy] Click | " .. gui.Name .. " > " .. path)
                end)
                table.insert(guiSpyConns, c)
            end
        end
    end

    for _, gui in ipairs(lp.PlayerGui:GetChildren()) do
        pcall(function() hookGui(gui) end)
    end

    -- Also hook proximity prompts
    local ppConn = game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt)
        print("[GUI Spy] ProximityPrompt | " .. prompt:GetFullName())
    end)
    table.insert(guiSpyConns, ppConn)

    -- Hook any GUIs that appear after spy is enabled
    local addConn = lp.PlayerGui.ChildAdded:Connect(function(child)
        task.wait(0.2)
        pcall(function() hookGui(child) end)
    end)
    table.insert(guiSpyConns, addConn)
end

MiscTab:AddToggle("GuiSpy", {
    Title       = "GUI + Proximity Spy",
    Description = "Logs button clicks and proximity prompt triggers to console — use alongside Remote Spy to map buttons to remotes",
    Icon        = "mouse-pointer",
    Default     = false,
})

Options.GuiSpy:OnChanged(function()
    guiSpyActive = Options.GuiSpy.Value
    refreshGuiSpy()
    if scriptReady then
        notify("GUI Spy", guiSpyActive and "Enabled — click buttons/prompts and check console." or "Disabled.", 3)
    end
end)

-- ─── Shop Tab ────────────────────────────────────────────────────────────────

local function openStockMarket()
    -- TP to NPC model position
    local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local npc = workspace.Map.NPCs.StockMarket
    local npcRoot = npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChildWhichIsA("BasePart")
    if not npcRoot then return false end
    root.CFrame = npcRoot.CFrame * CFrame.new(0, 0, -3)
    task.wait(0.5)
    -- Fire proximity prompt
    local ok = pcall(function()
        fireproximityprompt(workspace.Map.NPCs.StockMarket.TalkToPrompt)
    end)
    if not ok then return false end
    -- Wait up to 5s for the GUI to appear
    local deadline = tick() + 5
    repeat task.wait(0.1) until (lp.PlayerGui:FindFirstChild("newStockMarketGUI") and lp.PlayerGui.newStockMarketGUI.Enabled) or tick() > deadline
    return lp.PlayerGui:FindFirstChild("newStockMarketGUI") ~= nil
end

local SELLABLE_ITEMS = {"Charged Arrow", "Requiem Arrow"}

local sellItem   = SELLABLE_ITEMS[1]
local sellAmount = 1
local sellAll    = false

ShopTab:AddParagraph({
    Title   = "Sell Items",
    Content = "Sells items to the shop. Teleports to the NPC and opens the market before firing.",
})

ShopTab:AddDropdown("SellItemPick", {
    Title   = "Item to Sell",
    Icon    = "package",
    Values  = SELLABLE_ITEMS,
    Default = SELLABLE_ITEMS[1],
})

Options.SellItemPick:OnChanged(function()
    sellItem = Options.SellItemPick.Value
end)

ShopTab:AddInput("SellAmount", {
    Title       = "Amount",
    Default     = "1",
    Placeholder = "e.g. 10",
    Numeric     = true,
    Callback    = function(v)
        sellAmount = tonumber(v) or 1
    end,
})

ShopTab:AddToggle("SellAll", {
    Title   = "Sell All",
    Icon    = "layers",
    Default = false,
})

Options.SellAll:OnChanged(function()
    sellAll = Options.SellAll.Value
end)

local function doSell()
    local item = sellItem
    local count = getItemCount(item)
    if count == 0 then
        notify("Shop", "You have no " .. item .. " to sell.", 4)
        return false
    end
    local amount = sellAll and count or math.min(sellAmount, count)
    shopBusy = true
    local smEvent = game:GetService("ReplicatedStorage").Events.SM_Event
    local opened = false
    for attempt = 1, 5 do
        notify("Shop", "Opening stock market" .. (attempt > 1 and " (retry " .. attempt .. "/5)..." or "..."), 3)
        if openStockMarket() then opened = true; break end
        task.wait(2)
    end
    if not opened then
        shopBusy = false
        notify("Shop", "Failed to open stock market.", 4)
        return false
    end
    pcall(function()
        lp.PlayerGui.newStockMarketGUI.SM_Frame.SelectFrame.BulkSell.MouseButton1Click:Fire()
    end)
    task.wait(0.3)
    local ok, err = shopFire(smEvent, "Sell", item, amount)
    shopFire(smEvent, "Cancel")
    pcall(function()
        lp.PlayerGui.newStockMarketGUI.SM_Frame.ExitButton.MouseButton1Click:Fire()
    end)
    shopBusy = false
    resetCharacter()
    if ok then
        notify("Shop", "Sold " .. amount .. "x " .. item, 4)
        return true
    else
        notify("Shop", "Sell failed: " .. tostring(err), 5)
        return false
    end
end

ShopTab:AddButton({
    Title    = "Sell",
    Icon     = "dollar-sign",
    Callback = function() doSell() end,
})

-- ─── MerchantAU spam buy ─────────────────────────────────────────────────────

local merchantBuying = false

local MERCHANT_CF = CFrame.new(
    11926.1094, -3.45856023, -4510.9082,
    0.998864949,  0.0278102029, 0.0386722721,
    -0.0288556386, 0.999225676,  0.0267434008,
    -0.0378986038, -0.0278289542, 0.998894036
)

local MERCHANT_OPTIONS = {
    ["10x Rokakaka (bulk)"]   = "Option1",
    ["1x Rokakaka"]           = "Option2",
    ["10x Stand Arrow (bulk)"]= "Option3",
    ["1x Stand Arrow"]        = "Option4",
}
local MERCHANT_OPTION_LABELS = {
    "10x Rokakaka (bulk)",
    "1x Rokakaka",
    "10x Stand Arrow (bulk)",
    "1x Stand Arrow",
}
local MERCHANT_OPTION_ITEM = {
    Option1 = "Rokakaka",
    Option2 = "Rokakaka",
    Option3 = "Stand Arrow",
    Option4 = "Stand Arrow",
}

local function openMerchantAU()
    local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    root.CFrame = MERCHANT_CF
    task.wait(0.3)
    local npc = workspace.Map.NPCs:FindFirstChild("MerchantAU")
    if not npc then return false end
    pcall(function()
        fireproximityprompt(npc:FindFirstChild("Talk") or npc:WaitForChild("Talk", 2))
    end)
    -- Wait for the NPC dialogue GUI to fully open before spamming
    local deadline = tick() + 4
    repeat task.wait(0.1) until lp.PlayerGui:FindFirstChild("NpcDialouge") or tick() > deadline
    task.wait(0.2)
    return true
end

local merchantOption    = "Option1"
local merchantSpamCount = 50

ShopTab:AddParagraph({
    Title   = "Buy Items (MerchantAU)",
    Content = "Teleports to the MerchantAU NPC and spams BuyItem. Bulk options buy 10 at a time (cheaper per unit).",
})

ShopTab:AddDropdown("MerchantOptionPick", {
    Title   = "Item to Buy",
    Icon    = "shopping-bag",
    Values  = MERCHANT_OPTION_LABELS,
    Default = MERCHANT_OPTION_LABELS[1],
})

Options.MerchantOptionPick:OnChanged(function()
    merchantOption = MERCHANT_OPTIONS[Options.MerchantOptionPick.Value] or "Option1"
end)

ShopTab:AddInput("MerchantSpamCount", {
    Title       = "Spam Count",
    Default     = "50",
    Placeholder = "e.g. 50",
    Numeric     = true,
    Callback    = function(v)
        merchantSpamCount = tonumber(v) or 50
    end,
})

local function doBuy()
    if merchantBuying then return false end
    local option = merchantOption
    local count  = math.max(1, merchantSpamCount)
    merchantBuying = true
    shopBusy = true
    local opened = false
    for attempt = 1, 5 do
        notify("Shop", "Teleporting to MerchantAU" .. (attempt > 1 and " (retry " .. attempt .. "/5)..." or "..."), 2)
        if openMerchantAU() then opened = true; break end
        task.wait(2)
    end
    if not opened then
        notify("Shop", "MerchantAU NPC not found.", 4)
        merchantBuying = false
        shopBusy = false
        return false
    end
    local BuyItem = game:GetService("ReplicatedStorage").Events:FindFirstChild("BuyItem")
    if not BuyItem then
        notify("Shop", "BuyItem remote not found!", 4)
        merchantBuying = false
        shopBusy = false
        return false
    end
    local itemName = MERCHANT_OPTION_ITEM[option] or "Rokakaka"
    notify("Shop", "Buying " .. count .. "x...", 2)
    local fired = 0
    local prevCount = getItemCount(itemName)
    for i = 1, count do
        shopFire(BuyItem, "MerchantAU", option)
        fired = fired + 1
        if fired % 25 == 0 then
            task.wait(0.3)
            local newCount = getItemCount(itemName)
            if newCount <= prevCount then
                notify("Shop", "Stopped — hit max or out of coins at " .. fired .. " fires.", 4)
                merchantBuying = false
                shopBusy = false
                return false
            end
            prevCount = newCount
        end
    end
    pcall(function()
        lp.PlayerGui.NpcDialouge.Frame.No.MouseButton1Click:Fire()
    end)
    merchantBuying = false
    shopBusy = false
    resetCharacter()
    notify("Shop", "Done! " .. fired .. " purchase(s) fired.", 4)
    return true
end

ShopTab:AddButton({
    Title    = "Buy",
    Icon     = "plus-circle",
    Callback = function() task.spawn(doBuy) end,
})

-- ─── Auto Tab ────────────────────────────────────────────────────────────────

local autoSellEnabled  = false
local autoBuyEnabled   = false
local autoSellMinutes  = 10
local autoBuyMinutes   = 10

-- Auto-tab-specific sell settings (independent of Shop tab)
local autoSellItems    = {}   -- selected item names (multi)
local autoSellAmount   = 1
local autoSellAllFlag  = false

-- Auto-tab-specific buy settings (independent of Shop tab)
local autoBuyOptions   = {}   -- selected option keys (multi)
local autoBuyCount     = 50

local function doAutoSell()
    if #autoSellItems == 0 then
        notify("Auto Sell", "No items selected to sell.", 4)
        return
    end
    local smEvent = game:GetService("ReplicatedStorage").Events.SM_Event
    shopBusy = true
    for _, item in ipairs(autoSellItems) do
        local count = getItemCount(item)
        if count == 0 then
            notify("Auto Sell", "No " .. item .. " to sell, skipping.", 3)
        else
            local amount = autoSellAllFlag and count or math.min(autoSellAmount, count)
            local opened = false
            for attempt = 1, 5 do
                if openStockMarket() then opened = true; break end
                notify("Auto Sell", "Retrying market for " .. item .. " (" .. attempt .. "/5)...", 2)
                task.wait(2)
            end
            if not opened then
                notify("Auto Sell", "Could not open market for " .. item .. ", skipping.", 4)
            else
                pcall(function()
                    lp.PlayerGui.newStockMarketGUI.SM_Frame.SelectFrame.BulkSell.MouseButton1Click:Fire()
                end)
                task.wait(0.3)
                local ok, err = shopFire(smEvent, "Sell", item, amount)
                shopFire(smEvent, "Cancel")
                pcall(function()
                    lp.PlayerGui.newStockMarketGUI.SM_Frame.ExitButton.MouseButton1Click:Fire()
                end)
                if ok then
                    notify("Auto Sell", "Sold " .. amount .. "x " .. item, 4)
                else
                    notify("Auto Sell", "Sell failed (" .. item .. "): " .. tostring(err), 5)
                end
            end
        end
    end
    shopBusy = false
    resetCharacter()
end

local function doAutoBuy()
    if merchantBuying then return end
    if #autoBuyOptions == 0 then
        notify("Auto Buy", "No items selected to buy.", 4)
        return
    end
    local count = math.max(1, autoBuyCount)
    merchantBuying = true
    shopBusy = true
    local BuyItem = game:GetService("ReplicatedStorage").Events:FindFirstChild("BuyItem")
    if not BuyItem then
        notify("Auto Buy", "BuyItem remote not found!", 4)
        merchantBuying = false
        shopBusy = false
        return
    end
    for _, option in ipairs(autoBuyOptions) do
        local opened = false
        for attempt = 1, 5 do
            notify("Auto Buy", "Teleporting to MerchantAU" .. (attempt > 1 and " (retry " .. attempt .. "/5)..." or "..."), 2)
            if openMerchantAU() then opened = true; break end
            task.wait(2)
        end
        if not opened then
            notify("Auto Buy", "MerchantAU NPC not found, skipping.", 4)
        else
            local itemName = MERCHANT_OPTION_ITEM[option] or "Rokakaka"
            notify("Auto Buy", "Buying " .. count .. "x " .. itemName .. "...", 2)
            local fired = 0
            local prevCount = getItemCount(itemName)
            for i = 1, count do
                shopFire(BuyItem, "MerchantAU", option)
                fired = fired + 1
                if fired % 25 == 0 then
                    task.wait(0.3)
                    local newCount = getItemCount(itemName)
                    if newCount <= prevCount then
                        notify("Auto Buy", "Stopped — hit max or out of coins at " .. fired .. " fires.", 4)
                        break
                    end
                    prevCount = newCount
                end
            end
            notify("Auto Buy", "Done! " .. fired .. " purchase(s) fired for " .. itemName, 3)
        end
    end
    pcall(function()
        lp.PlayerGui.NpcDialouge.Frame.No.MouseButton1Click:Fire()
    end)
    merchantBuying = false
    shopBusy = false
    resetCharacter()
end

-- ── Auto Sell UI ─────────────────────────────────────────────────────────────

AutoTab:AddParagraph({
    Title   = "Auto Sell",
    Content = "Automatically sells selected items on a timer. Pick one or more items below — each will be sold in sequence.",
})

AutoTab:AddDropdown("AutoSellItemsPick", {
    Title   = "Items to Sell",
    Icon    = "package",
    Values  = SELLABLE_ITEMS,
    Multi   = true,
    Default = {},
})

Options.AutoSellItemsPick:OnChanged(function()
    autoSellItems = {}
    for k, v in pairs(Options.AutoSellItemsPick.Value) do
        if v then table.insert(autoSellItems, k) end
    end
end)

AutoTab:AddInput("AutoSellAmount", {
    Title       = "Amount per Item",
    Default     = "1",
    Placeholder = "e.g. 10",
    Numeric     = true,
    Callback    = function(v)
        autoSellAmount = tonumber(v) or 1
    end,
})

AutoTab:AddToggle("AutoSellAll", {
    Title   = "Sell All (ignores amount)",
    Icon    = "layers",
    Default = false,
})

Options.AutoSellAll:OnChanged(function()
    autoSellAllFlag = Options.AutoSellAll.Value
end)

AutoTab:AddInput("AutoSellInterval", {
    Title       = "Sell Every (minutes)",
    Default     = "10",
    Placeholder = "e.g. 10",
    Numeric     = true,
    Callback    = function(v)
        autoSellMinutes = tonumber(v) or 10
    end,
})

AutoTab:AddToggle("AutoSell", {
    Title   = "Enable Auto Sell",
    Icon    = "repeat",
    Default = false,
})

Options.AutoSell:OnChanged(function()
    autoSellEnabled = Options.AutoSell.Value
    if not autoSellEnabled then return end
    task.spawn(function()
        while autoSellEnabled do
            local secs = math.max(1, autoSellMinutes) * 60
            notify("Auto Sell", "Next sell in " .. autoSellMinutes .. " min.", 4)
            task.wait(secs)
            if not autoSellEnabled then break end
            doAutoSell()
        end
    end)
end)

-- ── Auto Buy UI ───────────────────────────────────────────────────────────────

AutoTab:AddParagraph({
    Title   = "Auto Buy",
    Content = "Automatically buys from MerchantAU on a timer.",
})

AutoTab:AddDropdown("AutoBuyItemPick", {
    Title   = "Items to Buy",
    Icon    = "shopping-bag",
    Values  = MERCHANT_OPTION_LABELS,
    Multi   = true,
    Default = {},
})

Options.AutoBuyItemPick:OnChanged(function()
    autoBuyOptions = {}
    for k, v in pairs(Options.AutoBuyItemPick.Value) do
        if v then table.insert(autoBuyOptions, MERCHANT_OPTIONS[k] or k) end
    end
end)

AutoTab:AddInput("AutoBuyCount", {
    Title       = "Spam Count",
    Default     = "50",
    Placeholder = "e.g. 50",
    Numeric     = true,
    Callback    = function(v)
        autoBuyCount = tonumber(v) or 50
    end,
})

AutoTab:AddInput("AutoBuyInterval", {
    Title       = "Buy Every (minutes)",
    Default     = "10",
    Placeholder = "e.g. 10",
    Numeric     = true,
    Callback    = function(v)
        autoBuyMinutes = tonumber(v) or 10
    end,
})

AutoTab:AddToggle("AutoBuy", {
    Title   = "Enable Auto Buy",
    Icon    = "repeat",
    Default = false,
})

Options.AutoBuy:OnChanged(function()
    autoBuyEnabled = Options.AutoBuy.Value
    if not autoBuyEnabled then return end
    task.spawn(function()
        while autoBuyEnabled do
            local secs = math.max(1, autoBuyMinutes) * 60
            notify("Auto Buy", "Next buy in " .. autoBuyMinutes .. " min.", 4)
            task.wait(secs)
            if not autoBuyEnabled then break end
            doAutoBuy()
        end
    end)
end)

-- ─── Config Tab ───────────────────────────────────────────────────────────────

pcall(function()
    SaveManager:SetLibrary(Fluent)
    SaveManager:SetFolder("SUR Script")

    SaveManager:BuildConfigSection(ConfigTab)
end)

-- ─── Global stand change watcher (debug) ────────────────────────────────────

pcall(function()
    local data     = lp:WaitForChild("Data", 10)
    if not data then return end
    local standVal = data:WaitForChild("Stand", 10)
    local attriVal = data:FindFirstChild("Attri")
    if not standVal then return end

    standVal.Changed:Connect(function(newValue)
        if not debugMode then return end
        task.spawn(function()
            -- Wait for Attri to replicate too (it lags behind Stand by a frame or two)
            if attriVal then
                local attriReady = false
                local ac = attriVal.Changed:Connect(function() attriReady = true end)
                local dl = tick() + 2
                repeat task.wait(0.05) until attriReady or tick() > dl
                ac:Disconnect()
            end
            local attrib = attriVal and tostring(attriVal.Value) or "?"
            local source = rolling and "Auto Roller" or "Manual / Slot Swap"
            sendDebugWebhook(
                "Data.Stand Changed → " .. tostring(newValue),
                tostring(newValue),
                attrib,
                source
            )
        end)
    end)
end)

-- ─── Hide Travlling GUI ───────────────────────────────────────────────────────

pcall(function()
    local pg = lp.PlayerGui
    local function hideTravlling(gui)
        if gui.Name == "Travlling" then
            pcall(function() gui.Enabled = false end)
            pcall(function() gui:Destroy() end)
        end
    end
    for _, gui in ipairs(pg:GetChildren()) do hideTravlling(gui) end
    pg.ChildAdded:Connect(hideTravlling)
end)

-- ─── Done ─────────────────────────────────────────────────────────────────────

Window:SelectTab(1)
pcall(function() SaveManager:LoadAutoloadConfig() end)
scriptReady = true
Fluent:Notify({Title = "SUR Stand Roller", Content = "Loaded!", Duration = 4})

task.spawn(function()
    local function cleanupMenu()
        -- kill blur effects left behind by MenuGUI scripts
        pcall(function()
            for _, v in ipairs(game:GetService("Lighting"):GetChildren()) do
                if v:IsA("BlurEffect") then v.Enabled = false end
            end
        end)
        -- reset camera to character
        pcall(function()
            game:GetService("RunService").RenderStepped:Wait()
            local cam = workspace.CurrentCamera
            cam.CameraType = Enum.CameraType.Custom
            local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
            if hum then cam.CameraSubject = hum end
        end)
    end

    local function checkAutoRestart()
        pcall(function()
            if isfile(AUTO_RESTART_FILE) then
                local data = HttpService:JSONDecode(readfile(AUTO_RESTART_FILE))
                pcall(function()
                    if delfile then delfile(AUTO_RESTART_FILE)
                    elseif deletefile then deletefile(AUTO_RESTART_FILE) end
                end)
                if type(data) == "table" and data.autoRestart then
                    notify("Auto-Restart", "Roller resuming in 10 seconds...", 6)
                    task.delay(10, function()
                        Options.StartRoller:SetValue(true)
                    end)
                end
            end
        end)
    end

    -- Wait up to 8s for MenuGUI to appear; if it never shows, just check auto-restart and exit
    local menuGui = lp.PlayerGui:FindFirstChild("MenuGUI")
    if not menuGui then
        local deadline = tick() + 8
        repeat task.wait(0.2) until lp.PlayerGui:FindFirstChild("MenuGUI") or tick() > deadline
        menuGui = lp.PlayerGui:FindFirstChild("MenuGUI")
    end

    if not menuGui then
        checkAutoRestart()
        return
    end

    -- Lock the camera every frame at Last priority (runs after game camera scripts)
    local lockedCF = workspace.CurrentCamera.CFrame
    RunService:BindToRenderStep("SUR_CamLock", Enum.RenderPriority.Last.Value, function()
        workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
        workspace.CurrentCamera.CFrame = lockedCF
    end)

    -- Fire PressedPlay every 2s until it succeeds, then destroy the GUI ourselves
    local pressed = false
    local deadline = tick() + 30
    while not pressed and tick() < deadline do
        pcall(function()
            game:GetService("ReplicatedStorage").Events.PressedPlay:FireServer()
            pressed = true
        end)
        if not pressed then task.wait(2) end
    end

    -- Stop fighting the camera, destroy menu, restore everything
    RunService:UnbindFromRenderStep("SUR_CamLock")
    pcall(function() menuGui:Destroy() end)
    pcall(function() lp.PlayerGui.PlayerGUI.Enabled = true end)
    pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true) end)
    cleanupMenu()
    checkAutoRestart()
end)
