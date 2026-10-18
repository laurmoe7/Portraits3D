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
  hideMinimap = true, square = false, squareSize = 1.04, targetSquareSize = 1.04, petSquareSize = 1.04, background = "black",
  squareStyle = "classic", showBadge = true, showGlow = true, showZzz = true, greyDead = true, hideCombatText = false, hideSwords = false, gradient = 1, gradientAlpha = 1,
  turn = 0, targetTurn = 0, partyTurn = 0, petTurn = 0,
  frameX = 0, targetFrameX = 0, partyFrameX = 0, petFrameX = 0, universal = false,
  offX = 0, offY = 0, targetOffX = 0, targetOffY = 0, partyOffX = 0, partyOffY = 0, petOffX = 0, petOffY = 0 }

-- Rounded-square border (Textures\RoundedFrame.tga, made by tools\make_frame.py).
-- HOLE is the width of its hole as a fraction of the picture.
local FRAME_TEXTURE = "Interface/AddOns/Portraits3D/Textures/RoundedFrame"
local GLOW_TEXTURE = "Interface/AddOns/Portraits3D/Textures/RoundedGlow"
local GLOW_RATIO = 0.80 -- how much of the glow picture the framed square fills
local RING_CUT_TEXTURE = "Interface/AddOns/Portraits3D/Textures/RingCutEdge"
local EDGE_PAD_TOP = 0.13 -- how far (portrait widths) the kept area reaches above the name text (the plate is taller than its text)
local EDGE_PAD_BOTTOM = 0.05 -- ...and below the mana bar
local RING_KEEP = 0.54 -- Blizzard's frame picture is hidden left of this line (portrait widths from the portrait centre, towards the bars); adjust it here
local PLAQUE_SHIFT = 0 -- the square frame sits this far (portrait widths) towards the bars
local HOLE = 0.89

-- "Blended" square (Textures\RoundedFrameBlend.tga, made by tools\make_blend_frame.py):
-- shaded like Blizzard's ring and drawn at the ring's own place and size, so the
-- name plate and bars tuck under it the way they tuck under the ring. Instead of
-- cutting Blizzard's picture at a line, only the round ring is removed from it.
local FRAME_BLEND_TEXTURE = "Interface/AddOns/Portraits3D/Textures/RoundedFrameBlend"
-- the hole that removes the ring has a straight side towards the bars, so the plate's
-- edge line (right against the ring) and the joints of the bar lines are kept
local RING_HOLE_TEXTURE = "Interface/AddOns/Portraits3D/Textures/RingHoleCut"
local HOLE_BLEND = 0.85 -- hole width of RoundedFrameBlend
local HOLE_DISC = 0.84 -- the round hole's width in RingHoleCut, as a fraction of the picture
local FLAT_CUT = 0.714 -- where its straight side is, as a fraction of the half width
local PLATE_KEEP = 1.2 -- the straight side stops this far inside the ring's radius (unless a ring sets `cut`)
-- Space left between the blended square and the bars (the ring touches them), how much
-- further away from the bars the square is moved, and how much smaller it is drawn
-- (it shrinks away from the bars' side). Small frames (pet, party, target of target)
-- get a tighter fit, and are a little smaller and lower so they clear the frame above them.
local FIT = { gap = 4, shift = 1.5, shrink = 0, down = 0 }
local FIT_SMALL = { gap = 2, shift = 1.5, shrink = 2, down = 1.5 }
-- The portrait rings in the game's unit frame picture (Interface\HUD\UIUnitFrameC60,
-- 1024 x 512): centre and outer radius in that picture's pixels, and (`cut`) how far
-- from the centre the plate's edge line begins when that is closer than r - PLATE_KEEP.
-- A frame finds its ring by looking for the one inside the part of the picture it shows.
local ATLAS_W, ATLAS_H = 1024, 512
local RINGS = {
  -- player (measured centre 441.5 / 641.5): in game its picture lands about 1.9 px
  -- further left than worked out from it, so the centre is set that much further left
  { x = 439.6, y = 36.5, r = 34, cut = 31.8 }, { x = 639.6, y = 36.5, r = 34, cut = 31.8 }, -- edge line 32.5 out
  { x = 40.5, y = 40, r = 33.5 },     -- player (vehicle)
  { x = 365, y = 42.5, r = 33.5 },    -- target (vehicle)
  { x = 360.5, y = 121, r = 33 },     -- target and focus
  { x = 135.5, y = 188.5, r = 27.5 }, -- small target
  -- party, pet, target of target; `bleed`: the next frame's ring in the picture, whose
  -- top edge peeks into the bottom of this frame's part of the picture
  { x = 24, y = 242, r = 21.5, small = true, bleed = { x = 23, y = 292, r = 21 } },
  { x = 24, y = 395, r = 21.5, small = true, bleed = { x = 23, y = 445, r = 21 } },
}
local RING_ROUND_TEXTURE = "Interface/AddOns/Portraits3D/Textures/RingHole" -- round hole (HOLE_DISC wide)

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
    -- the crossed swords shown on the portrait while in combat
    swords = { "PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.AttackIcon",
               "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.AttackIcon", "PlayerAttackIcon" },
    -- the floating damage / healing numbers shown over the portrait
    combat = { "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator",
               "PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.HitIndicator", "PlayerHitIndicator" },
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
    combat = { "PetFrame.HitIndicator", "PetHitIndicator" },
    dumpRoot = { "PetFrame" }, bgRoot = "PetFrame",
    -- the combat flash around the pet frame (round / plate shaped)
    rest = { "PetFrame.threatIndicator", "PetFrameFlash", "PetFrame.Flash", "PetAttackModeTexture", "PetFrame.PetAttackModeTexture" },
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
  local was = obj.portraits3dHush
  obj.portraits3dHush = on
  -- Only give the alpha back to pieces we hid ourselves; forcing 1 on everything
  -- (this runs every second) showed pieces the game had faded out.
  if on then obj:SetAlpha(0) elseif was then obj:SetAlpha(1) end
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
    -- newer game versions can also set the alpha from a true / false value
    if obj.SetAlphaFromBoolean then
      pcall(hooksecurefunc, obj, "SetAlphaFromBoolean", function(self)
        if self.portraits3dHush then self:SetAlpha(0) end
      end)
    end
  end
end

