local addonName, ns = ...

-- Combo points:
--   * on the target's nameplate: our own, drawn with Blizzard's own combo point art (the
--     modern round points of the newer unit frames, or the red gems of the old target
--     frame), on the top edge of the health bar, drawn above the cast bar;
--   * on the target frame: the game draws its own there; this only moves them by the
--     offset set in the options (the game's points are never replaced or copied).
-- Combo points belong to your target, so only the target gets them.

local MODERN = {
  ROGUE = { bg = "uf-roguecp-bg", point = "uf-roguecp-icon-red" },
  DRUID = { bg = "uf-druidcp-bg", point = "uf-druidcp-icon" },
}
local CLASSIC_FILE = "Interface\\ComboFrame\\ComboPoint"
local MODERN_SCALE = 0.75 -- the modern points at full size are large for a nameplate
local CAT_FORM = 1
-- the drawing layer above each one (for drawing the nameplate's points over the whole plate)
local NEXT_STRATA = { BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG",
  DIALOG = "FULLSCREEN", FULLSCREEN = "FULLSCREEN_DIALOG", FULLSCREEN_DIALOG = "TOOLTIP" }

local DEFAULTS = {
  plateCombo = true, plateComboStyle = "modern", plateComboScale = 1, plateComboX = 0, plateComboY = 0,
  frameComboX = 0, frameComboY = 0,
}

local function DB()
  Portraits3DDB = Portraits3DDB or {}
  local db = Portraits3DDB
  for k, v in pairs(DEFAULTS) do
    if db[k] == nil then db[k] = v end
  end
  if db.plateComboStyle ~= "classic" then db.plateComboStyle = "modern" end -- ("auto" was removed)
  return db
end

local function AtlasExists(name)
  return name and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function ModernSet()
  local _, class = UnitClass("player")
  local set = MODERN[class]
  if set and AtlasExists(set.bg) and AtlasExists(set.point) then return set end
  set = MODERN.ROGUE
  if AtlasExists(set.bg) and AtlasExists(set.point) then return set end
end

-- "modern", set  or  "classic" (also when the game has no modern art)
local function PickStyle()
  local set = ModernSet()
  if DB().plateComboStyle == "classic" or not set then return "classic" end
  return "modern", set
end

local function Points()
  if GetComboPoints then
    local ok, n = pcall(GetComboPoints, "player", "target")
    if ok and n then return n end
  end
  local kind = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
  return UnitPower("player", kind) or 0
end

local function MaxPoints()
  local kind = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
  local n = UnitPowerMax and UnitPowerMax("player", kind) or 0
  if not n or n < 1 then n = 5 end
  return math.min(n, 10)
end

-- Rogues always, druids in cat form: show the empty slots too, as Blizzard does.
local function UsesComboPoints()
  local _, class = UnitClass("player")
  if class == "ROGUE" then return true end
  if class == "DRUID" and GetShapeshiftFormID then return GetShapeshiftFormID() == CAT_FORM end
  return false
end

-- ===== The target frame: moving the game's own combo points =====

-- The game's combo point frame on the target frame: ComboFrame in most versions, else
-- the first frame with "Combo" in its name or key inside the target frame.
local blizzCombo
local function FindBlizzardCombo()
  if blizzCombo then return blizzCombo end
  if type(_G.ComboFrame) == "table" and _G.ComboFrame.GetPoint then
    blizzCombo = _G.ComboFrame
    return blizzCombo
  end
  local tf = _G.TargetFrame
  if type(tf) ~= "table" then return end
  local seen = {}
  local function Walk(frame, depth)
    if depth > 4 or seen[frame] then return end
    seen[frame] = true
    for key, child in pairs(frame) do
      if type(key) == "string" and key:find("Combo") and type(child) == "table" and child.GetPoint then
        return child
      end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
      local name = child.GetName and child:GetName()
      if name and name:find("Combo") then return child end
      local found = Walk(child, depth + 1)
      if found then return found end
    end
  end
  blizzCombo = Walk(tf, 0)
  return blizzCombo
end

-- Where the game put it (all of its anchors), so the offset is always added to that.
local home
local moving = false
local function SaveHome(frame)
  home = {}
  for i = 1, frame:GetNumPoints() do
    home[i] = { frame:GetPoint(i) }
  end
end

local function MoveBlizzardCombo()
  local frame = FindBlizzardCombo()
  if not frame then return end
  if not home then
    SaveHome(frame)
    -- if the game places it again, take that as its new home and add the offset again
    hooksecurefunc(frame, "SetPoint", function(self)
      if moving then return end
      SaveHome(self)
      MoveBlizzardCombo()
    end)
  end
  if #home == 0 then return end
  local db = DB()
  moving = true
  frame:ClearAllPoints()
  for _, p in ipairs(home) do
    local point, relativeTo, relativePoint, x, y = p[1], p[2], p[3], p[4] or 0, p[5] or 0
    frame:SetPoint(point, relativeTo, relativePoint, x + db.frameComboX, y + db.frameComboY)
  end
  moving = false
end

-- ===== The nameplate: our own points =====

local display = { bar = CreateFrame("Frame", nil, UIParent), points = {}, shown = 0 }
display.bar:Hide()

local function NewPoint(d)
  local p = CreateFrame("Frame", nil, d.bar)
  p.bg = p:CreateTexture(nil, "BACKGROUND")
  p.fill = p:CreateTexture(nil, "ARTWORK")
  p.shine = p:CreateTexture(nil, "OVERLAY")
  p.shine:SetAlpha(0)

  p.fillAnim = p.fill:CreateAnimationGroup()
  local a = p.fillAnim:CreateAnimation("Alpha")
  a:SetFromAlpha(0) a:SetToAlpha(1) a:SetDuration(0.2)
  p.fillAnim:SetScript("OnFinished", function() p.fill:SetAlpha(1) end)

  p.shineAnim = p.shine:CreateAnimationGroup()
  local s1 = p.shineAnim:CreateAnimation("Alpha")
  s1:SetFromAlpha(0) s1:SetToAlpha(1) s1:SetDuration(0.15) s1:SetOrder(1)
  local s2 = p.shineAnim:CreateAnimation("Alpha")
  s2:SetFromAlpha(1) s2:SetToAlpha(0) s2:SetDuration(0.35) s2:SetStartDelay(0.1) s2:SetOrder(2)
  p.shineAnim:SetScript("OnFinished", function() p.shine:SetAlpha(0) end)

  -- a spent point fades out instead of vanishing
  p.fadeAnim = p.fill:CreateAnimationGroup()
  local f = p.fadeAnim:CreateAnimation("Alpha")
  f:SetFromAlpha(1) f:SetToAlpha(0) f:SetDuration(0.25)
  p.fadeAnim:SetScript("OnFinished", function() p.fill:Hide() p.fill:SetAlpha(1) end)
  return p
end

-- the points' pictures for the current style, side by side
local function Build(d)
  local style, set = PickStyle()
  local max = MaxPoints()
  local key = style .. (set and set.point or "") .. max
  if d.built == key then return end
  d.built = key

  if style == "modern" then
    local info = C_Texture.GetAtlasInfo(set.bg)
    d.w, d.h = info.width, info.height
  else
    d.w, d.h = 12, 16
  end
  d.baseScale = style == "modern" and MODERN_SCALE or 1
  local gap = 1

  for i = 1, math.max(max, #d.points) do
    local p = d.points[i] or NewPoint(d)
    d.points[i] = p
    p.bg:ClearAllPoints() p.fill:ClearAllPoints() p.shine:ClearAllPoints()
    p.bg:SetTexCoord(0, 1, 0, 1) p.fill:SetTexCoord(0, 1, 0, 1) p.shine:SetTexCoord(0, 1, 0, 1)
    if style == "modern" then
      p.bg:SetAtlas(set.bg, true)
      p.bg:SetPoint("CENTER")
      p.bg:SetBlendMode("BLEND")
      p.fill:SetAtlas(set.point, true)
      p.fill:SetPoint("CENTER")
      p.fill:SetBlendMode("BLEND")
      p.shine:SetAtlas(set.point, true)
      p.shine:SetPoint("CENTER")
      p.shine:SetBlendMode("ADD")
    else
      -- the old target frame's ComboPoint: a dark socket, a red gem added on top
      -- and a quick white shine when a point is gained
      p.bg:SetTexture(CLASSIC_FILE)
      p.bg:SetTexCoord(0, 0.375, 0, 1)
      p.bg:SetSize(12, 16)
      p.bg:SetPoint("TOPLEFT")
      p.bg:SetBlendMode("BLEND")
      p.fill:SetTexture(CLASSIC_FILE)
      p.fill:SetTexCoord(0.375, 0.5625, 0, 1)
      p.fill:SetSize(8, 16)
      p.fill:SetPoint("TOPLEFT", 2, 0)
      p.fill:SetBlendMode("ADD")
      p.shine:SetTexture(CLASSIC_FILE)
      p.shine:SetTexCoord(0.5625, 1, 0, 1)
      p.shine:SetSize(14, 8)
      p.shine:SetPoint("TOP", 2, 2)
      p.shine:SetBlendMode("ADD")
    end
    p:SetSize(d.w, d.h)
    p:ClearAllPoints()
    p:SetPoint("LEFT", d.bar, "LEFT", (i - 1) * (d.w + gap), 0)
    p:SetShown(i <= max)
  end
  d.bar:SetSize(max * d.w + (max - 1) * gap, d.h)
end

local function TargetPlate()
  if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
  local plate = C_NamePlate.GetNamePlateForUnit("target")
  if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
  return plate
end

local function Attach(d, plate)
  local db = DB()
  local uf = plate.UnitFrame or plate
  local health = uf.healthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar)
  local bar = d.bar
  bar:SetParent(uf)
  -- one drawing layer (strata) above the nameplate: nothing on it, the cast bar
  -- included, can cover the points, however the game stacks its own parts
  local ORDER = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
  local strata = uf:GetFrameStrata()
  for _, part in ipairs({ plate, uf.castBar, uf.CastBar }) do
    local s2 = type(part) == "table" and part.GetFrameStrata and part:GetFrameStrata()
    if s2 and (ORDER[s2] or 0) > (ORDER[strata] or 0) then strata = s2 end
  end
  bar:SetFrameStrata(NEXT_STRATA[strata] or strata)
  bar:SetFrameLevel(math.min(uf:GetFrameLevel() + 10, 9000))
  local scale = d.baseScale * db.plateComboScale
  bar:SetScale(scale)
  bar:ClearAllPoints()
  -- centred on the top edge of the health bar, moved by the player's offset (in the
  -- nameplate's own pixels, whatever the points' size)
  local x, y = db.plateComboX / scale, db.plateComboY / scale
  if health then
    bar:SetPoint("CENTER", health, "TOP", x, y)
  else
    bar:SetPoint("BOTTOM", uf, "TOP", x, y)
  end
end

-- take the points off (a nameplate gets reused for other units) and clear them
local function Detach(d)
  for _, p in ipairs(d.points) do
    p.fillAnim:Stop() p.shineAnim:Stop() p.fadeAnim:Stop()
    p.fill:Hide() p.fill:SetAlpha(1) p.shine:SetAlpha(0)
  end
  d.bar:Hide()
  d.bar:SetParent(UIParent)
  d.shown = 0
end

-- light points 1..n, animating the ones just gained or spent
local function Light(d, n)
  local visible = d.bar:IsVisible()
  for i, p in ipairs(d.points) do
    if i <= n then
      if p.fadeAnim:IsPlaying() then p.fadeAnim:Stop() end
      if i > d.shown and visible then
        p.fill:SetAlpha(0)
        p.fillAnim:Stop() p.fillAnim:Play()
        p.shineAnim:Stop() p.shineAnim:Play()
      elseif not p.fillAnim:IsPlaying() then
        p.fill:SetAlpha(1)
      end
      p.fill:Show()
    else
      p.fillAnim:Stop() p.shineAnim:Stop()
      p.shine:SetAlpha(0)
      if i <= d.shown and visible and p.fill:IsShown() then
        if not p.fadeAnim:IsPlaying() then p.fadeAnim:Play() end
      elseif not p.fadeAnim:IsPlaying() then
        p.fill:Hide()
      end
    end
  end
  d.bar:Show()
  d.shown = n
end

local function Update()
  local db = DB()
  local target = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")
  local n = target and Points() or 0
  local plate = target and (n > 0 or UsesComboPoints()) and db.plateCombo and TargetPlate()
  if plate then
    Build(display)
    Attach(display, plate)
    Light(display, n)
  else
    Detach(display)
  end
end

local events = CreateFrame("Frame")
for _, name in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED", "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER",
    "UNIT_COMBO_POINTS", "UPDATE_SHAPESHIFT_FORM", "UNIT_HEALTH", "UNIT_FLAGS", "UNIT_FACTION" }) do
  pcall(events.RegisterEvent, events, name)
