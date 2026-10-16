local addonName = ...

-- Replaces the flat portrait on Blizzard's unit frames with a 3D model.
--
-- Clipping: model frames cannot be masked to a circle, so the model lives in
-- a holder frame one strata BELOW the unit frame. The ring art of the unit
-- frame is drawn over it and hides the square's corners; the hole in the ring
-- is transparent, so the model shows through it. A black circle (a real mask
-- texture) sits behind the model to fill the sides that the square misses.
-- `scale` makes the square smaller than the portrait so its corners stay
-- inside the ring. Tune it with /p3d scale.

local DEFAULTS = { enabled = true, scale = 0.85, zoom = 1, petScale = 0.85, petZoom = 1,
  targetScale = 0.85, targetZoom = 1, partyScale = 0.85, partyZoom = 1, partySquareSize = 1.04, anim = "full",
  hideMinimap = false, square = false, squareSize = 1.04, targetSquareSize = 1.04, petSquareSize = 1.04, background = "black",
  borderColor = "gold", showBadge = true, showGlow = true, showZzz = true, universal = false,
  offX = 0, offY = 0, targetOffX = 0, targetOffY = 0, partyOffX = 0, partyOffY = 0, petOffX = 0, petOffY = 0 }

-- Rounded-square border (Textures\RoundedFrame.tga, made by tools\make_frame.py).
-- HOLE is the width of its hole as a fraction of the picture.
local FRAME_TEXTURE = "Interface/AddOns/Portraits3D/Textures/RoundedFrame"
local GLOW_TEXTURE = "Interface/AddOns/Portraits3D/Textures/RoundedGlow"
local GLOW_RATIO = 0.80 -- how much of the glow picture the framed square fills
local RING_CUT_TEXTURE = "Interface/AddOns/Portraits3D/Textures/RingCutEdge"
local EDGE_PAD_TOP = 0.13 -- how far (portrait widths) the kept area reaches above the name text (the plate is taller than its text)
local EDGE_PAD_BOTTOM = 0.05 -- ...and below the mana bar
local RING_KEEP = 0.54 -- Blizzard's frame picture is hidden left of this line (portrait widths from the portrait centre, towards the bars); /p3d ring <n> to try others
local PLAQUE_SHIFT = 0 -- the square frame sits this far (portrait widths) towards the bars
local HOLE = 0.89

-- Frames that can be switched on or off in the options (party 1-4 share one).
local GROUPS = {
  { key = "player", label = "Player" },
  { key = "target", label = "Target" },
  { key = "targettarget", label = "Target of target" },
  { key = "focus", label = "Focus" },
  { key = "pet", label = "Pet" },
  { key = "party", label = "Party" },
}
local DB

local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }

-- Each entry: the unit, and candidate paths to the portrait texture (first one
-- that is a texture wins). Paths are looked up from _G at call time because
-- some frames (party) are only created later.
local ENTRIES = {
  { unit = "player", paths = { "PlayerFrame.PlayerFrameContainer.PlayerPortrait", "PlayerPortrait" },
    ringTex = { "PlayerFrame.PlayerFrameContainer.FrameTexture" },
    nameObj = { "PlayerName", "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.Name" },
    manaObj = { "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar" },
    level = { "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.LevelText",
              "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.LevelBackgroundCircle", "PlayerLevelText" }, side = "left",
    ring = { "PlayerFrame.PlayerFrameContainer" }, content = { "PlayerFrame.PlayerFrameContent" },
    -- the pulsing resting / combat glow around the portrait
    -- the rising Zzz in a rested area; hidden by the "Resting Zzz" option
    zzz = { "PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PlayerRestLoop" },
    rest = { "PlayerFrame.PlayerFrameContainer.FrameFlash",
             "PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PlayerPortraitCornerIcon",
             "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.StatusTexture",
             "PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.StatusTexture",
             "PlayerStatusTexture", "PlayerStatusGlow" } },
  { unit = "target", paths = { "TargetFrame.TargetFrameContainer.Portrait", "TargetFramePortrait" },
    ringTex = { "TargetFrame.TargetFrameContainer.FrameTexture" },
    nameObj = { "TargetFrame.TargetFrameContent.TargetFrameContentMain.Name" },
    manaObj = { "TargetFrame.TargetFrameContent.TargetFrameContentMain.ManaBar" },
    level = { "TargetFrame.TargetFrameContent.TargetFrameContentMain.LevelText",
              "TargetFrame.TargetFrameContent.TargetFrameContentMain.LevelBackgroundCircle", "TargetFrameTextureFrameLevelText" }, side = "right",
    ring = { "TargetFrame.TargetFrameContainer" }, content = { "TargetFrame.TargetFrameContent" },
    -- round decorations: the combat flash and the elite / rare / boss ring
    rest = { "TargetFrame.TargetFrameContainer.Flash", "TargetFrame.TargetFrameContainer.BossPortraitFrameTexture" } },
  { unit = "focus", paths = { "FocusFrame.TargetFrameContainer.Portrait", "FocusFramePortrait" },
    ringTex = { "FocusFrame.TargetFrameContainer.FrameTexture" },
    nameObj = { "FocusFrame.TargetFrameContent.TargetFrameContentMain.Name" },
    manaObj = { "FocusFrame.TargetFrameContent.TargetFrameContentMain.ManaBar" },
    level = { "FocusFrame.TargetFrameContent.TargetFrameContentMain.LevelText",
              "FocusFrame.TargetFrameContent.TargetFrameContentMain.LevelBackgroundCircle", "FocusFrameTextureFrameLevelText" }, side = "right",
    ring = { "FocusFrame.TargetFrameContainer" }, content = { "FocusFrame.TargetFrameContent" },
    rest = { "FocusFrame.TargetFrameContainer.Flash", "FocusFrame.TargetFrameContainer.BossPortraitFrameTexture" } },
  { unit = "pet", paths = { "PetPortrait", "PetFrame.Portrait" },
    ringTex = { "PetFrameTexture", "PetFrame.FrameTexture" },
    nameObj = { "PetName", "PetFrame.name" }, manaObj = { "PetFrameManaBar", "PetFrame.manabar" } },
  { unit = "targettarget", paths = { "TargetFrameToT.Portrait", "TargetFrame.totFrame.Portrait", "TargetFrameToTPortrait" },
    root = "TargetFrame.totFrame", ring = { "TargetFrame.totFrame" },
    nameObj = { "TargetFrame.totFrame.name", "TargetFrame.totFrame.Name" },
    manaObj = { "TargetFrame.totFrame.manabar", "TargetFrame.totFrame.ManaBar" } },
  { unit = "party1", paths = { "PartyFrame.MemberFrame1.Portrait", "PartyMemberFrame1.portrait", "PartyMemberFrame1Portrait" },
    root = "PartyFrame.MemberFrame1", ring = { "PartyFrame.MemberFrame1" },
    ringTex = { "PartyFrame.MemberFrame1.Texture" },
    -- combat / status glows (round shaped)
    rest = { "PartyFrame.MemberFrame1.threatIndicator", "PartyFrame.MemberFrame1.PartyMemberOverlay.Status" },
    nameObj = { "PartyFrame.MemberFrame1.Name" }, manaObj = { "PartyFrame.MemberFrame1.ManaBar" } },
  { unit = "party2", paths = { "PartyFrame.MemberFrame2.Portrait", "PartyMemberFrame2.portrait", "PartyMemberFrame2Portrait" },
    root = "PartyFrame.MemberFrame2", ring = { "PartyFrame.MemberFrame2" },
    ringTex = { "PartyFrame.MemberFrame2.Texture" },
    -- combat / status glows (round shaped)
    rest = { "PartyFrame.MemberFrame2.threatIndicator", "PartyFrame.MemberFrame2.PartyMemberOverlay.Status" },
    nameObj = { "PartyFrame.MemberFrame2.Name" }, manaObj = { "PartyFrame.MemberFrame2.ManaBar" } },
  { unit = "party3", paths = { "PartyFrame.MemberFrame3.Portrait", "PartyMemberFrame3.portrait", "PartyMemberFrame3Portrait" },
    root = "PartyFrame.MemberFrame3", ring = { "PartyFrame.MemberFrame3" },
    ringTex = { "PartyFrame.MemberFrame3.Texture" },
    -- combat / status glows (round shaped)
    rest = { "PartyFrame.MemberFrame3.threatIndicator", "PartyFrame.MemberFrame3.PartyMemberOverlay.Status" },
    nameObj = { "PartyFrame.MemberFrame3.Name" }, manaObj = { "PartyFrame.MemberFrame3.ManaBar" } },
  { unit = "party4", paths = { "PartyFrame.MemberFrame4.Portrait", "PartyMemberFrame4.portrait", "PartyMemberFrame4Portrait" },
    root = "PartyFrame.MemberFrame4", ring = { "PartyFrame.MemberFrame4" },
    ringTex = { "PartyFrame.MemberFrame4.Texture" },
    -- combat / status glows (round shaped)
    rest = { "PartyFrame.MemberFrame4.threatIndicator", "PartyFrame.MemberFrame4.PartyMemberOverlay.Status" },
    nameObj = { "PartyFrame.MemberFrame4.Name" }, manaObj = { "PartyFrame.MemberFrame4.ManaBar" } },
}

