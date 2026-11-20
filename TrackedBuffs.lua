local addonName, ns = ...

-- A row of your important buffs (Slice and Dice and the like) under the player frame,
-- styled like Blizzard's aura buttons: the spell icon with the cooldown swipe the
-- target frame's auras use, the stack count in the corner and the time left under it
-- in the game's small yellow font (white and pulsing in the last few seconds).
-- Buffs are matched by name or spell ID and shown in the order of the list.
--
-- IN COMBAT this game hides buffs from addons: asking for them raises an error
-- ("Auras cannot be accessed when secret while tainted"; C_Secrets.ShouldAurasBeSecret()
-- is true). So:
--   * out of combat the real buffs are read (and how long each lasts is remembered);
--   * in combat the buffs already up keep counting down, and a tracked buff you cast
--     yourself starts (or restarts) its timer from your cast, as long as it lasted last
--     time (Slice and Dice: for the combo points just spent);
--   * when combat ends the real buffs are read again.
-- Buffs from other people, early removals and procs show only out of combat.

local DEFAULT_BUFFS = { "Slice and Dice", "Adrenaline Rush", "Blade Flurry", "Evasion", "Sprint",
  "Cold Blood", "Tiger's Fury", "Dash" }
local WARN = 5 -- seconds left when the time turns white and the icon pulses
local GAP = 4
local LINE_EXTRA = 16 -- below each line of icons: room for the time left
local DEFAULT_ROW_WIDTH = 124 -- if the player frame's bars cannot be measured

local MANA_BAR = { "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar",
  "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBar", "PlayerFrame.manabar", "PlayerFrameManaBar" }

local function DB()
  Portraits3DDB = Portraits3DDB or {}
  local db = Portraits3DDB
  if db.trackBuffs == nil then db.trackBuffs = true end
  if type(db.trackedBuffs) ~= "table" then
    db.trackedBuffs = {}
    for i, name in ipairs(DEFAULT_BUFFS) do db.trackedBuffs[i] = name end
  end
  db.buffSize = db.buffSize or 24
  db.buffX = db.buffX or 0
  db.buffY = db.buffY or 0
  return db
end

local function Resolve(path)
  local obj = _G
  for key in path:gmatch("[^%.]+") do
    if type(obj) ~= "table" then return nil end
    obj = obj[key]
    if obj == nil then return nil end
  end
  return obj
end

local function ManaBar()
  for _, path in ipairs(MANA_BAR) do
    local bar = Resolve(path)
    if type(bar) == "table" and bar.GetObjectType then return bar end
  end
end

local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) and true or false end

local function SpellNameOf(id)
  local name
  if C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(id) end
  if name == nil and GetSpellInfo then name = (GetSpellInfo(id)) end
  if IsSecret(name) or type(name) ~= "string" then return nil end
  return name
end

-- Is the game hiding buffs from addons right now (in combat)?
local function AurasRestricted()
  if C_Secrets and C_Secrets.ShouldAurasBeSecret then
    local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
    if ok and secret then return true end
  end
  return false
end

-- name / spell ID -> aura for every buff on you, or nil (and why) while the game hides them
local function ReadBuffs()
  if AurasRestricted() then return nil, "the game hides buffs right now (in combat)" end
  local found = {}
  for i = 1, 40 do
    local name, icon, count, duration, expires, spellId
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
      if not ok then return nil, "the game refused: " .. tostring(a) end
      if not a then break end
      name, icon, count, duration, expires, spellId = a.name, a.icon, a.applications, a.duration, a.expirationTime, a.spellId
    elseif UnitBuff then
      local n, ic, c, _, d, e, _, _, _, sid = UnitBuff("player", i)
      if not n then break end
      name, icon, count, duration, expires, spellId = n, ic, c, d, e, sid
    else
      break
    end
    if IsSecret(name) or IsSecret(duration) or IsSecret(expires) then return nil, "buff details are secret right now" end
    if type(name) ~= "string" then break end
    if IsSecret(icon) then icon = nil end
    if IsSecret(count) then count = 0 end
    if IsSecret(spellId) then spellId = nil end
    local aura = { index = i, name = name, icon = icon, count = tonumber(count) or 0, spellId = spellId,
      duration = tonumber(duration) or 0, expires = tonumber(expires) or 0 }
    found[name:lower()] = found[name:lower()] or aura
    if spellId then found[tostring(spellId)] = found[tostring(spellId)] or aura end
  end
  return found