end
events:SetScript("OnEvent", function(_, event, unit, kind)
  if event == "PLAYER_ENTERING_WORLD" then
    MoveBlizzardCombo()
  elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
    if unit ~= "player" or (kind and kind ~= "COMBO_POINTS") then return end
    if event == "UNIT_MAXPOWER" then display.built = nil end
  elseif event == "UNIT_HEALTH" or event == "UNIT_FLAGS" or event == "UNIT_FACTION" then
    if unit ~= "target" then return end
  elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
    if not (unit and UnitIsUnit(unit, "target")) then return end
    if event == "NAME_PLATE_UNIT_REMOVED" then
      -- the plate is about to be reused for another unit; take the points off it
      Detach(display)
      return
    end
  elseif event == "PLAYER_TARGET_CHANGED" then
    display.shown = 0
  end
  Update()
end)

-- for the options window: apply changed settings
function ns.ComboRefresh()
  display.built = nil
  MoveBlizzardCombo()
  Update()
end
ns.COMBO_DEFAULTS = DEFAULTS

-- for /p3d dev combo: what was found to move
function ns.ComboDebug(Say)
  local frame = FindBlizzardCombo()
  if not frame then Say("the game's target-frame combo points were not found") return end
  Say("the game's target-frame combo points: " .. tostring(frame.GetName and frame:GetName() or "(no name)"))
  for i, p in ipairs(home or {}) do
    local rel = p[2]
    Say(string.format("  home %d: %s of %s %s %.1f, %.1f", i, tostring(p[1]),
      tostring(rel and rel.GetName and rel:GetName() or rel), tostring(p[3]), p[4] or 0, p[5] or 0))
  end