local function Resolve(path)
  local obj = _G
  for key in path:gmatch("[^%.]+") do
    if type(obj) ~= "table" then return nil end
    obj = obj[key]
    if obj == nil then return nil end
  end
  return obj
end

-- Looks inside a frame (and its children, a few levels deep) for something
-- stored under a key that passes `test(key, value)`.
local function Discover(rootPath, test)
  local root = Resolve(rootPath)
  if type(root) ~= "table" or not root.GetChildren then return end
  local seen = {}
  local function walk(frame, depth)
    if seen[frame] or depth > 3 then return end
    seen[frame] = true
    for key, value in pairs(frame) do
      if type(key) == "string" and type(value) == "table" and value.GetObjectType and test(key, value) then
        return value, key
      end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
      local found, key = walk(child, depth + 1)
      if found then return found, key end
    end
  end
  return walk(root, 0)
end

local function FindPortrait(entry)
  for _, path in ipairs(entry.paths) do
    local obj = Resolve(path)
    if type(obj) == "table" and obj.GetObjectType and obj:GetObjectType() == "Texture" then
      return obj, path
    end
  end
  -- Not at any of the guessed paths: search the unit frame for a portrait texture.
  if entry.root then
    local obj, key = Discover(entry.root, function(k, v)
      local lower = k:lower()
      return v:GetObjectType() == "Texture" and lower:find("portrait", 1, true) and not lower:find("mask", 1, true)
    end)
    if obj then return obj, entry.root .. " (found as " .. key .. ")" end
  end
end

local function FindObject(paths)
  for _, path in ipairs(paths or {}) do
    local obj = Resolve(path)
    if type(obj) == "table" and obj.SetAlpha then return obj end
  end
end

-- In the square look Blizzard's level text and rest glow are drawn over the
-- model, so they are hidden and the level is shown on our own badge instead.
local hooked = {}
local function Hush(obj, on)
  obj.portraits3dHush = on
  obj:SetAlpha(on and 0 or 1)
  -- Blizzard shows the glow again and pulses it with SetAlpha; keep it hidden.
  if on and not hooked[obj] then
    hooked[obj] = true
    if obj.Show then
      hooksecurefunc(obj, "Show", function(self)
        if self.portraits3dHush then self:SetAlpha(0) end
      end)
    end
    if obj.SetAlpha then
      hooksecurefunc(obj, "SetAlpha", function(self, a)
        if self.portraits3dHush and a ~= 0 then self:SetAlpha(0) end
      end)
    end
  end
end