-- Finds the status / rest / glow pictures somewhere inside a unit frame, in
-- case they are not at the paths we guessed. Our own frames are skipped.
local GLOW_WORDS = { "status", "glow", "flash", "attackmode", "incombat" }
local function ScanGlows(root, skip, found, depth, maxDepth)
  if depth > (maxDepth or 5) then return end
  for _, region in ipairs({ root:GetRegions() }) do
    local atlas = region.GetAtlas and region:GetAtlas()
    local file = region.GetTexture and region:GetTexture()
    for _, name in ipairs({ type(atlas) == "string" and atlas or false, type(file) == "string" and file or false,
        region.GetName and region:GetName() or false }) do
      if name then
        local lower = name:lower()
        for _, word in ipairs(GLOW_WORDS) do
          if lower:find(word, 1, true) then found[#found + 1] = region break end
        end
      end
    end
  end
  for _, child in ipairs({ root:GetChildren() }) do
    if child ~= skip then ScanGlows(child, skip, found, depth + 1, maxDepth) end
  end
end

-- The portrait background: black, a gradient that starts black at the bottom and
-- fades to transparent at the top, the same in the unit's class color, or none.
-- The background fills its frame; a gradient only reaches up the "Gradient height"
-- fraction of it from the bottom.
local function AnchorBackground(entry)
  local bg = entry.bg
  if not bg or not entry.holder then return end
  local target = DB.square and entry.clip or entry.holder
  local mode = DB.background or "black"
  local extent = (mode == "gradient" or mode == "class") and (DB.gradient or 1) or 1
  bg:ClearAllPoints()
  if extent >= 0.999 then
    bg:SetAllPoints(target)
    return
  end
  bg:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT")
  bg:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT")
  bg:SetHeight(math.max(1, (target:GetHeight() or 0) * extent))
end

local function ApplyBackground(entry)
  local bg = entry.bg
  if not bg then return end
  AnchorBackground(entry)
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
  local bottomAlpha = fade and (DB.gradientAlpha or 1) or 1 -- the gradient's opacity setting
  bg:SetColorTexture(1, 1, 1, 1)
  local ok = CreateColor and pcall(bg.SetGradient, bg, "VERTICAL",
    CreateColor(r, g, b, bottomAlpha), CreateColor(r, g, b, topAlpha))
  if not ok then
    -- older gradient call; if that fails too, a flat color
    if not pcall(bg.SetGradientAlpha, bg, "VERTICAL", r, g, b, bottomAlpha, r, g, b, topAlpha) then
      bg:SetColorTexture(r, g, b, bottomAlpha)
    end
  end
end

local Cover2D, ScanLevel -- defined further down

-- Warns once if one of our texture files cannot be loaded (missing or misnamed).
local missingWarned = false
local function CheckLoaded(ok, file)
  if ok == false and not missingWarned then
    missingWarned = true
    print("|cff66ccffPortraits3D|r could not load " .. file:match("[^/]+$") .. " (is it in the addon's Textures folder?)")
  end
end

local function Decorate(entry, active)
  local square = DB.square and active
  for _, path in ipairs(entry.level or {}) do
    local obj = Resolve(path)
    if type(obj) == "table" and obj.SetAlpha then Hush(obj, square) end
  end
  -- Glows are also masked away: the game pulses some of them with an animation,
  -- which changes their alpha without going through SetAlpha.
  local function HideGlow(obj)
    Hush(obj, square)
    if entry.holder and obj.GetObjectType and obj:GetObjectType() == "Texture" then Cover2D(entry, obj, square) end
  end
  for _, path in ipairs(entry.rest or {}) do
    local obj = Resolve(path)
    if type(obj) == "table" and obj.SetAlpha then HideGlow(obj) end
  end
  for _, path in ipairs(entry.zzz or {}) do
    local obj = Resolve(path)
    if type(obj) == "table" and obj.SetAlpha then Hush(obj, active and DB.showZzz == false) end
  end
  if entry.swords then
    -- Also look inside the frame for a piece named or drawn like a combat icon.
    if not entry.swordsScanned then
      entry.swordsScanned = true
      local parent = Resolve("PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual")
      if type(parent) == "table" then
        for key, value in pairs(parent) do
          if type(key) == "string" and type(value) == "table" and value.GetObjectType
              and value:GetObjectType() == "Texture" then
            local atlas = value.GetAtlas and value:GetAtlas()
            if key:lower():find("attack") or key:lower():find("combat")
                or (type(atlas) == "string" and atlas:lower():find("combat")) then
              entry.swordObjects = entry.swordObjects or {}
              entry.swordObjects[#entry.swordObjects + 1] = value
            end
          end
        end
      end
    end
    for _, obj in ipairs(entry.swordObjects or {}) do Hush(obj, DB.hideSwords == true) end
    for _, path in ipairs(entry.swords) do
      local obj = Resolve(path)
      if type(obj) == "table" and obj.SetAlpha then Hush(obj, DB.hideSwords == true) end
    end
  end
  for _, path in ipairs(entry.combat or {}) do
    local obj = Resolve(path)
    if type(obj) == "table" and obj.SetAlpha then Hush(obj, DB.hideCombatText == true) end
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
  local scanRoot = (entry.unit == "player" and PlayerFrame) or (entry.unit == "pet" and PetFrame) or nil
  if scanRoot then
    if not entry.scanned and entry.holder then
      entry.scanned, entry.scanFound = true, {}
      -- (pet frame: only its own pictures, not the heal / absorb bars inside it)
      pcall(ScanGlows, scanRoot, entry.holder, entry.scanFound, 0, entry.unit == "pet" and 0 or nil)
    end
    for _, obj in ipairs(entry.scanFound or {}) do HideGlow(obj) end
  end
  ApplyBackground(entry)
  if entry.glowTex then
    local combat = UnitAffectingCombat and UnitAffectingCombat(entry.unit)
    local resting = entry.unit == "player" and IsResting and IsResting()
    if square and DB.showGlow ~= false and (combat or resting) then
      if combat then entry.glowTex:SetVertexColor(1, 0.25, 0.2) else entry.glowTex:SetVertexColor(1, 0.82, 0.2) end
      entry.glowTex:Show()
      if not entry.border:GetScript("OnUpdate") then -- Decorate runs every second
        entry.border:SetScript("OnUpdate", function()
          entry.glowTex:SetAlpha(0.45 + 0.4 * math.sin(GetTime() * 3))
        end)
      end
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
function ScanLevel(root, found, seen, depth, skip)
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

-- Where Blizzard's ring is, from the part of the unit frame picture the frame shows:
-- its centre as an offset from the portrait's centre, and its outer radius (all in
-- the portrait's units). Nil when it cannot be worked out.
-- Puts a mask on Blizzard's frame picture, or takes it off; `flag` remembers which.
local function SetRingMask(entry, mask, flag, on)
  if not mask or not entry.ringTexObj then return end
  if on and not entry[flag] then
    pcall(entry.ringTexObj.AddMaskTexture, entry.ringTexObj, mask)
    entry[flag] = true
  elseif not on and entry[flag] then
    pcall(entry.ringTexObj.RemoveMaskTexture, entry.ringTexObj, mask)
    entry[flag] = false
  end
end

local function RingGeometry(entry)
  local tex = entry.ringTexObj
  if not (tex and tex.GetAtlas and C_Texture and C_Texture.GetAtlasInfo) then return end
  local atlas = tex:GetAtlas()
  local info = atlas and C_Texture.GetAtlasInfo(atlas)
  if not info or not info.leftTexCoord then return end
  local l, r = info.leftTexCoord * ATLAS_W, info.rightTexCoord * ATLAS_W
  local t, b = info.topTexCoord * ATLAS_H, info.bottomTexCoord * ATLAS_H
  local left, top, w, h = tex:GetLeft(), tex:GetTop(), tex:GetWidth(), tex:GetHeight()
  local pcx, pcy = entry.portrait:GetCenter()
  if not (left and top and w and h and w > 0 and pcx and r ~= l and b ~= t) then return end
  for _, ring in ipairs(RINGS) do
    if ring.x > math.min(l, r) and ring.x < math.max(l, r) and ring.y > math.min(t, b) and ring.y < math.max(t, b) then
      local sx, sy = w / (r - l), h / (b - t)
      local k = tex:GetEffectiveScale() / entry.portrait:GetEffectiveScale()
      local x, y = left + (ring.x - l) * sx, top - (ring.y - t) * sy
      local scale = math.abs(sx) * k
      local bleed
      if ring.bleed then
        local bx, by = left + (ring.bleed.x - l) * sx, top - (ring.bleed.y - t) * sy
        bleed = { dx = bx * k - pcx, dy = by * k - pcy, r = ring.bleed.r * scale }
      end
      return x * k - pcx, y * k - pcy, ring.r * scale, (ring.cut or ring.r - PLATE_KEEP) * scale, ring, bleed
    end
  end
end

local function Layout(entry)
  local holder, clip = entry.holder, entry.clip
  if not holder then return end
  local w, h = holder:GetWidth(), holder:GetHeight()
  if not w or w <= 0 then return end
  if DB.square then
    local blend = DB.squareStyle == "blend"
    -- The model fills the hole of the border picture exactly.
    local size = w * Opt(entry, "squareSize")
    local cx, cy = 0, 0
    local dx, dy, radius, cut, ring, bleed
    if blend then
      -- Exactly in the ring's place and as big as the ring; the size and position
      -- sliders are for the original square and are not used here.
      dx, dy, radius, cut, ring, bleed = RingGeometry(entry)
      if not radius or radius < w * 0.35 or radius > w * 0.8 then dx, dy, radius, cut, ring, bleed = 0, 0, w * 0.56, w * 0.56 - PLATE_KEEP, nil, nil end
      local fit = ring and ring.small and FIT_SMALL or FIT
      -- Its outer side starts on the ring's edge; the side by the bars is pulled back
      -- by the gap, then the whole square is moved away from the bars by the shift,
      -- and the shrink takes the rest off the side away from the bars.
      local away = entry.side == "right" and 1 or -1
      cx, cy = dx + away * (fit.gap / 2 + fit.shift - fit.shrink / 2), dy - fit.down
      size = 2 * (radius + 0.5) - fit.gap - fit.shrink
      if entry.hole then
        -- Sized so the straight side lands just before the plate's edge line; the
        -- round part then reaches a little past the ring's soft edge.
        local d = 2 * cut / FLAT_CUT
        entry.hole:SetSize(d, d)
        entry.hole:ClearAllPoints()
        entry.hole:SetPoint("CENTER", entry.portrait, "CENTER", dx, dy)
      end
      if entry.hole2 then
        -- a second round hole over the next frame's ring, which peeks in at the bottom
        if bleed then
          local d = 2 * (bleed.r + 1.5) / HOLE_DISC
          entry.hole2:SetSize(d, d)
          entry.hole2:ClearAllPoints()
          entry.hole2:SetPoint("CENTER", entry.portrait, "CENTER", bleed.dx, bleed.dy)
        end
        entry.wantHole2 = bleed and true or false
        SetRingMask(entry, entry.hole2, "hole2On", entry.wantHole2)
      end
    end
    entry.border:SetSize(size, size)
    -- Shifted towards the bars (right for player and pet, left for target and
    -- focus) so it covers the part of the ring the mask leaves.
    local shift = blend and 0 or (entry.side == "right" and -1 or 1) * w * (PLAQUE_SHIFT + (Opt(entry, "frameX") or 0))
    entry.border:ClearAllPoints()
    entry.border:SetPoint("CENTER", entry.portrait, "CENTER", cx + shift, cy)
    clip:ClearAllPoints()
    clip:SetPoint("CENTER", entry.border, "CENTER")
    if entry.glowTex then entry.glowTex:SetSize(size / GLOW_RATIO, size / GLOW_RATIO) end
    if entry.cut and not blend then
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
      local x = dir * w * RING_KEEP
      if dir == 1 then
        entry.cut:SetPoint("TOPLEFT", entry.portrait, "CENTER", x, top)
      else
        entry.cut:SetPoint("TOPRIGHT", entry.portrait, "CENTER", x, top)
      end
    end
    local hole = blend and HOLE_BLEND or HOLE
    clip:SetSize(size * hole, size * hole)
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
  AnchorBackground(entry)
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
  AnchorBackground(entry)
  if DB.square then
    entry.bg:RemoveMaskTexture(entry.mask)
  else
    entry.bg:AddMaskTexture(entry.mask)
  end
  entry.border:SetShown(DB.square and entry.holder:IsShown())
  -- Square look: cut a hole in Blizzard's ring picture so the round ring is
  -- hidden instead of covered (the blended look removes only the ring itself).
  local blend = DB.squareStyle == "blend"
  local file = blend and FRAME_BLEND_TEXTURE or FRAME_TEXTURE
  CheckLoaded(entry.frameTex:SetTexture(file), file)
  SetRingMask(entry, entry.cut, "cutOn", DB.square and not blend)
  SetRingMask(entry, entry.hole, "holeOn", DB.square and blend)
  SetRingMask(entry, entry.hole2, "hole2On", DB.square and blend and entry.wantHole2)
  Decorate(entry, entry.holder:IsShown())
  Layout(entry)
end

local function ApplyCamera(entry)
  local model = entry.model
  -- Same order Immersion uses for its portrait models.
  -- Zoom 0-1 is the portrait zoom (1 = face); above 1 the camera also moves closer.
  local zoom = Opt(entry, "zoom") or 1
  pcall(model.SetCamDistanceScale, model, zoom > 1 and 1 / zoom or 1)
  pcall(model.SetPortraitZoom, model, math.min(zoom, 1))
  -- Turn: rotates the model about its vertical axis (degrees; 0 = the game's default).
  pcall(model.SetFacing, model, math.rad(Opt(entry, "turn") or 0))
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
  if entry.unit == "player" or entry.unit == "pet" then
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
      -- blended look: removes only the round ring (sized and placed by Layout)
      local hole = owner:CreateMaskTexture()
      local holeFile = RING_HOLE_TEXTURE .. (entry.side == "right" and "Mirror" or "")
      CheckLoaded(hole:SetTexture(holeFile, "CLAMP", "CLAMP"), holeFile)
      hole:SetPoint("CENTER", portrait, "CENTER")
      local hole2 = owner:CreateMaskTexture()
      CheckLoaded(hole2:SetTexture(RING_ROUND_TEXTURE, "CLAMP", "CLAMP"), RING_ROUND_TEXTURE)
      hole2:SetPoint("CENTER", portrait, "CENTER")
      entry.cut, entry.hole, entry.hole2, entry.ringTexObj = cut, hole, hole2, ringTex
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

-- Target of target can hold more than one flat portrait picture; collect every
-- texture inside it that is named like a portrait, so all of them can be hidden.
local function FlatPieces(entry)
  if entry.flatPieces then return entry.flatPieces end
  local list = { entry.portrait }
  if entry.unit == "targettarget" and entry.root then
    for _, name in ipairs({ "Portrait", "portrait" }) do
      local piece = Resolve(entry.root .. "." .. name)
      if type(piece) == "table" and piece.SetAlpha and piece ~= entry.portrait then list[#list + 1] = piece end
    end
    local root = Resolve(entry.root)
    local seen = {}
    local function walk(frame, depth)
      if type(frame) ~= "table" or seen[frame] or depth > 2 then return end
      seen[frame] = true
      for key, value in pairs(frame) do
        if type(key) == "string" and type(value) == "table" and value.GetObjectType
            and value.SetAlpha and value ~= entry.portrait and value:GetObjectType() == "Texture" then
          local lower = key:lower()
          if lower:find("portrait", 1, true) and not lower:find("mask", 1, true)
              and not lower:find("icon", 1, true) and not lower:find("corner", 1, true) then
            local known = false
            for _, have in ipairs(list) do if have == value then known = true end end
            if not known then list[#list + 1] = value end
          end
        end
      end
      if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
          if child ~= entry.holder then walk(child, depth + 1) end
        end
      end
    end
    walk(root, 0)
  end
  -- The round black backdrop behind a flat portrait is a plain colour picture in the
  -- frame itself; it showed through a transparent gradient as a dark circle.
  local bgPath = entry.bgRoot or ((entry.unit == "targettarget" or entry.unit:match("^party")) and entry.root)
  local bgRoot = bgPath and Resolve(bgPath)
  if type(bgRoot) == "table" and bgRoot.GetRegions then
    for _, region in ipairs({ bgRoot:GetRegions() }) do
      local atlas = region.GetAtlas and region:GetAtlas()
      local file = region.GetTexture and region:GetTexture()
      if region.SetAlpha and not atlas and type(file) == "number" and file <= 0 then
        local known = false
        for _, have in ipairs(list) do if have == region then known = true end end
        if not known then list[#list + 1] = region end
      end
    end
  end
  entry.flatPieces = list
  return list
end

-- Hiding by alpha is not always enough (target of target kept its flat portrait):
-- an empty mask on the picture hides it whatever the game does with its alpha.
function Cover2D(entry, piece, on)
  if not piece.AddMaskTexture then return end
  entry.covers = entry.covers or {}
  local mask = entry.covers[piece]
  if not mask then
    if not on then return end
    mask = entry.holder:CreateMaskTexture()
    mask:SetAllPoints(piece)
    mask:SetTexture("Interface/AddOns/Portraits3D/Textures/Blank", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    entry.covers[piece] = mask
  end
  if on and not mask.p3dOn then
    mask.p3dOn = true
    piece:AddMaskTexture(mask)
  elseif not on and mask.p3dOn then
    mask.p3dOn = false
    piece:RemoveMaskTexture(mask)
  end
end

local function Show2D(entry)
  entry.state = nil
  entry.holder:Hide()
  entry.border:Hide()
  Decorate(entry, false)
  for _, piece in ipairs(FlatPieces(entry)) do Hush(piece, false); Cover2D(entry, piece, false) end
end

local testParty = false -- /p3d testparty: party frames show the player's model

-- Dead, ghost and offline units are shown grey and dimmed, like the game's own
-- portraits.
local function ApplyLook(entry, unit)
  local grey = false
  if DB.greyDead ~= false then
    local ok, dead = pcall(UnitIsDeadOrGhost, unit)
    grey = ok and dead == true
  end
  if entry.greyed == grey then return end
  entry.greyed = grey
  pcall(entry.model.SetDesaturation, entry.model, grey and 1 or 0)
  pcall(entry.model.SetAlpha, entry.model, grey and 0.75 or 1)
end

local function Refresh(entry, force)
  if not Setup(entry) then return end
  local unit = entry.unit
  if testParty and unit:match("^party") then unit = "player" end
  local wanted = DB.enabled and DB.frames[GroupOf(entry)] ~= false
  -- A disconnected unit has no 3D model; its flat portrait is shown grey instead,
  -- and given its colour back once the unit is online again (or the option is off).
  local offline = wanted and DB.greyDead ~= false and UnitExists(unit) and not UnitIsConnected(unit)
  if offline and not entry.flatGreyed then
    entry.flatGreyed = true
    pcall(entry.portrait.SetDesaturated, entry.portrait, true)
  elseif not offline and entry.flatGreyed then
    entry.flatGreyed = nil
    pcall(entry.portrait.SetDesaturated, entry.portrait, false)
  end
  if not wanted or not UnitExists(unit) or not UnitIsConnected(unit) or not UnitIsVisible(unit) then
    Show2D(entry)
    return
  end
  Decorate(entry, true)
  ApplyLook(entry, unit)
  for _, piece in ipairs(FlatPieces(entry)) do
    if (piece:GetAlpha() or 0) > 0 then Hush(piece, true) end
  end
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
  entry.greyed = nil -- a new model starts in colour
  ApplyLook(entry, unit)
  -- The model loads a moment later and can reset the camera; apply again.
  C_Timer.After(0.2, function()
    -- skip if the frame has moved on to another unit since
    if entry.holder:IsShown() and entry.state == state then
      ApplyCamera(entry)
      entry.greyed = nil
      ApplyLook(entry, unit)
    end
  end)
  -- Blizzard redraws the flat portrait (and its alpha) whenever the unit changes,
  -- which showed it behind the model on target of target; keep it hidden.
  for _, piece in ipairs(FlatPieces(entry)) do Hush(piece, true); Cover2D(entry, piece, true) end
end

-- ===== Elite / rare / boss border =====
-- In the square look Blizzard's border sits behind the model, so a copy is drawn
-- above our frame (below the bars and indicators, which stay on top) and
-- Blizzard's own is kept invisible. Offsets are fractions of the border's own
-- width / height.
local DECO_STYLE = {
  normal = { x = 0.00, y = 0.02, size = 0.99 },
  boss = { x = 0.11, y = -0.04, size = 0.99 },
}
local function DecoKind(atlas)
  return (atlas and tostring(atlas):find("Winged")) and "boss" or "normal"
end

local function DecoEntry()
  for _, entry in ipairs(ENTRIES) do
    if entry.unit == "target" then return entry end
  end
end

-- Elite border mover (not saved until "Save"): forces the game's elite /
-- rare / boss border on the target frame so it can be lined up by hand.
local TEST = { deco = "off", decoX = 0.00, decoY = 0.02, decoSize = 0.99 }
local TEST_ATLAS = {
  elite = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold",
  rare = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver",
  boss = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged",
}
local testForced = false

local function UpdateDeco()
  local entry = DecoEntry()
  if not entry or not entry.holder then return end
  local deco = Resolve("TargetFrame.TargetFrameContainer.BossPortraitFrameTexture")
  if type(deco) ~= "table" or not deco.SetAtlas then return end
  local testing = TEST.deco ~= "off"
  if testing then
    Hush(deco, false)
    pcall(deco.SetAtlas, deco, TEST_ATLAS[TEST.deco], true)
    deco:SetAlpha(1)
    deco:Show()
    testForced = true
  elseif testForced then
    testForced = false
    deco:Hide()
    -- let the game put back the real border if the target is elite / rare
    if TargetFrame and TargetFrame.CheckClassification then
      pcall(TargetFrame.CheckClassification, TargetFrame)
    elseif TargetFrame_CheckClassification then
      pcall(TargetFrame_CheckClassification, TargetFrame)
    end
  end
  local ov = entry.decoOverlay
  local atlas = deco.GetAtlas and deco:GetAtlas()
  local live = DB.square and DB.enabled and entry.border and entry.holder:IsShown()
    and atlas and deco:IsShown()
  if not live then
    if ov then ov:Hide() end
    return
  end
  -- Measure the game's border at the picture's own size, as it was when the offsets
  -- below were worked out; the game can resize it for other frame sizes.
  pcall(deco.SetAtlas, deco, atlas, true)
  local dw, dh = deco:GetSize()
  local dx, dy = 0, 0
  local dcx, dcy = deco:GetCenter()
  local pcx, pcy = entry.portrait:GetCenter()
  if dcx and pcx then dx, dy = dcx - pcx, dcy - pcy end
  local blend = DB.squareStyle == "blend"
  local sq = blend and 1 or Opt(entry, "squareSize")
  local kind = DecoKind(atlas)
  local style = testing and { x = TEST.decoX, y = TEST.decoY, size = TEST.decoSize }
    or (blend and { x = 0, y = 0, size = 1 })
    or (DB.decoStyle and DB.decoStyle[kind]) or DECO_STYLE[kind]
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
  local shift = blend and 0 or (entry.side == "right" and -1 or 1) * entry.holder:GetWidth() * (Opt(entry, "frameX") or 0)
  ov.tex:SetPoint("CENTER", entry.portrait, "CENTER", dx * sq + style.x * dw + shift, dy * sq + style.y * dh)
  ov:Show()
  Hush(deco, true)
  entry.decoInfo = string.format("%s style x=%.2f y=%.2f size=%.2f | atlas=%s size=%.0fx%.0f offset=%.1f,%.1f square=%.2f framePos=%.2f scales deco=%.2f portrait=%.2f holder=%.2f",
    kind, style.x, style.y, style.size, tostring(atlas), dw, dh, dx, dy, sq, Opt(entry, "frameX") or 0,
    deco:GetEffectiveScale() or 0, entry.portrait:GetEffectiveScale() or 0, entry.holder:GetEffectiveScale() or 0)
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
    if key == "gradientAlpha" then ApplyBackground(entry) end
    if entry.model and entry.holder:IsShown() then ApplyCamera(entry) end
  end
end

-- "classic" (our own square, shifted towards the bars) or "blend" (in the ring's place)
local function SetSquareStyle(style)
  DB.squareStyle = style
  for _, entry in ipairs(ENTRIES) do ApplyStyle(entry) end
  RefreshAll(true)
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
  { key = "clear", label = "Transparent" },
  { key = "class", label = "Class gradient" },
  { key = "gradient", label = "Gradient" },
}

local ANIMATIONS = {
  { key = "full", label = "All idles" },
  { key = "basic", label = "Basic idle only" },
  { key = "still", label = "No animation" },
}

-- Window for lining up the elite / rare / boss border by hand.
local borderTest
local function ToggleBorderTest()
  if borderTest then
    borderTest:SetShown(not borderTest:IsShown())
    return
  end
  local ok, f = pcall(CreateFrame, "Frame", "Portraits3DBorderTest", UIParent, "BackdropTemplate")
  if not ok then f = CreateFrame("Frame", "Portraits3DBorderTest", UIParent) end
  borderTest = f
  f:SetSize(330, 360)
  f:SetPoint("CENTER", UIParent, "CENTER", -120, 120)
  f:SetFrameStrata("DIALOG")
  f:SetFrameLevel(60)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
      edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
  end
  tinsert(UISpecialFrames, "Portraits3DBorderTest")
  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 22, -18)
  title:SetText("Elite border mover")
  CreateFrame("Button", nil, f, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -6, -6)

  local refreshers = {}
  local modes = { { "off", "None" }, { "elite", "Elite" }, { "rare", "Rare" }, { "boss", "Boss" } }
  for i, mode in ipairs(modes) do
    local box = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    box:SetSize(24, 24)
    box:SetPoint("TOPLEFT", 16 + (i - 1) * 80, -48)
    local text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", box, "RIGHT", 0, 0)
    text:SetText(mode[2])
    box:SetScript("OnClick", function()
      TEST.deco = mode[1]
      local kind = mode[1] == "boss" and "boss" or "normal"
      local style = (DB.decoStyle and DB.decoStyle[kind]) or DECO_STYLE[kind]
      TEST.decoX, TEST.decoY, TEST.decoSize = style.x, style.y, style.size
      UpdateDeco()
      for _, r in ipairs(refreshers) do r() end
    end)
    refreshers[#refreshers + 1] = function() box:SetChecked(TEST.deco == mode[1]) end
  end

  local function AddTestSlider(key, label, lo, hi, y)
    local text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 24, y)
    text:SetText(label)
    local value = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    value:SetPoint("TOPLEFT", 24, y)
    value:SetWidth(282)
    value:SetJustifyH("RIGHT")
    local slider = CreateFrame("Slider", nil, f, "OptionsSliderTemplate")
    slider:SetSize(282, 16)
    slider:SetPoint("TOPLEFT", 24, y - 18)
    slider:SetMinMaxValues(lo, hi)
    slider:SetValueStep(0.01)
    slider:SetObeyStepOnDrag(true)
    pcall(function() slider.Low:SetText(""); slider.High:SetText(""); slider.Text:Hide() end)
    slider:SetScript("OnValueChanged", function(self, v)
      v = math.floor(v / 0.01 + 0.5) * 0.01
      value:SetText(string.format("%.2f", v))
      if self.syncing or math.abs(TEST[key] - v) < 1e-6 then return end
      TEST[key] = v
      UpdateDeco()
    end)
    refreshers[#refreshers + 1] = function()
      slider.syncing = true
      slider:SetValue(TEST[key])
      slider.syncing = false
      value:SetText(string.format("%.2f", TEST[key]))
    end
  end
  AddTestSlider("decoX", "Left / right", -0.5, 0.5, -90)
  AddTestSlider("decoY", "Up / down", -0.5, 0.5, -136)
  AddTestSlider("decoSize", "Size", 0.5, 1.5, -182)

  local save = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  save:SetSize(100, 24)
  save:SetPoint("TOPLEFT", 24, -236)
  save:SetText("Save")
  save:SetScript("OnClick", function()
    if TEST.deco == "off" then
      print("|cff66ccffPortraits3D|r pick Elite, Rare or Boss first")
      return
    end
    local kind = TEST.deco == "boss" and "boss" or "normal"
    DB.decoStyle = DB.decoStyle or {}
    DB.decoStyle[kind] = { x = TEST.decoX, y = TEST.decoY, size = TEST.decoSize }
    print(string.format("|cff66ccffPortraits3D|r saved for %s borders: x=%.2f y=%.2f size=%.2f (also tell Claude these numbers)",
      kind, TEST.decoX, TEST.decoY, TEST.decoSize))
  end)
  local note = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  note:SetPoint("TOPLEFT", 24, -272)
  note:SetWidth(282)
  note:SetJustifyH("LEFT")
  note:SetTextColor(0.75, 0.75, 0.75)
  note:SetText("Moves the elite, rare and boss border on your target frame. Needs the rounded square frame. Pick a border type, move it, then Save. Elite and Rare share one setting, Boss has its own. None turns the preview off.")
  f:SetScript("OnShow", function() for _, r in ipairs(refreshers) do r() end end)
  for _, r in ipairs(refreshers) do r() end
end

local COLUMN = 322 -- distance between the two columns of the window
local SetMinimapHidden = function() end -- replaced below, once the minimap button exists

-- Which set of size / camera / position settings the window edits.
local SIZE_GROUPS = {
  { key = "player", label = "Player", prefix = "", covers = "Player" },
  { key = "target", label = "Target", prefix = "target", covers = "Target, target of target and focus" },
  { key = "party", label = "Party", prefix = "party", covers = "Party members 1-4" },
  { key = "pet", label = "Pet", prefix = "pet", covers = "Pet" },
}

local function BuildWindow()
  local ok, f = pcall(CreateFrame, "Frame", "Portraits3DOptions", UIParent, "BackdropTemplate")
  if not ok then f = CreateFrame("Frame", "Portraits3DOptions", UIParent) end
  f:SetSize(660, 632)
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
  title:SetText("Portraits 3D: Forever Frames")
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
  local function AddCheck(label, x, y, get, set, showIf, tip)
    local box = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    box:SetSize(24, 24)
    box:SetPoint("TOPLEFT", x + colX, y)
    local text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", box, "RIGHT", 2, 0)
    text:SetText(label)
    box:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    if tip then
      -- the hover area covers the label too
      box:SetHitRectInsets(0, -((text:GetStringWidth() or 100) + 6), 0, 0)
      box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label)
        GameTooltip:AddLine(tip, 1, 1, 1, true)
        GameTooltip:Show()
      end)
      box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
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
    local fmt = step >= 1 and "%d°" or "%.2f" -- whole numbers are degrees
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
      value:SetText(string.format(fmt, v))
      if self.syncing or math.abs((DB[Key()] or 0) - v) < 1e-6 then return end
      SetNumber(Key(), v)
    end)
    controls[#controls + 1] = function()
      slider.syncing = true
      slider:SetValue(DB[Key()] or 0)
      slider.syncing = false
      value:SetText(string.format(fmt, DB[Key()] or 0))
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
  local function IsClassicSquare() return DB.square and DB.squareStyle ~= "blend" end

  -- Two check boxes per row, for a list of { key, label } choices.
  local function AddChoices(list, top, current, apply)
    for i, item in ipairs(list) do
      AddCheck(item.label, i % 2 == 1 and 28 or 178, top - math.floor((i - 1) / 2) * 22,
        function() return current() == item.key end,
        function() apply(item.key); f.refresh() end)
    end
  end

  -- ===== Left column =====
  AddSection("GENERAL", -44, 76)
  AddCheck("Rounded square frame", 28, -70, function() return DB.square end,
    function(on) SetSquare(on); f.refresh() end, nil,
    "Hides the edges and clipping that show when a 3D model is used in the normal round frames.")
  AddCheck("Minimap button", 28, -92, function() return not DB.hideMinimap end,
    function(on) SetMinimapHidden(not on) end)
  AddCheck("Blended look", 178, -92, function() return DB.squareStyle == "blend" end,
    function(on) SetSquareStyle(on and "blend" or "classic"); f.refresh() end, IsSquare,
    "Draws the square in place of Blizzard's ring, at the ring's size and shaded like it, so the name plate and bars run into it like they do into the ring. Turn off for the original square.")

  AddSection("FRAMES", -126, 98)
  FrameCheck("player", 28, -152)
  FrameCheck("target", 178, -152)
  FrameCheck("targettarget", 28, -174)
  FrameCheck("focus", 178, -174)
  FrameCheck("party", 28, -196)
  FrameCheck("pet", 178, -196)

  AddSection("ICONS & EFFECTS", -230, 120)
  AddCheck("Level badge", 28, -256, function() return DB.showBadge ~= false end,
    function(on) DB.showBadge = on; RefreshAll(true) end)
  AddCheck("Resting / combat glow", 140, -256, function() return DB.showGlow ~= false end,
    function(on) DB.showGlow = on; RefreshAll(true) end)
  AddCheck("Grey when dead / DC'd", 140, -278, function() return DB.greyDead ~= false end,
    function(on) DB.greyDead = on; RefreshAll(true) end)
  AddCheck("Resting Zzz", 28, -278, function() return DB.showZzz ~= false end,
    function(on) DB.showZzz = on; RefreshAll(true) end)

  AddCheck("Hide combat indicator", 28, -322, function() return DB.hideSwords == true end,
    function(on) DB.hideSwords = on; RefreshAll(true) end, nil,
    "Hides the crossed swords that show on your portrait during combat.")
  AddCheck("Hide combat text", 28, -300, function() return DB.hideCombatText == true end,
    function(on) DB.hideCombatText = on; RefreshAll(true) end)

  AddSection("BACKGROUND", -356, 168)
  AddChoices(BACKGROUNDS, -382, function() return DB.background or "black" end, SetBackground)
  local function IsGradient()
    local mode = DB.background or "black"
    return mode == "gradient" or mode == "class"
  end
  AddSlider("gradient", "Gradient height", 0.1, 1, -430, 0.05, IsGradient)
  AddSlider("gradientAlpha", "Gradient opacity", 0.1, 1, -476, 0.05, IsGradient)

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
  
  AddSection("SIZE & POSITION", -44, 462)
  AddCheck("Same for all frames", 28, -70, function() return DB.universal end,
    function(on)
      DB.universal = on
      for _, entry in ipairs(ENTRIES) do
        Layout(entry)
        if entry.model and entry.holder:IsShown() then ApplyCamera(entry) end
      end
      f.refresh()
    end)
  -- Tabs choose which frames the sliders below edit.
  local tabs = {}
  for i, group in ipairs(SIZE_GROUPS) do
    local tab = CreateFrame("Button", nil, f)
    tab:SetSize(66, 24)
    tab:SetPoint("TOPLEFT", 28 + colX + (i - 1) * 68, -98)
    local back = tab:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    local line = tab:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(2)
    local label = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("CENTER")
    label:SetText(group.label)
    tab:SetScript("OnClick", function() selected = group.key; f.refresh() end)
    tab:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(group.covers)
      GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tabs[i] = { tab = tab, back = back, line = line, label = label, key = group.key }
  end
  local covers = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  covers:SetPoint("TOPLEFT", 30 + colX, -126)
  covers:SetTextColor(0.75, 0.75, 0.75)
  controls[#controls + 1] = function()
    for _, t in ipairs(tabs) do
      local on = t.key == selected
      t.tab:SetShown(not DB.universal)
      t.back:SetColorTexture(1, 1, 1, on and 0.16 or 0.05)
      t.line:SetColorTexture(1, 0.82, 0, on and 0.9 or 0)
      t.label:SetTextColor(on and 1 or 0.7, on and 0.82 or 0.7, on and 0 or 0.7)
    end
    local text = "Every frame"
    if not DB.universal then
      for _, group in ipairs(SIZE_GROUPS) do
        if group.key == selected then text = "Editing: " .. group.covers end
      end
    end
    covers:SetText(text)
  end
  -- A small heading with a thin line, to group the sliders.
  local function AddHeading(label, y)
    local text = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", 30 + colX, y)
    text:SetText(label)
    text:SetTextColor(1, 0.82, 0, 0.9)
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.14)
    line:SetPoint("TOPLEFT", 30 + colX, y - 14)
    line:SetSize(262, 1)
  end

  AddHeading("FRAME", -152)
  AddSlider(function() return K("scale") end, "Model size", 0.5, 1.2, -172, 0.05, IsRound)
  AddSlider(function() return K("squareSize") end, "Frame size", 0.8, 1.25, -172, 0.05, IsClassicSquare)
  AddSlider(function() return K("frameX") end, "Frame position", -0.5, 0.5, -218, 0.01, IsClassicSquare)
  local blendNote = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  blendNote:SetPoint("TOPLEFT", 30 + colX, -176)
  blendNote:SetWidth(262)
  blendNote:SetJustifyH("LEFT")
  blendNote:SetTextColor(0.75, 0.75, 0.75)
  blendNote:SetText("The blended look sits exactly where Blizzard's ring is, at its size, so it has no size or position settings.")
  controls[#controls + 1] = function() blendNote:SetShown(DB.square and DB.squareStyle == "blend") end
  AddHeading("CAMERA", -268)
  AddSlider(function() return K("zoom") end, "Zoom", 0, 2, -288, 0.05)
  AddSlider(function() return K("turn") end, "Turn", -90, 90, -334, 5)
  AddHeading("MODEL POSITION", -384)
  AddSlider(function() return K("offX") end, "Left / right", -0.5, 0.5, -404, 0.01)
  AddSlider(function() return K("offY") end, "Up / down", -0.5, 0.5, -450, 0.01)

  AddSection("ANIMATION", -512, 76)
  AddChoices(ANIMATIONS, -538, function() return DB.anim end, SetAnimationMode)

  local borderBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  borderBtn:SetSize(150, 22)
  borderBtn:SetPoint("BOTTOMLEFT", 24, 14)
  borderBtn:SetText("Elite border mover")
  borderBtn:SetScript("OnClick", ToggleBorderTest)

  local reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  reset:SetSize(140, 22)
  reset:SetPoint("BOTTOMRIGHT", -24, 14)
  reset:SetText("Reset all settings")
  local function DoReset()
    DB.frames = {}
    DB.anim = DEFAULTS.anim
    DB.universal = DEFAULTS.universal
    SetBackground(DEFAULTS.background)
    DB.showBadge, DB.showGlow = DEFAULTS.showBadge, DEFAULTS.showGlow
    DB.showZzz, DB.greyDead, DB.hideCombatText, DB.hideSwords = DEFAULTS.showZzz, DEFAULTS.greyDead, DEFAULTS.hideCombatText, DEFAULTS.hideSwords
    SetNumber("gradient", DEFAULTS.gradient)
    SetNumber("gradientAlpha", DEFAULTS.gradientAlpha)
    SetMinimapHidden(DEFAULTS.hideMinimap)
    DB.squareStyle = DEFAULTS.squareStyle
    SetSquare(DEFAULTS.square)
    for _, prefix in ipairs({ "", "target", "party", "pet" }) do
      for _, name in ipairs({ "scale", "zoom", "squareSize", "offX", "offY", "turn", "frameX" }) do
        local key = prefix == "" and name or (prefix .. name:sub(1, 1):upper() .. name:sub(2))
        SetNumber(key, DEFAULTS[key])
      end
    end
    SetEnabled(DEFAULTS.enabled)
    f.refresh()
  end
  reset:SetScript("OnClick", function()
    if StaticPopupDialogs and StaticPopup_Show then
      StaticPopupDialogs["PORTRAITS3D_RESET"] = {
        text = "Reset every Portraits 3D setting to its default?",
        button1 = YES or "Yes", button2 = NO or "No",
        OnAccept = DoReset, timeout = 0, whileDead = true, hideOnEscape = true,
      }
      StaticPopup_Show("PORTRAITS3D_RESET")
    else
      DoReset()
    end
  end)
  reset:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Reset all settings")
    GameTooltip:AddLine("Puts every option on every tab back to its default.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  reset:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
  -- Same placement as other minimap buttons: on the rim, allowing for the minimap's
  -- and the button's own scale.
  local width = tonumber(Minimap:GetWidth()) or 140
  local mapScale = tonumber((Minimap:GetEffectiveScale())) or 1
  local buttonScale = tonumber((minimapButton:GetEffectiveScale())) or 1
  local radius = (width / 2) * (mapScale / buttonScale) + 6
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
  icon:SetTexture("Interface/Icons/Achievement_Character_Human_Female")
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
    GameTooltip:AddLine("Portraits 3D: Forever Frames")
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
  panel.name = "Portraits 3D: Forever Frames"

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
  title:SetPoint("TOP", 0, -80)
  title:SetText("Portraits 3D: Forever Frames")
  local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  sub:SetPoint("TOP", title, "BOTTOM", 0, -8)
  sub:SetText("3D unit frame portraits")

  local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  open:SetSize(260, 44)
  open:SetText("Open options")
  pcall(function() open:GetFontString():SetFontObject("GameFontNormalLarge") end)
  open:SetPoint("TOP", sub, "BOTTOM", 0, -60)
  local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  hint:SetPoint("TOP", open, "BOTTOM", 0, -8)
  hint:SetText("or type /p3d")
  open:SetScript("OnClick", ToggleWindow)

  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, "Portraits 3D: Forever Frames")
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
        local alpha = value.GetAlpha and value:GetAlpha()
        local visible = value.IsShown and value:IsShown()
        Say(string.format("%s.%s  %s%s%s", label, key, value:GetObjectType(), atlas and ("  atlas=" .. tostring(atlas)) or "",
          (alpha and visible) and string.format("  alpha=%.1f shown=%s", alpha, tostring(visible)) or ""))
        if value.GetChildren and value ~= entry.holder then walk(value, label .. "." .. key, depth + 1) end
      end
    end
  end
  for _, list in ipairs({ entry.ring or {}, entry.content or {}, entry.dumpRoot or {} }) do
    for _, path in ipairs(list) do
      local obj = Resolve(path)
      if type(obj) == "table" then
        walk(obj, path:match("[^%.]+$"), 0)
        -- unnamed pictures directly in the frame (named only by their file or atlas)
        if obj.GetRegions then
          for i, region in ipairs({ obj:GetRegions() }) do
            local atlas = region.GetAtlas and region:GetAtlas()
            local file = region.GetTexture and region:GetTexture()
            if atlas or file then
              lines = lines + 1
              Say(string.format("%s region %d  %s  %s  alpha=%.1f shown=%s", path:match("[^%.]+$"), i,
                atlas and ("atlas=" .. tostring(atlas)) or "", file and ("file=" .. tostring(file)) or "",
                region.GetAlpha and region:GetAlpha() or 0, tostring(region.IsShown and region:IsShown())))
            end
          end
        end
      end
    end
  end
  Say(lines .. " pieces listed")
end

local function Debug()
  for _, entry in ipairs(ENTRIES) do
    local portrait, path = FindPortrait(entry)
    if entry.cut then Say("   ring cut ready for " .. (entry.ringTex and entry.ringTex[1] or "?")) end
    if entry.portrait then
      local dx, dy, radius = RingGeometry(entry)
      Say(radius and string.format("   ring found: offset %.1f, %.1f  radius %.1f  (portrait %.1f wide)", dx, dy, radius, entry.portrait:GetWidth() or 0)
        or "   ring not found in the frame picture (blended look uses a guess)")
    end
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
  elseif cmd == "blend" then
    -- quick switch between the two square looks, for comparing them
    SetSquareStyle(DB.squareStyle == "blend" and "classic" or "blend")
    if not DB.square then SetSquare(true) end
    if win and win.refresh then win.refresh() end
    Say("square look: " .. (DB.squareStyle == "blend" and "blended" or "original"))
  elseif cmd == "minimap" then
    SetMinimapHidden(not DB.hideMinimap)
    Say("minimap button " .. (DB.hideMinimap and "hidden" or "shown"))
  elseif cmd == "dev" then
    -- developer tools, not needed in normal use
    local sub, rest = arg:match("^(%S*)%s*(.-)$")
    if sub == "testparty" then
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
      Say(testParty and ("party test ON: " .. shown .. " party frames shown with your model; /p3d dev testparty again to stop") or "party test off")
    elseif sub == "dump" then
      Dump(rest ~= "" and rest or "player")
    elseif sub == "debug" then
      Debug()
    elseif sub == "deco" then
      -- /p3d dev deco                      shows the numbers in use
      -- /p3d dev deco <normal|boss> x y size   changes them (saved); "reset" clears
      local kind, x, y, size = rest:match("^(%a+)%s+(-?[%d%.]+)%s+(-?[%d%.]+)%s+([%d%.]+)$")
      if kind and (kind == "normal" or kind == "boss") then
        DB.decoStyle = DB.decoStyle or {}
        DB.decoStyle[kind] = { x = tonumber(x), y = tonumber(y), size = tonumber(size) }
        UpdateDeco()
      elseif rest == "reset" then
        DB.decoStyle = nil
        UpdateDeco()
      end
      local entry = DecoEntry()
      Say(entry and entry.decoInfo or "no border drawn right now (target an elite, square frame on)")
    elseif sub == "bordertest" then
      ToggleBorderTest()
    elseif sub == "shown" then
      -- /p3d dev shown [unit]: every Blizzard picture that is drawn on or around the
      -- portrait right now (not ours), to find a glow that is not hidden
      local unit = rest ~= "" and rest or "player"
      local entry
      for _, e in ipairs(ENTRIES) do if e.unit == unit then entry = e end end
      local root = entry and Resolve((entry.root or (unit == "player" and "PlayerFrame") or (unit == "target" and "TargetFrame")
        or (unit == "focus" and "FocusFrame") or (unit == "pet" and "PetFrame")) or "")
      if not (entry and entry.portrait and type(root) == "table") then Say("no frame for " .. unit) return end
      local pcx, pcy = entry.portrait:GetCenter()
      local reach = entry.portrait:GetWidth() * 0.75
      local count, skipped, seen = 0, 0, {}
      local function name(region, path)
        return (region.GetName and region:GetName()) or path
      end
      local function walk(frame, path, depth)
        if depth > 6 or seen[frame] or frame == entry.holder then return end
        seen[frame] = true
        local keys = {}
        for k, v in pairs(frame) do if type(k) == "string" and type(v) == "table" then keys[v] = k end end
        -- Some numbers (the bars' size and place) are secret to addons in newer game
        -- versions and cannot be compared; such pictures are counted and skipped.
        local function check(i, region)
          local alpha = region.GetEffectiveAlpha and region:GetEffectiveAlpha() or (region.GetAlpha and region:GetAlpha()) or 0
          if region.GetObjectType and region:GetObjectType() == "Texture" and region:IsVisible() and alpha > 0.01 then
            local x, y = region:GetCenter()
            local w, h = region:GetWidth() or 0, region:GetHeight() or 0
            local k = (region:GetEffectiveScale() or 1) / (entry.portrait:GetEffectiveScale() or 1)
            if x and pcx and math.abs(x * k - pcx) < reach + w * k / 2 and math.abs(y * k - pcy) < reach + h * k / 2 then
              count = count + 1
              local atlas = region.GetAtlas and region:GetAtlas()
              local file = region.GetTexture and region:GetTexture()
              local masks = region.GetNumMaskTextures and region:GetNumMaskTextures() or 0
              Say(string.format("%s  %s  alpha=%.2f %.0fx%.0f at %.1f,%.1f blend=%s masks=%d layer=%s",
                name(region, path .. "." .. (keys[region] or ("#" .. i))),
                atlas and ("atlas=" .. atlas) or ("file=" .. tostring(file)), alpha, w, h, x * k - pcx, y * k - pcy,
                tostring(region.GetBlendMode and region:GetBlendMode()), masks,
                tostring(region.GetDrawLayer and region:GetDrawLayer())))
            end
          end
        end
        for i, region in ipairs({ frame:GetRegions() }) do
          if not pcall(check, i, region) then skipped = skipped + 1 end
        end
        for _, child in ipairs({ frame:GetChildren() }) do
          walk(child, path .. "." .. (keys[child] or "?"), depth + 1)
        end
      end
      walk(root, root.GetName and root:GetName() or unit, 0)
      Say(count .. " pictures shown around the portrait (" .. skipped .. " could not be read)")
    elseif sub == "ring" then
      -- /p3d dev ring [unit]: what the blended look measured for that frame's ring
      local unit = rest ~= "" and rest or "player"
      for _, entry in ipairs(ENTRIES) do
        if entry.unit == unit then
          local tex, p = entry.ringTexObj, entry.portrait
          if not (tex and p) then Say(unit .. ": no ring picture / portrait found") break end
          local atlas = tex.GetAtlas and tex:GetAtlas()
          local info = atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
          Say(string.format("%s atlas=%s file=%s", unit, tostring(atlas), tostring(info and (info.filename or info.file))))
          if info then
            Say(string.format("  texcoords L%.4f R%.4f T%.4f B%.4f  atlas size %sx%s",
              info.leftTexCoord or -1, info.rightTexCoord or -1, info.topTexCoord or -1, info.bottomTexCoord or -1,
              tostring(info.width), tostring(info.height)))
          end
          local pcx, pcy = p:GetCenter()
          Say(string.format("  frame picture L%.1f T%.1f %.1fx%.1f scale %.3f",
            tex:GetLeft() or -1, tex:GetTop() or -1, tex:GetWidth() or -1, tex:GetHeight() or -1, tex:GetEffectiveScale() or -1))
          Say(string.format("  portrait centre %.1f,%.1f %.1fx%.1f scale %.3f",
            pcx or -1, pcy or -1, p:GetWidth() or -1, p:GetHeight() or -1, p:GetEffectiveScale() or -1))
          local dx, dy, radius = RingGeometry(entry)
          Say(radius and string.format("  ring offset %.1f,%.1f radius %.1f", dx, dy, radius) or "  ring not matched (using a guess)")
          Say(string.format("  square %.1f  squareSize=%.2f frameX=%.2f", entry.border:GetWidth() or -1,
            Opt(entry, "squareSize") or -1, Opt(entry, "frameX") or 0))
        end
      end
    elseif sub == "tot" then
      for _, entry in ipairs(ENTRIES) do
        if entry.unit == "targettarget" and entry.portrait then
          for i, piece in ipairs(FlatPieces(entry)) do
            Say(string.format("flat piece %d: alpha=%.1f hushed=%s shown=%s", i, piece:GetAlpha(), tostring(piece.portraits3dHush), tostring(piece:IsShown())))
          end
          Say("model shown: " .. tostring(entry.holder and entry.holder:IsShown()) .. ", path: " .. tostring(entry.path))
        end
      end
    else
      Say("/p3d dev testparty | dump <unit> | debug | ring [unit] | shown [unit] | tot | deco")
    end
  elseif cmd == "" or cmd == "options" or cmd == "config" then
    ToggleWindow()
  else
    Say("/p3d opens the options. Also: /p3d on | off | minimap | blend")
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
    DB.borderColor = nil -- the frame colour options were removed
    DB.icon = nil -- the icon picker was removed
    for _, key in ipairs({ "squareSize", "targetSquareSize", "partySquareSize", "petSquareSize" }) do
      if type(DB[key]) == "number" and DB[key] > 1.25 then DB[key] = 1.25 end
    end
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