end

-- How long a buff lasts when the game cannot tell (in combat): what it lasted the last
-- time it was read, else these. Slice and Dice by combo points spent.
local DEFAULT_DURATIONS = {
  ["slice and dice"] = { 9, 12, 15, 18, 21 }, ["adrenaline rush"] = 15, ["blade flurry"] = 15,
  ["evasion"] = 15, ["sprint"] = 15, ["cold blood"] = 0, ["tiger's fury"] = 6, ["dash"] = 15,
}

local function Learned(key)
  local db = DB()
  if type(db.buffLearned) ~= "table" then db.buffLearned = {} end
  db.buffLearned[key] = db.buffLearned[key] or {}
  return db.buffLearned[key]
end

local function GuessDuration(key, cp)
  local learned = Learned(key)
  local default = DEFAULT_DURATIONS[key]
  if type(default) == "table" then
    cp = math.max(1, math.min(#default, cp or 1))
    if learned[cp] then return learned[cp] end
    -- not seen with this many points: the usual length, scaled by any length seen
    -- (talents can make it last longer)
    for c, d in pairs(learned) do
      if type(c) == "number" and default[c] then return default[cp] * d / default[c] end
    end
    return default[cp]
  end
  return learned.base or default or 0
end

-- Spell IDs of the default buffs: a spell you have not learned yet has no icon by its
-- name, but always has one by its ID (for the preview and the options list).
local KNOWN_IDS = {
  ["slice and dice"] = 5171, ["adrenaline rush"] = 13750, ["blade flurry"] = 13877, ["evasion"] = 5277,
  ["sprint"] = 2983, ["cold blood"] = 14177, ["tiger's fury"] = 5217, ["dash"] = 1850,
}

local function SpellIcon(name)
  local icon
  local function Try(what)
    if icon or not what then return end
    if C_Spell and C_Spell.GetSpellTexture then icon = C_Spell.GetSpellTexture(what) end
    if not icon and GetSpellTexture then icon = GetSpellTexture(what) end
  end
  Try(name)
  Try(type(name) == "string" and KNOWN_IDS[name:lower()] or nil)
  return icon or "Interface/Icons/INV_Misc_QuestionMark"
end

-- Preview (from the options window): every tracked buff with a sample timer, so the
-- row can be placed without having the buffs.
local PREVIEW_TIME = 20
local previewStart

local function PreviewBuffs()
  local found = {}
  for _, wanted in ipairs(DB().trackedBuffs) do
    local key = tostring(wanted):lower()
    local id = tonumber(wanted)
    local name = id and ((C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id))) or wanted
    found[key] = { name = name, icon = SpellIcon(id or wanted), count = 0, duration = PREVIEW_TIME,
      expires = previewStart + PREVIEW_TIME }
  end
  return found
end

-- what is known about your buffs: the last real look, plus timers started by your casts
local known = {}

-- combo points spent by the last finisher (for Slice and Dice's length)
local lastPoints, spent, spentAt = 0, 0, -100
local function ComboPoints()
  if not GetComboPoints then return nil end
  local ok, n = pcall(GetComboPoints, "player", "target")
  if not ok or IsSecret(n) then return nil end
  return tonumber(n)
end

local pending -- a tracked buff you just cast: { key, cp, at }, to learn its length from

local row = CreateFrame("Frame", nil, UIParent)
row:SetSize(1, 1)
local buttons = {}

local function NewButton()
  local b = CreateFrame("Frame", nil, row)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints()
  b.cd:SetReverse(true)
  b.cd:SetDrawEdge(false)
  if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
  -- text above the swipe
  b.over = CreateFrame("Frame", nil, b)
  b.over:SetAllPoints()
  b.over:SetFrameLevel(b.cd:GetFrameLevel() + 1)
  b.count = b.over:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  b.count:SetPoint("BOTTOMRIGHT", 2, -1)
  b.time = b.over:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.time:SetPoint("TOP", b, "BOTTOM", 0, -1)
  -- the game's buff tooltip on hover; clicks still go through to what is underneath
  b:EnableMouse(true)
  if b.SetMouseClickEnabled then b:SetMouseClickEnabled(false) end
  b:SetScript("OnEnter", function(self)
    if not self.index then
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
      if self.spellId and GameTooltip.SetSpellByID and not previewStart then
        GameTooltip:SetSpellByID(self.spellId)
      else
        GameTooltip:SetText(self.name or "")
      end
      GameTooltip:AddLine(previewStart and "Preview" or "Timed from your cast (buffs cannot be read in combat)", 0.65, 0.65, 0.65, true)
      GameTooltip:Show()
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:SetUnitAura("player", self.index, "HELPFUL")
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function FormatTime(left)
  if SecondsToTimeAbbrev then return string.format(SecondsToTimeAbbrev(left)) end
  if left >= 60 then return string.format("%d m", math.ceil(left / 60)) end
  return string.format("%d s", math.ceil(left))
end

-- how wide a line of icons may be: the player frame's bars, in the row's own units
local function RowWidth()
  local mana = ManaBar()
  local width = mana and mana:GetWidth()
  if not width or width <= 0 then return DEFAULT_ROW_WIDTH end
  return width * (mana:GetEffectiveScale() or 1) / (row:GetEffectiveScale() or 1)
end

local function Anchor()
  local db = DB()
  local parent = _G.PlayerFrame
  if not parent then return false end
  row:SetParent(parent)
  row:SetFrameLevel(parent:GetFrameLevel() + 20)
  row:ClearAllPoints()
  local mana = ManaBar()
  if mana then
    row:SetPoint("TOPLEFT", mana, "BOTTOMLEFT", db.buffX, db.buffY - 6)
  else
    row:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 100 + db.buffX, 20 + db.buffY)
  end
  return mana ~= nil
end

local anchored
local function Update()
  local db = DB()
  if not anchored then anchored = Anchor() end
  local count = 0
  if db.trackBuffs then
    local now = GetTime()
    for key, aura in pairs(known) do
      if aura.expires > 0 and aura.expires <= now then known[key] = nil end -- ran out
    end
    local have, used = previewStart and PreviewBuffs() or known, {}
    -- as many icons on a line as fit under the player frame's bars
    local perRow = math.max(1, math.floor((RowWidth() + GAP) / (db.buffSize + GAP)))
    for _, wanted in ipairs(db.trackedBuffs) do
      local aura = have[tostring(wanted):lower()]
      if aura and not used[aura] then
        used[aura] = true
        count = count + 1
        local b = buttons[count] or NewButton()
        buttons[count] = b
        b:SetSize(db.buffSize, db.buffSize)
        b:ClearAllPoints()
        -- left to right, then on to the next line down, like the target frame's auras
        local i = count - 1
        b:SetPoint("TOPLEFT", row, "TOPLEFT", (i % perRow) * (db.buffSize + GAP),
          -math.floor(i / perRow) * (db.buffSize + LINE_EXTRA))
        b.icon:SetTexture(aura.icon)
        b.index, b.name, b.spellId = aura.index, aura.name, aura.spellId
        b.count:SetText(aura.count > 1 and aura.count or "")
        b.expires, b.duration = aura.expires, aura.duration
        if aura.duration > 0 and aura.expires > 0 then
          if b.cdStart ~= aura.expires then
            b.cd:SetCooldown(aura.expires - aura.duration, aura.duration)
            b.cdStart = aura.expires
          end
          b.cd:Show()
        else
          b.cd:Hide()
          b.cdStart = nil
          b.time:SetText("")
        end
        b:Show()
      end
    end
  end
  for i = count + 1, #buttons do
    buttons[i]:Hide()
    buttons[i].cdStart = nil
  end
  row:SetShown(count > 0)
end

-- the time under each icon and the pulse when it is about to run out
local elapsedSince = 0
row:SetScript("OnUpdate", function(_, elapsed)
  elapsedSince = elapsedSince + elapsed
  if elapsedSince < 0.05 then return end
  elapsedSince = 0
  local now = GetTime()
  if previewStart and now >= previewStart + PREVIEW_TIME then
    previewStart = now
    Update()
  end
  local ranOut = false
  for _, b in ipairs(buttons) do
    if b:IsShown() and b.duration and b.duration > 0 and b.expires > 0 then
      local left = b.expires - now
      if left <= 0 then left = 0; ranOut = true end
      b.time:SetText(FormatTime(left))
      if left <= WARN then
        b.time:SetTextColor(1, 1, 1)
        b:SetAlpha(0.55 + 0.45 * math.abs(math.sin(now * math.pi)))
      else
        local c = NORMAL_FONT_COLOR
        if c then b.time:SetTextColor(c.r, c.g, c.b) else b.time:SetTextColor(1, 0.82, 0) end
        b:SetAlpha(1)
      end
    else
      b:SetAlpha(1)
    end
  end
  if ranOut and not previewStart then Update() end
end)

local function IsTracked(key, spellId)
  for _, wanted in ipairs(DB().trackedBuffs) do
    local w = tostring(wanted):lower()
    if w == key or (spellId and w == tostring(spellId)) then return true end
  end
  return false
end

-- A real look at your buffs (when the game allows it) replaces what was known, and
-- teaches how long a buff you just cast lasts.
local function Look()
  local found = ReadBuffs()
  if not found then return false end
  known = found
  if pending and GetTime() - pending.at < 3 then
    local aura = found[pending.key]
    if aura and aura.duration > 0 then
      local learned = Learned(pending.key)
      learned.base = aura.duration
      if pending.cp and pending.cp > 0 then learned[pending.cp] = aura.duration end
      pending = nil
    end
  end
  return true
end

-- One of your own spells went off.
local function OnCast(spellId)
  if spellId == nil or IsSecret(spellId) then return end
  local name = SpellNameOf(spellId)
  if not name then return end
  local key = name:lower()
  local now = GetTime()
  -- a buff with no timer (Cold Blood) is used up by your next ability
  for k, aura in pairs(known) do
    if aura.guessed and aura.consumable and aura.key ~= key then known[k] = nil end
  end
  if not IsTracked(key, spellId) then Update() return end
  local cp = (now - spentAt < 1) and spent or (ComboPoints() or 0)
  pending = { key = key, cp = cp, at = now }
  if Look() then Update() return end -- out of combat the game shows the real buff
  local duration = GuessDuration(key, cp)
  local aura = { name = name, icon = SpellIcon(spellId), count = 0, spellId = spellId, key = key,
    duration = duration, expires = duration > 0 and now + duration or 0, guessed = true, consumable = duration == 0 }
  known[key] = aura
  known[tostring(spellId)] = aura
  Update()
end

local events = CreateFrame("Frame")
for _, name in ipairs({ "PLAYER_ENTERING_WORLD", "UNIT_AURA", "PLAYER_REGEN_ENABLED", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_POWER_FREQUENT", "PLAYER_TARGET_CHANGED" }) do
  pcall(events.RegisterEvent, events, name)
end
events:SetScript("OnEvent", function(_, event, unit, a2, a3)
  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    if unit == "player" then OnCast(a3) end
    return
  elseif event == "UNIT_POWER_FREQUENT" then
    if unit ~= "player" or a2 ~= "COMBO_POINTS" then return end
    local p = ComboPoints()
    if p then
      if p < lastPoints then spent, spentAt = lastPoints, GetTime() end
      lastPoints = p
    end
    return
  elseif event == "PLAYER_TARGET_CHANGED" then
    lastPoints = ComboPoints() or 0
    return
  elseif event == "UNIT_AURA" then
    if unit ~= "player" then return end
  elseif event == "PLAYER_ENTERING_WORLD" then
    anchored = Anchor()
  end
  Look()
  Update()
end)

-- /p3d dev buffs: what the game lets the addon see of your buffs right now
function ns.BuffsDebug(Say)
  local found, why = ReadBuffs()
  if not found then
    Say("buffs cannot be read right now: " .. tostring(why))
  else
    local names = {}
    for key, aura in pairs(found) do
      if key == aura.name:lower() then names[#names + 1] = string.format("%s (%s, %.0f s left)", aura.name,
        tostring(aura.spellId), aura.expires > 0 and aura.expires - GetTime() or 0) end
    end
    Say(#names .. " buffs read: " .. (#names > 0 and table.concat(names, ", ") or "none"))
  end
  local showing = {}
  for _, b in ipairs(buttons) do
    if b:IsShown() then
      showing[#showing + 1] = string.format("%s%s", b.name or "?", b.expires and b.expires > 0
        and string.format(" (%.0f s left)", b.expires - GetTime()) or "")
    end
  end
  Say("showing: " .. (#showing > 0 and table.concat(showing, ", ") or "nothing"))
  for key, learned in pairs(DB().buffLearned or {}) do
    local parts = {}
    for k, v in pairs(learned) do parts[#parts + 1] = tostring(k) .. "=" .. string.format("%.1f", v) end
    if #parts > 0 then Say("  remembered length of " .. key .. ": " .. table.concat(parts, " ")) end
  end
end

-- for the options window
function ns.BuffsRefresh()
  anchored = Anchor()
  Update()
end

function ns.BuffsPreview(on)
  if on == nil then return previewStart ~= nil end
  previewStart = on and GetTime() or nil
  for _, b in ipairs(buttons) do b.cdStart = nil end
  Update()
end

function ns.BuffsList() return DB().trackedBuffs end

-- returns false if it is already in the list
function ns.BuffsAdd(name)
  name = name and name:match("^%s*(.-)%s*$") or ""
  if name == "" then return false end
  local db = DB()
  for _, have in ipairs(db.trackedBuffs) do
    if tostring(have):lower() == name:lower() then return false end
  end
  table.insert(db.trackedBuffs, name)
  ns.BuffsPreview(ns.BuffsPreview())
  return true
end

function ns.BuffsRemove(i)
  table.remove(DB().trackedBuffs, i)
  ns.BuffsPreview(ns.BuffsPreview())
end

function ns.BuffsResetList()
  DB().trackedBuffs = nil
  DB()
  ns.BuffsPreview(ns.BuffsPreview())
end

ns.SpellIcon = SpellIcon

-- /p3d buffs [on | off | list | add <name or id> | remove <name or id> | reset | size <n> | move <x> <y>]
function ns.BuffsCommand(arg, Say)
  local db = DB()
  local cmd, rest = (arg or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  if cmd == "" or cmd == "list" then
    Say("tracked buffs (" .. (db.trackBuffs and "on" or "off") .. "): " .. table.concat(db.trackedBuffs, ", "))
    Say("/p3d buffs on | off | add <name or id> | remove <name or id> | reset | size <n> | move <x> <y>")
    return
  elseif cmd == "on" or cmd == "off" then
    db.trackBuffs = cmd == "on"
    Say("tracked buffs " .. cmd)
  elseif cmd == "add" and rest ~= "" then
    for _, name in ipairs(db.trackedBuffs) do
      if tostring(name):lower() == rest:lower() then Say("already tracking " .. rest) return end
    end
    table.insert(db.trackedBuffs, rest)
    Say("tracking " .. rest)
  elseif cmd == "remove" and rest ~= "" then
    local before = #db.trackedBuffs
    for i = #db.trackedBuffs, 1, -1 do
      if tostring(db.trackedBuffs[i]):lower() == rest:lower() then
        table.remove(db.trackedBuffs, i)
      end
    end
    Say(#db.trackedBuffs < before and ("no longer tracking " .. rest) or (rest .. " was not in the list"))
  elseif cmd == "reset" then
    db.trackedBuffs = nil
    db.buffSize, db.buffX, db.buffY = nil, nil, nil
    DB()
    Say("tracked buffs reset")
  elseif cmd == "size" and tonumber(rest) then
    db.buffSize = math.max(12, math.min(64, tonumber(rest)))
    Say("buff icon size " .. db.buffSize)
  elseif cmd == "move" then
    local x, y = rest:match("^(%-?[%d%.]+)%s+(%-?[%d%.]+)$")
    if not x then Say("/p3d buffs move <x> <y>  (from where it starts: right is +x, up is +y)") return end
    db.buffX, db.buffY = tonumber(x), tonumber(y)
    Say(string.format("buff row moved to %s, %s", x, y))
  else
    Say("/p3d buffs on | off | list | add <name or id> | remove <name or id> | reset | size <n> | move <x> <y>")
    return
  end
  anchored = Anchor()
  Update()
end