-- Finds the status / rest / glow pictures somewhere inside a unit frame, in
-- case they are not at the paths we guessed. Our own frames are skipped.
local GLOW_WORDS = { "status", "glow", "flash" }
local function ScanGlows(root, skip, found, depth)
  if depth > 5 then return end
  for _, region in ipairs({ root:GetRegions() }) do
    local atlas = region.GetAtlas and region:GetAtlas()
    if type(atlas) == "string" then
      local lower = atlas:lower()
      for _, word in ipairs(GLOW_WORDS) do
        if lower:find(word, 1, true) then found[#found + 1] = region break end
      end
    end
  end
  for _, child in ipairs({ root:GetChildren() }) do
    if child ~= skip then ScanGlows(child, skip, found, depth + 1) end
  end
end

-- The portrait background: black, a gradient that starts black at the bottom and
-- fades to transparent at the top, the same in the unit's class color, or none.
local function ApplyBackground(entry)
  local bg = entry.bg
  if not bg then return end
  local mode = DB.background or "black"
  if mode == "clear" then
    bg:Hide()
    return
  end
  bg:Show()
  local r, g, b = 0, 0, 0
  local fade = mode == "gradient" or mode == "class"
  if mode == "class" then
    r, g, b = 0, 0, 0 -- units without a class get the plain black gradient
    if UnitIsPlayer and UnitIsPlayer(entry.unit) then
      local _, class = UnitClass(entry.unit)
      local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
      if c then r, g, b = c.r, c.g, c.b end
    end
  end
  local topAlpha = fade and 0 or 1
  bg:SetColorTexture(1, 1, 1, 1)
  local ok = CreateColor and pcall(bg.SetGradient, bg, "VERTICAL",
    CreateColor(r, g, b, 1), CreateColor(r, g, b, topAlpha))
  if not ok then
    -- older gradient call; if that fails too, a flat color
    if not pcall(bg.SetGradientAlpha, bg, "VERTICAL", r, g, b, 1, r, g, b, topAlpha) then
      bg:SetColorTexture(r, g, b, 1)
    end
  end
end

-- Tints the square frame's gold border: gold (as drawn), silver, dark, or the
-- unit's class color (gold for units that are not players).
local function ApplyBorderColor(entry)
  local tex = entry.frameTex
  if not tex then return end
  local mode = DB.borderColor or "gold"
  local r, g, b, desaturate = 1, 1, 1, false
  if mode == "silver" then
    desaturate, r, g, b = true, 0.9, 0.93, 1
  elseif mode == "dark" then
    desaturate, r, g, b = true, 0.55, 0.55, 0.6
  elseif mode == "class" and UnitIsPlayer and UnitIsPlayer(entry.unit) then
    local _, class = UnitClass(entry.unit)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then desaturate, r, g, b = true, c.r, c.g, c.b end
  end
  pcall(tex.SetDesaturated, tex, desaturate)
  tex:SetVertexColor(r, g, b)
end

local function Decorate(entry, active)
  local square = DB.square and active
  for _, path in ipairs(entry.level or {}) do
    local obj = Resolve(path)
    if type(obj) == "table" and obj.SetAlpha then Hush(obj, square) end
  end
  for _, path in ipairs(entry.rest or {}) do
    local obj = Resolve(path)
    if type(obj) == "table" and obj.SetAlpha then Hush(obj, square) end
  end
  for _, path in ipairs(entry.zzz or {}) do
    local obj = Resolve(path)
    if type(obj) == "table" and obj.SetAlpha then Hush(obj, active and DB.showZzz == false) end
  end
  if entry.badge and not entry.levelScanned then
    entry.levelScanned, entry.levelFound = true, {}
    local seen = {}
    for _, list in ipairs({ entry.content or {}, entry.ring or {} }) do
      local root = FindObject(list)
      if root then pcall(ScanLevel, root, entry.levelFound, seen, 0, entry.holder) end
    end
  end
  for _, obj in ipairs(entry.levelFound or {}) do Hush(obj, square) end
  if entry.unit == "player" and PlayerFrame then
    if not entry.scanned and entry.holder then
      entry.scanned, entry.scanFound = true, {}
      pcall(ScanGlows, PlayerFrame, entry.holder, entry.scanFound, 0)
    end
    for _, obj in ipairs(entry.scanFound or {}) do Hush(obj, square) end
  end
  ApplyBackground(entry)
  if square then ApplyBorderColor(entry) end
  if entry.glowTex then
    local combat = UnitAffectingCombat and UnitAffectingCombat("player")
    local resting = IsResting and IsResting()
    if square and DB.showGlow ~= false and (combat or resting) then
      if combat then entry.glowTex:SetVertexColor(1, 0.25, 0.2) else entry.glowTex:SetVertexColor(1, 0.82, 0.2) end
      entry.glowTex:Show()
      entry.border:SetScript("OnUpdate", function()
        entry.glowTex:SetAlpha(0.45 + 0.4 * math.sin(GetTime() * 3))
      end)
    else
      entry.glowTex:Hide()
      entry.border:SetScript("OnUpdate", nil)
    end
  end
  if entry.badge then
    entry.badge:SetShown(square and DB.showBadge ~= false)
    if square then
      local n = UnitLevel(entry.unit)
      entry.badgeText:SetText((n and n > 0) and n or "??")
      -- white on the player frame (Blizzard shows it white there), yellow elsewhere
      if entry.unit == "player" then entry.badgeText:SetTextColor(1, 1, 1) else entry.badgeText:SetTextColor(1, 0.82, 0) end
    end
  end
end

-- Finds the level badge pictures and texts Blizzard keeps in a unit frame's
-- content frame: anything stored under a key with a
-- name starting with "Level", or using the plain small-circle atlas.
local function ScanLevel(root, found, seen, depth, skip)
  if depth > 4 then return end
  for key, value in pairs(root) do
    if type(key) == "string" and type(value) == "table" and value ~= root and value.SetAlpha
        and not seen[value] then
      if key:lower():find("^level") then
        seen[value] = true
        found[#found + 1] = value
      end
    end
  end
  for _, region in ipairs({ root:GetRegions() }) do
    local atlas = region.GetAtlas and region:GetAtlas()
    if type(atlas) == "string" and not seen[region] then
      if atlas:lower() == "ui-hud-unitframe-smallcircle" then
        seen[region] = true
        found[#found + 1] = region
      end
    end
  end
  for _, child in ipairs({ root:GetChildren() }) do
    if child ~= root and child ~= skip then ScanLevel(child, found, seen, depth + 1, skip) end
  end
end

local function StrataBelow(frame)
  local current = frame:GetFrameStrata()
  for i, name in ipairs(STRATA) do
    if name == current then return STRATA[math.max(1, i - 1)] end
  end
  return "LOW"
end

-- Four sets of size and zoom settings: player (no prefix), target (also target
-- of target and focus), party and pet.
local OPT_PREFIX = { pet = "pet", target = "target", targettarget = "target", focus = "target" }
local function Opt(entry, key)
  if DB.universal then return DB[key] end -- one set of settings for every frame
  local prefix = entry.unit:match("^party") and "party" or OPT_PREFIX[entry.unit]
  if prefix then return DB[prefix .. key:sub(1, 1):upper() .. key:sub(2)] end
  return DB[key]
end

local function Layout(entry)
  local holder, clip = entry.holder, entry.clip
  if not holder then return end
  local w, h = holder:GetWidth(), holder:GetHeight()
  if not w or w <= 0 then return end
  if DB.square then
    -- The model fills the hole of the border picture exactly.
    local size = w * Opt(entry, "squareSize")
    entry.border:SetSize(size, size)
    -- Shifted towards the bars (right for player and pet, left for target and
    -- focus) so it covers the part of the ring the mask leaves.
    local shift = (entry.side == "right" and -1 or 1) * w * PLAQUE_SHIFT
    entry.border:ClearAllPoints()
    entry.border:SetPoint("CENTER", entry.portrait, "CENTER", shift, 0)
    clip:ClearAllPoints()
    clip:SetPoint("CENTER", entry.border, "CENTER")
    if entry.glowTex then entry.glowTex:SetSize(size / GLOW_RATIO, size / GLOW_RATIO) end
    if entry.cut then
      -- The mask's centre line goes where Blizzard's name plate and bars begin.
      local dir = entry.side == "right" and -1 or 1
      -- The mask picture's top and bottom edges sit on the top of the name plate
      -- and the bottom of the mana bar, so its rounded corners round those of the
      -- kept frame. If a frame piece cannot be measured, a standard height is used.
      local _, cy = entry.portrait:GetCenter()
      local nameTop, manaBottom
      local nameObj, manaObj = FindObject(entry.nameObj), FindObject(entry.manaObj)
      if nameObj and nameObj.GetTop then nameTop = nameObj:GetTop() end
      if manaObj and manaObj.GetBottom then manaBottom = manaObj:GetBottom() end
      local padTop, padBottom = w * EDGE_PAD_TOP, w * EDGE_PAD_BOTTOM
      local top, height
      if cy and nameTop and manaBottom and nameTop > manaBottom then
        top = nameTop + padTop - cy
        height = (nameTop - manaBottom) + padTop + padBottom
      else
        top, height = w * 0.45, w * 0.9
      end
      entry.cut:SetSize(height, height)
      entry.cut:ClearAllPoints()
      local x = dir * w * (DB.ringKeep or RING_KEEP)
      if dir == 1 then
        entry.cut:SetPoint("TOPLEFT", entry.portrait, "CENTER", x, top)
      else
        entry.cut:SetPoint("TOPRIGHT", entry.portrait, "CENTER", x, top)
      end
    end
    clip:SetSize(size * HOLE, size * HOLE)
    if entry.badge then
      local b = math.max(22, size * 0.42)
      local inset = size * 0.08
      entry.badge:SetSize(b, b)
      entry.badge:ClearAllPoints()
      if entry.side == "left" then
        entry.badge:SetPoint("CENTER", entry.border, "BOTTOMLEFT", inset, inset)
      else
        entry.badge:SetPoint("CENTER", entry.border, "BOTTOMRIGHT", -inset, inset)
      end
    end
  else
    clip:ClearAllPoints()
    clip:SetPoint("CENTER", holder, "CENTER")
    clip:SetSize(w * Opt(entry, "scale"), h * Opt(entry, "scale"))
  end
end

-- Switches one frame between the round look and the rounded-square look.
local function ApplyStyle(entry)
  if not entry.holder then return end
  -- Round look: the model sits BELOW the unit frame and its ring hides the
  -- corners. Square look: the model sits ABOVE the unit frame's ring art (so
  -- it covers the round ring) and the new border is drawn over the model.
  local parent = FindObject(entry.ring) or entry.holder:GetParent()
  local holder = entry.holder
  if DB.square then
    -- Above the frame that holds the ring art (the portrait's own parent is not
    -- always that frame, e.g. on the target).
    holder:SetFrameStrata(parent:GetFrameStrata())
    holder:SetFrameLevel(parent:GetFrameLevel() + 1)
  else
    holder:SetFrameStrata(StrataBelow(parent))
    end
  local base = holder:GetFrameLevel()
  -- The bars and texts live in a sibling "content" frame; lift it above our
  -- border so a border that reaches over them cannot hide them.
  local content = FindObject(entry.content)
  if DB.square and content and content.SetFrameLevel and content:GetFrameLevel() < base + 6
      and not (InCombatLockdown and InCombatLockdown()) then
    pcall(content.SetFrameLevel, content, base + 6)
  end
  entry.clip:SetFrameLevel(base + 1)
  entry.border:SetFrameLevel(base + 3)
  if entry.badge then entry.badge:SetFrameLevel(base + 5) end -- above the dragon, below the content frame (PvP icon)
  entry.bg:ClearAllPoints()
  if DB.square then
    entry.bg:SetAllPoints(entry.clip)
    entry.bg:RemoveMaskTexture(entry.mask)
  else
    entry.bg:SetAllPoints(entry.holder)
    entry.bg:AddMaskTexture(entry.mask)
  end
  entry.border:SetShown(DB.square and entry.holder:IsShown())
  -- Square look: cut a hole in Blizzard's ring picture so the round ring is
  -- hidden instead of covered.
  if entry.cut and entry.ringTexObj then
    if DB.square and not entry.cutOn then
      pcall(entry.ringTexObj.AddMaskTexture, entry.ringTexObj, entry.cut)
      entry.cutOn = true
    elseif not DB.square and entry.cutOn then
      pcall(entry.ringTexObj.RemoveMaskTexture, entry.ringTexObj, entry.cut)
      entry.cutOn = false
    end
  end
  Decorate(entry, entry.holder:IsShown())
  Layout(entry)
end

local function ApplyCamera(entry)
  local model = entry.model
  -- Same order Immersion uses for its portrait models.
  pcall(model.SetCamDistanceScale, model, 1)
  pcall(model.SetPortraitZoom, model, Opt(entry, "zoom"))
  -- Left / right and up / down: moves the model within its frame.
  pcall(model.SetPosition, model, 0, -(Opt(entry, "offX") or 0), Opt(entry, "offY") or 0)
  -- "full" leaves the animation alone: the model plays all its idles by itself.
  if DB.anim ~= "still" then pcall(model.SetPaused, model, false) end
  if DB.anim == "basic" then
    pcall(model.SetAnimation, model, 0, 0) -- the plain stand animation
  elseif DB.anim == "still" then
    pcall(model.SetAnimation, model, 0, 0)
    pcall(model.SetPaused, model, true)
  end
end

local function Setup(entry)
  if entry.holder then return true end
  local portrait, path = FindPortrait(entry)
  if not portrait then return false end
  local parent = portrait:GetParent()
  if not parent then return false end

  local holder = CreateFrame("Frame", nil, parent)
  holder:SetFrameStrata(StrataBelow(parent))
  holder:SetFrameLevel(1)
  holder:SetAllPoints(portrait)

  local bg = holder:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(holder)
  bg:SetColorTexture(0, 0, 0, 1)
  local mask = holder:CreateMaskTexture()
  mask:SetAllPoints(holder)
  mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  bg:AddMaskTexture(mask)

  -- The model sits in a clipping frame so nothing can draw outside its square.
  local clip = CreateFrame("Frame", nil, holder)
  clip:SetPoint("CENTER", holder, "CENTER")
  pcall(clip.SetClipsChildren, clip, true)

  local model = CreateFrame("PlayerModel", nil, clip)
  model:SetAllPoints(clip)
  model:SetScript("OnModelLoaded", function() ApplyCamera(entry) end)

  -- The border picture sits in its own frame above the model.
  local border = CreateFrame("Frame", nil, holder)
  border:SetPoint("CENTER", portrait, "CENTER")
  border:Hide()
  local frameTex = border:CreateTexture(nil, "ARTWORK")
  frameTex:SetAllPoints(border)
  frameTex:SetTexture(FRAME_TEXTURE)
  if entry.unit == "player" then
    -- Our own resting / combat pulse, shaped to the square frame.
    local glowTex = border:CreateTexture(nil, "BACKGROUND")
    glowTex:SetTexture(GLOW_TEXTURE)
    glowTex:SetPoint("CENTER", border, "CENTER")
    glowTex:Hide()
    entry.glowTex = glowTex
  end

  -- A level badge of our own, since Blizzard's sits under the model.
  if entry.level then
    local badge = CreateFrame("Frame", nil, holder)
    -- Round layers, outside in: faint dark outline, thin pale-bronze ring, brown disc
    -- (Blizzard's level circle has a thin tan ring around a dark brown centre).
    local ROUND = "Interface/CharacterFrame/TempPortraitAlphaMask"
    local function Layer(inset, sub, r, g, bl, a)
      local tex = badge:CreateTexture(nil, "ARTWORK", nil, sub)
      tex:SetPoint("TOPLEFT", inset, -inset)
      tex:SetPoint("BOTTOMRIGHT", -inset, inset)
      tex:SetColorTexture(r, g, bl, a or 1)
      local mask = badge:CreateMaskTexture()
      mask:SetPoint("TOPLEFT", inset, -inset)
      mask:SetPoint("BOTTOMRIGHT", -inset, inset)
      mask:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      tex:AddMaskTexture(mask)
      return tex
    end
    Layer(0, 0, 0.03, 0.02, 0.01, 0.55)
    local ring = badge:CreateTexture(nil, "ARTWORK", nil, 1)
    ring:SetPoint("TOPLEFT", 0.5, -0.5)
    ring:SetPoint("BOTTOMRIGHT", -0.5, 0.5)
    ring:SetTexture("Interface/AddOns/Portraits3D/Textures/BadgeRing")
    local disc = badge:CreateTexture(nil, "ARTWORK", nil, 2)
    disc:SetPoint("TOPLEFT", 2, -2)
    disc:SetPoint("BOTTOMRIGHT", -2, 2)
    disc:SetTexture("Interface/AddOns/Portraits3D/Textures/BadgeDisc")
    local text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", badge, "CENTER", 0, 0)
    badge:Hide()
    entry.badge, entry.badgeText = badge, text
  end

  local ringTex = FindObject(entry.ringTex)
  if not ringTex and entry.root then
    ringTex = Discover(entry.root, function(k, v)
      local lower = k:lower()
      return v:GetObjectType() == "Texture" and (lower == "frametexture" or lower == "texture")
    end)
  end
  if ringTex and ringTex.AddMaskTexture and ringTex.GetParent then
    local owner = ringTex:GetParent()
    if owner and owner.CreateMaskTexture then
      local cut = owner:CreateMaskTexture()
      -- The bars are on the right of the portrait (left on target and focus,
      -- which use the mirrored picture).
      local file = RING_CUT_TEXTURE
      if entry.side == "right" then file = file .. "Mirror" end
      cut:SetTexture(file, "CLAMP", "CLAMP")
      cut:SetPoint("CENTER", portrait, "CENTER")
      entry.cut, entry.ringTexObj = cut, ringTex
    end
  end

  entry.portrait, entry.path, entry.holder, entry.clip, entry.model = portrait, path, holder, clip, model
  entry.bg, entry.mask, entry.border, entry.frameTex = bg, mask, border, frameTex
  holder:SetScript("OnSizeChanged", function() Layout(entry) end)
  holder:Hide()
  ApplyStyle(entry)
  return true
end

local function GroupOf(entry)
  return entry.unit:match("^party") and "party" or entry.unit
end

local function Show2D(entry)
  entry.state = nil
  entry.holder:Hide()
  entry.border:Hide()
  Decorate(entry, false)
  entry.portrait:SetAlpha(1)
end

local testParty = false -- /p3d testparty: party frames show the player's model

local function Refresh(entry, force)
  if not Setup(entry) then return end
  local unit = entry.unit
  if testParty and unit:match("^party") then unit = "player" end
  if not DB.enabled or DB.frames[GroupOf(entry)] == false or not UnitExists(unit) or not UnitIsConnected(unit) or not UnitIsVisible(unit) then
    Show2D(entry)
    return
  end
  Decorate(entry, true)
  local state = (UnitGUID(unit) or "?") .. ":" .. tostring(UnitIsDead(unit) and true or false)
  if entry.state == state and not force then return end
  entry.state = state
  entry.holder:Show()
  entry.border:SetShown(DB.square)
  Layout(entry)
  local model = entry.model
  model:ClearModel()
  ApplyCamera(entry) -- before SetUnit, the way other portrait addons do it
  model:SetUnit(unit)
  ApplyCamera(entry)
  -- The model loads a moment later and can reset the camera; apply again.
  C_Timer.After(0.2, function() if entry.holder:IsShown() then ApplyCamera(entry) end end)
  entry.portrait:SetAlpha(0)
end

-- ===== Elite / rare / boss border =====
-- In the square look Blizzard's border sits behind the model, so a copy is drawn
-- above our frame (below the bars and indicators, which stay on top) and
-- Blizzard's own is kept invisible. Offsets are fractions of the border's own
-- width / height.
local DECO_STYLE = {
  normal = { x = 0.10, y = 0.11, size = 0.99 },
  boss = { x = 0.20, y = 0.06, size = 0.99 },
}
local function DecoKind(atlas)
  return (atlas and tostring(atlas):find("Winged")) and "boss" or "normal"
end

local function DecoEntry()
  for _, entry in ipairs(ENTRIES) do
    if entry.unit == "target" then return entry end
  end
end

local function UpdateDeco()
  local entry = DecoEntry()
  if not entry or not entry.holder then return end
  local deco = Resolve("TargetFrame.TargetFrameContainer.BossPortraitFrameTexture")
  if type(deco) ~= "table" or not deco.SetAtlas then return end
  local ov = entry.decoOverlay
  local atlas = deco.GetAtlas and deco:GetAtlas()
  local live = DB.square and DB.enabled and entry.border and entry.holder:IsShown()
    and atlas and deco:IsShown()
  if not live then
    if ov then ov:Hide() end
    return
  end
  local dw, dh = deco:GetSize()
  local dx, dy = 0, 0
  local dcx, dcy = deco:GetCenter()
  local pcx, pcy = entry.portrait:GetCenter()
  if dcx and pcx then dx, dy = dcx - pcx, dcy - pcy end
  local sq = Opt(entry, "squareSize")
  local style = DECO_STYLE[DecoKind(atlas)]
  if not ov then
    ov = CreateFrame("Frame", nil, entry.holder)
    ov.tex = ov:CreateTexture(nil, "OVERLAY")
    entry.decoOverlay = ov
  end
  ov:SetFrameStrata(entry.holder:GetFrameStrata())
  ov:SetFrameLevel(entry.holder:GetFrameLevel() + 4) -- above the border, below the level badge, bars and PvP icon
  ov:SetAllPoints(entry.holder)
  pcall(ov.tex.SetAtlas, ov.tex, atlas)
  local scaled = sq * style.size
  ov.tex:SetSize(dw * scaled, dh * scaled)
  ov.tex:ClearAllPoints()
  ov.tex:SetPoint("CENTER", entry.portrait, "CENTER", dx * sq + style.x * dw, dy * sq + style.y * dh)
  ov:Show()
  Hush(deco, true)
end

local function RefreshAll(force)
  for _, entry in ipairs(ENTRIES) do Refresh(entry, force) end
  UpdateDeco()
end

-- Blizzard decides the border when the target changes; look again just after.
local function SetupDecoEvents()
  local decoEvents = CreateFrame("Frame")
  decoEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
  pcall(decoEvents.RegisterEvent, decoEvents, "UNIT_CLASSIFICATION_CHANGED")
  decoEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
  decoEvents:SetScript("OnEvent", function()
    if C_Timer and C_Timer.After then C_Timer.After(0.1, UpdateDeco) else UpdateDeco() end
  end)
end

local function RefreshUnit(unit, force)
  for _, entry in ipairs(ENTRIES) do
    if entry.unit == unit then Refresh(entry, force) end
  end
end

local function Say(msg) print("|cff66ccffPortraits3D|r " .. msg) end

local win -- the movable options window; win.refresh re-reads the saved values

local function SetNumber(key, n)
  DB[key] = n
  for _, entry in ipairs(ENTRIES) do
    Layout(entry)
    if entry.model and entry.holder:IsShown() then ApplyCamera(entry) end
  end
end

local function SetSquare(on)
  DB.square = on
  for _, entry in ipairs(ENTRIES) do ApplyStyle(entry) end
  RefreshAll(true)
end

local function SetAnimationMode(mode)
  DB.anim = mode
  RefreshAll(true) -- reloads each model so it starts from a clean state
end

local function SetEnabled(on)
  DB.enabled = on
  RefreshAll(true)
end

local GROUP_LABEL = {}
for _, group in ipairs(GROUPS) do GROUP_LABEL[group.key] = group.label end

local function SetBackground(mode)
  DB.background = mode
  for _, entry in ipairs(ENTRIES) do ApplyBackground(entry) end
end

local BACKGROUNDS = {
  { key = "black", label = "Black" },
  { key = "gradient", label = "Gradient" },
  { key = "class", label = "Class gradient" },
  { key = "clear", label = "Transparent" },
}

local function SetBorderColor(mode)
  DB.borderColor = mode
  for _, entry in ipairs(ENTRIES) do ApplyBorderColor(entry) end
end

local ANIMATIONS = {
  { key = "full", label = "All idles" },
  { key = "basic", label = "Basic idle only" },
  { key = "still", label = "No animation" },
}

local BORDERS = {
  { key = "gold", label = "Gold" },
  { key = "silver", label = "Silver" },
  { key = "dark", label = "Dark" },
  { key = "class", label = "Class color" },
}

local COLUMN = 322 -- distance between the two columns of the window
local SetMinimapHidden = function() end -- replaced below, once the minimap button exists

-- Which set of size / camera / position settings the window edits.
local SIZE_GROUPS = {
  { key = "player", label = "Player", prefix = "" },
  { key = "target", label = "Target & focus", prefix = "target" },
  { key = "party", label = "Party", prefix = "party" },
  { key = "pet", label = "Pet", prefix = "pet" },
}

local function BuildWindow()
  local ok, f = pcall(CreateFrame, "Frame", "Portraits3DOptions", UIParent, "BackdropTemplate")
  if not ok then f = CreateFrame("Frame", "Portraits3DOptions", UIParent) end
  f:SetSize(660, 504)
  f:SetPoint("CENTER", UIParent, "CENTER", 200, 0) -- out of the way of the unit frames
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
  end
  tinsert(UISpecialFrames, "Portraits3DOptions") -- Escape closes it

  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 22, -20)
  title:SetText("Portraits3D")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  local controls = {}
  local colX = 0 -- x offset of the column being built

  -- A shaded card with a gold bar on its left edge and a heading.
  local function AddSection(label, top, height)
    local card = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    card:SetColorTexture(1, 1, 1, 0.05)
    card:SetPoint("TOPLEFT", 16 + colX, top)
    card:SetSize(298, height)
    local bar = f:CreateTexture(nil, "BACKGROUND", nil, 2)
    bar:SetColorTexture(1, 0.82, 0, 0.8)
    bar:SetPoint("TOPLEFT", card, "TOPLEFT")
    bar:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT")
    bar:SetWidth(2)
    local text = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -6)
    text:SetText(label)
  end

  -- A check box; showIf (optional) hides it while it returns false.
  local function AddCheck(label, x, y, get, set, showIf)
    local box = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    box:SetSize(24, 24)
    box:SetPoint("TOPLEFT", x + colX, y)
    local text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", box, "RIGHT", 2, 0)
    text:SetText(label)
    box:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    controls[#controls + 1] = function()
      box:SetChecked(get())
      if showIf then
        local show = showIf()
        box:SetShown(show); text:SetShown(show)
      end
    end
  end

  -- A slider on a saved number. key is the setting's name, or a function that
  -- returns it (the size card edits a different setting per frame group).
  local function AddSlider(key, label, lo, hi, y, step, showIf)
    local function Key() return type(key) == "function" and key() or key end
    local text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 30 + colX, y)
    text:SetText(label)
    local value = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    value:SetPoint("TOPLEFT", 30 + colX, y)
    value:SetWidth(262)
    value:SetJustifyH("RIGHT")
    local slider = CreateFrame("Slider", nil, f, "OptionsSliderTemplate")
    slider:SetSize(262, 16)
    slider:SetPoint("TOPLEFT", 30 + colX, y - 18)
    slider:SetMinMaxValues(lo, hi)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    pcall(function() slider.Low:SetText(""); slider.High:SetText(""); slider.Text:Hide() end)
    slider:SetScript("OnValueChanged", function(self, v)
      v = math.floor(v / step + 0.5) * step
      value:SetText(string.format("%.2f", v))
      if self.syncing or math.abs((DB[Key()] or 0) - v) < 1e-6 then return end
      SetNumber(Key(), v)
    end)
    controls[#controls + 1] = function()
      slider.syncing = true
      slider:SetValue(DB[Key()] or 0)
      slider.syncing = false
      value:SetText(string.format("%.2f", DB[Key()] or 0))
      if showIf then
        local show = showIf()
        text:SetShown(show); value:SetShown(show); slider:SetShown(show)
      end
    end
  end

  local function FrameCheck(key, x, y)
    AddCheck(GROUP_LABEL[key], x, y,
      function() return DB.frames[key] ~= false end,
      function(on) DB.frames[key] = on; RefreshAll(true) end)
  end

  local function IsRound() return not DB.square end
  local function IsSquare() return DB.square end

  -- Two check boxes per row, for a list of { key, label } choices.
  local function AddChoices(list, top, current, apply)
    for i, item in ipairs(list) do
      AddCheck(item.label, i % 2 == 1 and 28 or 178, top - math.floor((i - 1) / 2) * 22,
        function() return current() == item.key end,
        function() apply(item.key); f.refresh() end)
    end
  end

  -- ===== Left column =====
  AddSection("GENERAL", -44, 98)
  AddCheck("Show 3D portraits", 28, -70, function() return DB.enabled end, SetEnabled)
  AddCheck("Rounded square frame", 28, -92, function() return DB.square end,
    function(on) SetSquare(on); f.refresh() end)
  AddCheck("Minimap button", 28, -114, function() return not DB.hideMinimap end,
    function(on) SetMinimapHidden(not on) end)

  AddSection("FRAMES", -148, 98)
  FrameCheck("player", 28, -174)
  FrameCheck("target", 178, -174)
  FrameCheck("targettarget", 28, -196)
  FrameCheck("focus", 178, -196)
  FrameCheck("party", 28, -218)
  FrameCheck("pet", 178, -218)

  AddSection("FRAME STYLE", -252, 126)
  AddChoices(BORDERS, -278, function() return DB.borderColor or "gold" end, SetBorderColor)
  AddCheck("Level badge", 28, -326, function() return DB.showBadge ~= false end,
    function(on) DB.showBadge = on; RefreshAll(true) end)
  AddCheck("Resting / combat glow", 140, -326, function() return DB.showGlow ~= false end,
    function(on) DB.showGlow = on; RefreshAll(true) end)

  AddCheck("Resting Zzz", 28, -350, function() return DB.showZzz ~= false end,
    function(on) DB.showZzz = on; RefreshAll(true) end)

  AddSection("BACKGROUND", -384, 76)
  AddChoices(BACKGROUNDS, -410, function() return DB.background or "black" end, SetBackground)

  -- ===== Right column =====
  colX = COLUMN
  local selected = "player" -- the frame group the size card edits
  local function Prefix()
    if DB.universal then return "" end
    for _, group in ipairs(SIZE_GROUPS) do
      if group.key == selected then return group.prefix end
    end
    return ""
  end
  local function K(name)
    local prefix = Prefix()
    return prefix == "" and name or (prefix .. name:sub(1, 1):upper() .. name:sub(2))
  end
  local function Separate() return not DB.universal end

  AddSection("SIZE & POSITION", -44, 332)
  AddCheck("Same for all frames", 28, -70, function() return DB.universal end,
    function(on)
      DB.universal = on
      for _, entry in ipairs(ENTRIES) do
        Layout(entry)
        if entry.model and entry.holder:IsShown() then ApplyCamera(entry) end
      end
      f.refresh()
    end)
  for i, group in ipairs(SIZE_GROUPS) do
    AddCheck(group.label, i % 2 == 1 and 28 or 178, -96 - math.floor((i - 1) / 2) * 22,
      function() return selected == group.key end,
      function() selected = group.key; f.refresh() end, Separate)
  end
  AddSlider(function() return K("scale") end, "Model size", 0.5, 1.2, -150, 0.05, IsRound)
  AddSlider(function() return K("squareSize") end, "Frame size", 0.8, 2, -150, 0.05, IsSquare)
  AddSlider(function() return K("zoom") end, "Camera zoom", 0, 1, -196, 0.05)
  AddSlider(function() return K("offX") end, "Model left / right", -0.5, 0.5, -242, 0.01)
  AddSlider(function() return K("offY") end, "Model up / down", -0.5, 0.5, -288, 0.01)

  AddSection("ANIMATION", -382, 76)
  AddChoices(ANIMATIONS, -408, function() return DB.anim end, SetAnimationMode)

  local reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  reset:SetSize(130, 22)
  reset:SetPoint("BOTTOMRIGHT", -24, 14)
  reset:SetText("Reset to defaults")
  reset:SetScript("OnClick", function()
    DB.frames = {}
    DB.anim = DEFAULTS.anim
    DB.universal = DEFAULTS.universal
    SetBackground(DEFAULTS.background)
    DB.borderColor, DB.showBadge, DB.showGlow = DEFAULTS.borderColor, DEFAULTS.showBadge, DEFAULTS.showGlow
    DB.showZzz = DEFAULTS.showZzz
    SetSquare(DEFAULTS.square)
    for _, prefix in ipairs({ "", "target", "party", "pet" }) do
      for _, name in ipairs({ "scale", "zoom", "squareSize", "offX", "offY" }) do
        local key = prefix == "" and name or (prefix .. name:sub(1, 1):upper() .. name:sub(2))
        SetNumber(key, DEFAULTS[key])
      end
    end
    SetEnabled(DEFAULTS.enabled)
    f.refresh()
  end)

  f.refresh = function() for _, update in ipairs(controls) do update() end end
  f:SetScript("OnShow", f.refresh)
  f:Hide()
  return f
end

local function ToggleWindow()
  win = win or BuildWindow()
  if win:IsShown() then
    win:Hide()
    return
  end
  -- Close the game's settings so the unit frames are visible while tuning.
  if SettingsPanel and SettingsPanel:IsShown() then pcall(HideUIPanel, SettingsPanel) end
  win:Show()
end

-- Minimap button: left click opens the options, right click turns the 3D
-- portraits on or off, drag moves it around the minimap.
local minimapButton

local function PlaceMinimapButton(angle)
  local radius = (tonumber(Minimap:GetWidth()) or 140) / 2 + 6
  minimapButton:ClearAllPoints()
  minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function BuildMinimapButton()
  local button = CreateFrame("Button", "Portraits3DMinimapButton", UIParent)
  minimapButton = button
  button:SetSize(31, 31)
  button:SetFrameStrata("HIGH")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  local icon = button:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface/Icons/INV_Misc_Head_Human_01")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", 2, 0)
  button:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")

  local function Look() icon:SetDesaturated(not DB.enabled) end
  local atan2 = math.atan2 or math.atan
  button:SetScript("OnDragStart", function(self)
    GameTooltip:Hide()
    self:SetScript("OnUpdate", function()
      local cx, cy = Minimap:GetCenter()
      local scale = Minimap:GetEffectiveScale()
      local mx, my = GetCursorPosition()
      DB.minimapAngle = atan2(my / scale - cy, mx / scale - cx)
      PlaceMinimapButton(DB.minimapAngle)
    end)
  end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  button:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then
      SetEnabled(not DB.enabled)
      Look()
      if win and win.refresh then win.refresh() end
    else
      ToggleWindow()
    end
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Portraits3D")
    GameTooltip:AddLine("Left click: options", 1, 1, 1)
    GameTooltip:AddLine("Right click: 3D portraits on/off", 1, 1, 1)
    GameTooltip:AddLine("Drag: move", 1, 1, 1)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)

  SetMinimapHidden = function(hide)
    DB.hideMinimap = hide
    button:SetShown(not hide)
  end
  PlaceMinimapButton(DB.minimapAngle or math.rad(160))
  Look()
  button:SetShown(not DB.hideMinimap)
  -- The minimap can be resized after login; place the button again.
  C_Timer.After(1, function() PlaceMinimapButton(DB.minimapAngle or math.rad(160)) end)
end

-- The entry under Options > AddOns only holds a button that opens the window.
local function BuildPanel()
  local panel = CreateFrame("Frame")
  panel.name = "Portraits3D"

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
  title:SetPoint("TOP", 0, -80)
  title:SetText("Portraits3D")
  local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  sub:SetPoint("TOP", title, "BOTTOM", 0, -8)
  sub:SetText("3D unit frame portraits")

  local open = CreateFrame("Button", nil, panel)
  open:SetNormalFontObject("GameFontHighlightHuge")
  open:SetHighlightFontObject("GameFontNormalHuge")
  open:SetText("Open options  (/p3d)")
  open:SetSize(open:GetTextWidth() + 20, 40)
  open:SetPoint("TOP", sub, "BOTTOM", 0, -60)
  open:SetScript("OnClick", ToggleWindow)

  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, "Portraits3D")
    Settings.RegisterAddOnCategory(category)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end