end

-- /p3d combo [plate | frame] [on | off | scale <n> | move <x> <y>], /p3d combo modern | classic
function ns.ComboCommand(arg, Say)
  local db = DB()
  local words = {}
  for w in (arg or ""):lower():gmatch("%S+") do words[#words + 1] = w end
  local where = "plate"
  if words[1] == "plate" or words[1] == "frame" then where = table.remove(words, 1) end
  local cmd = words[1] or ""
  if where == "frame" then
    if cmd == "move" and tonumber(words[2]) and tonumber(words[3]) then
      db.frameComboX, db.frameComboY = tonumber(words[2]), tonumber(words[3])
    else
      Say("/p3d combo frame move <x> <y>   (moves the game's own combo points on the target frame)")
      return
    end
  elseif cmd == "" then
    db.plateCombo = not db.plateCombo
  elseif cmd == "on" or cmd == "off" then
    db.plateCombo = cmd == "on"
  elseif cmd == "modern" or cmd == "classic" then
    db.plateComboStyle = cmd
    if cmd == "modern" and not ModernSet() then Say("this client has no modern combo point art; using classic") end
  elseif cmd == "scale" and tonumber(words[2]) then
    db.plateComboScale = math.max(0.3, math.min(3, tonumber(words[2])))
  elseif cmd == "move" and tonumber(words[2]) and tonumber(words[3]) then
    db.plateComboX, db.plateComboY = tonumber(words[2]), tonumber(words[3])
  else
    Say("/p3d combo [on | off | scale <n> | move <x> <y>]   (the nameplate's combo points)")
    Say("/p3d combo modern | classic   (their art)")
    Say("/p3d combo frame move <x> <y>   (moves the game's own combo points on the target frame)")
    return
  end
  ns.ComboRefresh()
  Say(string.format("nameplate combo points %s, style %s (%s), scale %.2f, moved %s, %s",
    db.plateCombo and "on" or "off", db.plateComboStyle, (PickStyle()), db.plateComboScale, db.plateComboX, db.plateComboY))
  Say(string.format("target frame combo points moved %s, %s", db.frameComboX, db.frameComboY))
end