-- /p3d dump <unit>: lists the named pieces inside a unit frame's ring and
-- content frames, so missing pieces can be found.
local function Dump(unit)
  local entry
  for _, e in ipairs(ENTRIES) do if e.unit == unit then entry = e end end
  if not entry then Say("units: player target focus pet targettarget party1-4") return end
  local lines, seen = 0, {}
  local function walk(frame, label, depth)
    if depth > 3 or seen[frame] then return end
    seen[frame] = true
    local parent = frame.GetParent and frame:GetParent()
    for key, value in pairs(frame) do
      if lines < 70 and type(key) == "string" and type(value) == "table" and value ~= parent
          and value.GetObjectType then
        lines = lines + 1
        local atlas = value.GetAtlas and value:GetAtlas()
        Say(string.format("%s.%s  %s%s", label, key, value:GetObjectType(), atlas and ("  atlas=" .. tostring(atlas)) or ""))
        if value.GetChildren and value ~= entry.holder then walk(value, label .. "." .. key, depth + 1) end
      end
    end
  end
  for _, list in ipairs({ entry.ring or {}, entry.content or {} }) do
    for _, path in ipairs(list) do
      local obj = Resolve(path)
      if type(obj) == "table" then walk(obj, path:match("[^%.]+$"), 0) end
    end
  end
  Say(lines .. " pieces listed")
end

local function Debug()
  for _, entry in ipairs(ENTRIES) do
    local portrait, path = FindPortrait(entry)
    if entry.cut then Say("   ring cut ready for " .. (entry.ringTex and entry.ringTex[1] or "?")) end
    Say(string.format("%-12s %s", entry.unit, portrait and ("portrait at " .. path .. (entry.holder and ", 3D set up" or "")) or "no portrait found"))
    for _, obj in ipairs(entry.levelFound or {}) do
      Say("   hides level piece " .. tostring(obj:GetName() or obj:GetObjectType()))
    end
    for _, list in ipairs({ entry.level or {}, entry.rest or {} }) do
      for _, p in ipairs(list) do
        if type(Resolve(p)) == "table" then Say("   hides " .. p) end
      end
    end
  end
end

SLASH_PORTRAITS3D1 = "/p3d"
SlashCmdList["PORTRAITS3D"] = function(msg)
  local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  if cmd == "on" or cmd == "off" then
    SetEnabled(cmd == "on")
    Say(DB.enabled and "on" or "off")
  elseif cmd == "ring" then
    local n = tonumber(arg)
    if n and n >= 0.3 and n <= 0.9 then
      DB.ringKeep = n
      for _, entry in ipairs(ENTRIES) do Layout(entry) end
      Say("Blizzard frame hidden left of " .. n)
    else
      Say("/p3d ring <0.3-0.9>  (now " .. (DB.ringKeep or RING_KEEP) .. ")")
    end
  elseif cmd == "testparty" then
    if InCombatLockdown and InCombatLockdown() then Say("not while in combat") return end
    testParty = not testParty
    local shown = 0
    if testParty and PartyFrame and PartyFrame.Show then pcall(PartyFrame.Show, PartyFrame) end
    for i = 1, 4 do
      local frame = Resolve("PartyFrame.MemberFrame" .. i) or _G["PartyMemberFrame" .. i]
      if type(frame) == "table" and frame.Show then
        pcall(testParty and frame.Show or frame.Hide, frame)
        shown = shown + 1
      end
    end
    RefreshAll(true)
    Say(testParty and ("party test ON: " .. shown .. " party frames shown with your model; /p3d testparty again to stop") or "party test off")
  elseif cmd == "minimap" then
    SetMinimapHidden(not DB.hideMinimap)
    Say("minimap button " .. (DB.hideMinimap and "hidden" or "shown"))
  elseif cmd == "dump" then
    Dump(arg ~= "" and arg or "player")
  elseif cmd == "debug" then
    Debug()
  elseif cmd == "" or cmd == "options" or cmd == "config" then
    ToggleWindow()
  else
    Say("/p3d on | off | testparty | ring | minimap | debug (/p3d alone opens the options)")
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= addonName then return end
    Portraits3DDB = Portraits3DDB or {}
    DB = Portraits3DDB
    for k, v in pairs(DEFAULTS) do
      if DB[k] == nil then DB[k] = v end
    end
    if type(DB.frames) ~= "table" then DB.frames = {} end
    -- The square frame default size changed; replace the old saved sizes once.
    if not DB.version or DB.version < 10 then
      DB.squareSize, DB.petSquareSize = DEFAULTS.squareSize, DEFAULTS.petSquareSize
      DB.targetSquareSize = DEFAULTS.targetSquareSize
      DB.version = 10
    end
    -- 11: target and party got their own size / zoom; start them from the player's.
    if DB.version < 11 then
      DB.targetScale, DB.partyScale = DB.scale, DB.scale
      DB.targetZoom, DB.partyZoom = DB.zoom, DB.zoom
      DB.partySquareSize = DB.squareSize
      DB.version = 11
    end
    self:UnregisterEvent("ADDON_LOADED")
    BuildPanel()
    BuildMinimapButton()
    SetupDecoEvents()
    -- Not every event exists in every client build; skip the ones that do not.
    for _, name in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
        "GROUP_ROSTER_UPDATE", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_PET", "UNIT_CONNECTION",
        "UNIT_TARGET", "UNIT_LEVEL", "PLAYER_LEVEL_UP", "PLAYER_UPDATE_RESTING", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
      pcall(self.RegisterEvent, self, name)
    end
    -- Party members walking in and out of range raise no clean event.
    C_Timer.NewTicker(1, function() RefreshAll(false) end)
  elseif event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED" then
    RefreshUnit(arg1, true)
  elseif event == "UNIT_TARGET" then
    RefreshUnit("targettarget", false)
  else
    RefreshAll(false)
  end
end)
