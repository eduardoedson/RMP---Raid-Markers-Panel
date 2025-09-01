-- RaidMarkersPanel
-- Left click  : mark target (/tm N)
-- Right click : toggle ground marker (place if missing, clear if present)
-- Pull L=Start / R=Cancel, Ready Check, minimap button, UNLOCKED indicator

local ADDON = ...

-- ================== SAVED VARS / DEFAULTS ==================
local DEFAULTS = {
  iconSize = 36, padding = 6, perLine = 5, vertical = false, locked = false,
  point = "CENTER", x = 0, y = -150,
  pullSec = 10, onlyInGroup = false,

  -- look & feel
  bgAlpha = 0.60, panelBorderAlpha = 0.90,
  btnBgAlpha = 0.25, btnBorderAlpha = 0.60, btnInnerPad = 1,
  panelStrata = "LOW",

  -- minimap
  minimapEnabled = true, minimapPos = 225, minimapRadius = 80, minimapSize = 18,

  -- debug
  debug = false,
}

local function copyDefaults(dst, src) dst = dst or {}; for k,v in pairs(src) do if dst[k]==nil then dst[k]=v end end; return dst end

-- ================== LOCALS ==================
local DB, Panel, MinimapBtn, SettingsCategory
local Buttons = {}
local wipeTbl = table.wipe or function(t) for k in pairs(t) do t[k]=nil end end
local After = C_Timer and C_Timer.After or function(_, fn) fn() end

local function DBG(...) if not DB or not DB.debug then return end
  local t={}; for i=1,select("#",...) do t[#t+1]=tostring(select(i,...)) end
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00RMP-DEBUG:|r "..table.concat(t," ")) end
end

local function Msg(txt) UIErrorsFrame:AddMessage("|cff00ff00RMP:|r "..txt,1,1,0) end
local function IsLead() return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") or not IsInGroup() end

-- ================== UNLOCK INDICATOR ==================
local function UpdateLockIndicator()
  if not Panel then return end
  if not Panel.lockIcon then
    Panel.lockIcon = Panel:CreateTexture(nil, "OVERLAY"); Panel.lockIcon:SetSize(14,14)
    Panel.lockText = Panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  end
  local anchor = (Buttons and Buttons[1]) or Panel
  Panel.lockIcon:ClearAllPoints(); Panel.lockText:ClearAllPoints()
  Panel.lockIcon:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
  Panel.lockText:SetPoint("LEFT", Panel.lockIcon, "RIGHT", 4, 0)
  if DB.locked then
    Panel.lockIcon:Hide(); Panel.lockText:Hide()
  else
    Panel.lockIcon:SetTexture("Interface\\Buttons\\LockButton-Unlocked")
    Panel.lockText:SetText("|cffff8888UNLOCKED|r")
    Panel.lockIcon:Show(); Panel.lockText:Show()
  end
end

-- ================== SKIN ==================
local HOVER_PAD = 4
local function SkinButton(b)
  b:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1 })
  b:SetBackdropColor(0,0,0, DB.btnBgAlpha or 0.25)
  b:SetBackdropBorderColor(1,1,1, DB.btnBorderAlpha or 0.60)
  local pad = math.max(0, math.min(8, tonumber(DB.btnInnerPad) or 1))
  if b.icon then b.icon:ClearAllPoints(); b.icon:SetPoint("TOPLEFT", pad, -pad); b.icon:SetPoint("BOTTOMRIGHT", -pad, pad) end
  if not b.hl then b.hl=b:CreateTexture(nil,"HIGHLIGHT"); b.hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); b.hl:SetBlendMode("ADD") end
  b.hl:ClearAllPoints(); b.hl:SetPoint("TOPLEFT",-HOVER_PAD,HOVER_PAD); b.hl:SetPoint("BOTTOMRIGHT",HOVER_PAD,-HOVER_PAD)
end

local function MakeButton(parent, texture, tooltip)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(DB.iconSize, DB.iconSize)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetTexture(texture)
  b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:AddLine(tooltip,1,1,1,true); GameTooltip:Show() end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  SkinButton(b); return b
end

-- ================== ACTIONS ==================
local function StartPull(sec)
  sec = tonumber(sec) or (DB and DB.pullSec) or 10
  if not IsLead() then Msg("Leader/Assistant required.") return end
  if C_PartyInfo and C_PartyInfo.DoCountdown then
    C_PartyInfo.DoCountdown(sec)
  else
    RunMacroText("/pull "..sec)
  end
end

local function CancelPull()
  if C_PartyInfo and C_PartyInfo.CancelCountdown then pcall(C_PartyInfo.CancelCountdown) end
  if C_PartyInfo and C_PartyInfo.DoCountdown then pcall(C_PartyInfo.DoCountdown, 0) end
  RunMacroText("/pull 0")
  RunMacroText("/dbm pull 0"); RunMacroText("/dbm timer 0")
  RunMacroText("/bigwigs pull 0"); RunMacroText("/bigwigs cancel")
  RunMacroText("/bw pull 0"); RunMacroText("/bw cancel")
  DBG("Cancel requested")
end

local function DoReady()
  if not (IsInGroup() or IsInRaid()) then Msg("Not in a group.") return end
  if not IsLead() then Msg("Leader/Assistant required.") return end
  if C_PartyInfo and C_PartyInfo.DoReadyCheck then
    pcall(C_PartyInfo.DoReadyCheck)
    return
  end
  if DoReadyCheck then
    pcall(DoReadyCheck)
    return
  end
  RunMacroText("/readycheck")
end

-- ================== DATA ==================
local RAID_ICONS = {
  {1,"Interface\\TargetingFrame\\UI-RaidTargetingIcon_1","Star"},
  {2,"Interface\\TargetingFrame\\UI-RaidTargetingIcon_2","Circle"},
  {3,"Interface\\TargetingFrame\\UI-RaidTargetingIcon_3","Diamond"},
  {4,"Interface\\TargetingFrame\\UI-RaidTargetingIcon_4","Triangle"},
  {5,"Interface\\TargetingFrame\\UI-RaidTargetingIcon_5","Moon"},
  {6,"Interface\\TargetingFrame\\UI-RaidTargetingIcon_6","Square"},
  {7,"Interface\\TargetingFrame\\UI-RaidTargetingIcon_7","Cross"},
  {8,"Interface\\TargetingFrame\\UI-RaidTargetingIcon_8","Skull"},
}

-- raid icon -> world marker (1..8)
local WM_BY_RAIDICON = {
  [1]=5, -- Star    -> Yellow Star
  [2]=6, -- Circle  -> Orange Circle
  [3]=3, -- Diamond -> Purple Diamond
  [4]=2, -- Triangle-> Green Triangle
  [5]=7, -- Moon    -> White Moon
  [6]=1, -- Square  -> Blue Square
  [7]=4, -- Cross   -> Red Cross
  [8]=8, -- Skull   -> White Skull
}

-- Ground marker state (true/false or nil if API missing)
local function WMActive(i)
  if type(IsRaidMarkerActive) == "function" then
    local ok, v = pcall(IsRaidMarkerActive, i)
    if ok then return v end
  end
  return nil
end

-- ================== BUILD BUTTONS (SECURE + TOGGLE VIA PreClick) ==================
local function BuildButtons()
  wipeTbl(Buttons)

  -- LMB = /tm (target).  RMB = toggle ground/world marker via PreClick
  for _, info in ipairs(RAID_ICONS) do
    local idx, tex, name = info[1], info[2], info[3]

    local b = CreateFrame("Button", nil, Panel, "BackdropTemplate,SecureActionButtonTemplate")
    b:SetSize(DB.iconSize, DB.iconSize)
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetTexture(tex)
    SkinButton(b)
    b:RegisterForClicks("AnyDown")

    -- LEFT: target mark
    b:SetAttribute("type1", "macro")
    b:SetAttribute("macrotext1", "/tm "..idx)

    -- RIGHT: toggle ground marker (decided in PreClick)
    local wm = WM_BY_RAIDICON[idx]
    b:SetAttribute("type2", "macro")
    -- Intencionalmente sem macrotext2 inicial; o PreClick define conforme o estado.
    -- b:SetAttribute("macrotext2", "/wm "..wm)

    b:SetScript("PreClick", function(self, button)
      if button ~= "RightButton" then return end

      -- Agora só checa se está em grupo/raid
      if not (IsInGroup() or IsInRaid()) then
        self:SetAttribute("macrotext2",
          "/run UIErrorsFrame:AddMessage('|cffff5555RMP: not in a group.', 1, 0.3, 0.3)")
        return
      end

      -- toggle: if active -> clear; else -> place
      local active = WMActive(wm)
      if active == true then
        self:SetAttribute("macrotext2", "/cwm "..wm.."\n/clearworldmarker "..wm)
      else
        self:SetAttribute("macrotext2", "/wm "..wm.."\n/worldmarker "..wm)
      end
    end)


    -- tooltip (agora com placeholders)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(
        string.format("Left: Mark %s | Right: Toggle Ground %d", name, wm),
        1,1,1,true
      )
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    table.insert(Buttons, b)
  end

  -- Ready Check
  local bReady = MakeButton(Panel, "Interface\\RaidFrame\\ReadyCheck-Ready", "Ready Check")
  bReady:RegisterForClicks("AnyDown")
  bReady:SetScript("OnClick", DoReady)
  table.insert(Buttons, bReady)

  -- Pull (L start / R cancel)
  local bPull = MakeButton(Panel, "Interface\\Icons\\inv_misc_pocketwatch_01", "Left: Start Pull | Right: Cancel Pull")
  bPull:RegisterForClicks("AnyDown")
  bPull:SetScript("OnClick", function(_, btn) if btn=="RightButton" then CancelPull() else StartPull(DB.pullSec or 10) end end)
  table.insert(Buttons, bPull)

  UpdateLockIndicator()
end

-- ================== LAYOUT ==================
local function ApplySizes() for _,b in ipairs(Buttons) do b:SetSize(DB.iconSize, DB.iconSize); SkinButton(b) end end
local function DoLayout()
  local icon, pad, total = DB.iconSize, DB.padding, #Buttons
  local per = math.max(1, math.min(total, DB.perLine or total))
  local cols, rows
  if DB.vertical then rows=per; cols=math.ceil(total/rows) else cols=per; rows=math.ceil(total/cols) end
  Panel:SetSize((icon*cols)+(pad*(cols+1)), (icon*rows)+(pad*(rows+1)))
  for i,b in ipairs(Buttons) do
    local col,row
    if DB.vertical then row=(i-1)%rows; col=math.floor((i-1)/rows) else col=(i-1)%cols; row=math.floor((i-1)/cols) end
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", Panel, "TOPLEFT", pad + col*(icon+pad), -(pad + row*(icon+pad)))
  end
  UpdateLockIndicator()
end
local function Reanchor() Panel:ClearAllPoints(); Panel:SetPoint(DB.point or "CENTER", UIParent, DB.point or "CENTER", DB.x or 0, DB.y or -150) end

-- ================== MINIMAP ==================
local function Minimap_UpdatePosition() if not MinimapBtn then return end; local a=math.rad(DB.minimapPos or 225); local r=DB.minimapRadius or 80; MinimapBtn:ClearAllPoints(); MinimapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a)*r, math.sin(a)*r) end
local function Minimap_ApplySize() if MinimapBtn then MinimapBtn:SetSize(DB.minimapSize or 18, DB.minimapSize or 18) end end
local function Minimap_Create()
  if MinimapBtn then return end
  MinimapBtn = CreateFrame("Button", "RaidMarkersPanel_Minimap", Minimap); Minimap_ApplySize(); MinimapBtn:SetFrameStrata("MEDIUM")
  local icon=MinimapBtn:CreateTexture(nil,"ARTWORK"); icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"); icon:SetTexCoord(0.06,0.94,0.06,0.94); icon:SetAllPoints(MinimapBtn); MinimapBtn.icon=icon
  MinimapBtn:RegisterForClicks("AnyUp")
  MinimapBtn:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self,"ANCHOR_LEFT"); GameTooltip:AddLine("RaidMarkersPanel",1,1,1); GameTooltip:AddLine("Left-Click: Open addon options",0.9,0.9,0.9); GameTooltip:AddLine("Right-Click: Lock/Unlock panel",0.9,0.9,0.9); GameTooltip:Show() end)
  MinimapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  MinimapBtn:SetScript("OnClick", function(_, btn)
    if btn=="RightButton" then DB.locked=not DB.locked; Panel:EnableMouse(not DB.locked); UpdateLockIndicator(); return end
    if Settings and Settings.OpenToCategory and SettingsCategory then
      local id = SettingsCategory.ID or (SettingsCategory.GetID and SettingsCategory:GetID())
      if id then Settings.OpenToCategory(id) else Settings.OpenToCategory("AddOns") end
    else
      InterfaceOptionsFrame_OpenToCategory(_G["RaidMarkersPanel"]); InterfaceOptionsFrame_OpenToCategory(_G["RaidMarkersPanel"])
    end
  end)
  MinimapBtn:RegisterForDrag("LeftButton")
  MinimapBtn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx,my=GetCursorPosition(); local scale=UIParent:GetEffectiveScale()
      local cx,cy=Minimap:GetCenter(); local dx,dy=(mx/scale-cx),(my/scale-cy)
      DB.minimapPos=(math.deg(math.atan2(dy,dx))%360); Minimap_UpdatePosition()
    end)
  end)
  MinimapBtn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  Minimap_UpdatePosition()
end
local function Minimap_Apply() if not Minimap then return end; Minimap_Create(); Minimap_ApplySize(); if DB.minimapEnabled then MinimapBtn:Show() else MinimapBtn:Hide() end; Minimap_UpdatePosition() end

-- ================== REFRESH ==================
local function RefreshAll()
  Panel:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1 })
  Panel:SetBackdropColor(0,0,0, DB.bgAlpha or 0.6)
  Panel:SetBackdropBorderColor(0.2,0.2,0.2, DB.panelBorderAlpha or 0.9)

  for _, b in ipairs(Buttons) do SkinButton(b) end
  ApplySizes(); DoLayout(); Reanchor()

  Panel:EnableMouse(not (DB and DB.locked))

  if DB.onlyInGroup then
    if IsInGroup() or IsInRaid() then Panel:Show() else Panel:Hide() end
  else
    Panel:Show()
  end

  Minimap_Apply()
  UpdateLockIndicator()
end

-- ================== OPTIONS UI HELPERS ==================
local function Header(parent, text) local h=parent:CreateFontString(nil,"ARTWORK","GameFontHighlightLarge"); h:SetText(text); h:SetJustifyH("LEFT"); return h end
local function SubText(parent, text) local t=parent:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall"); t:SetText(text); t:SetJustifyH("LEFT"); t:SetTextColor(0.8,0.8,0.8); return t end
local function Box(parent, title, w, h) local box=CreateFrame("Frame", nil, parent, "BackdropTemplate"); box:SetSize(w or 560, h or 190); box:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1 }); box:SetBackdropColor(0,0,0,0); box:SetBackdropBorderColor(0,0,0,0); local lbl=box:CreateFontString(nil,"ARTWORK","GameFontNormal"); lbl:SetPoint("TOPLEFT",0,-2); lbl:SetText(title); return box end
local function MakeSlider(parent, title, minv, maxv, step, decimals, onChange)
  decimals = decimals or 0
  local function fmt(v) return (decimals==0) and tostring(math.floor(v+0.5)) or string.format("%."..decimals.."f", v) end
  local s=CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  s:SetWidth(220); s:SetHeight(16); s:SetMinMaxValues(minv,maxv); s:SetValueStep(step or 1); s:SetObeyStepOnDrag(true)
  s.Text:SetText(title); s.Low:SetText(tostring(minv)); s.High:SetText(tostring(maxv))
  s:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:AddLine(fmt(self:GetValue()),1,1,0); GameTooltip:Show() end)
  s:SetScript("OnLeave", function() GameTooltip:Hide() end)
  s:SetScript("OnValueChanged", function(self,v) if onChange then onChange(v) end; if GameTooltip:IsOwned(self) then GameTooltip:ClearLines(); GameTooltip:AddLine(fmt(v),1,1,0); GameTooltip:Show() end end)
  function s:ForceInit(v) After(0, function() self:SetValue(v); if onChange then onChange(v) end end) end
  return s
end
local function MakeCheckbox(parent, text) local cb=CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate"); local l=parent:CreateFontString(nil,"ARTWORK","GameFontNormal"); l:SetText(text); l:SetPoint("LEFT", cb, "RIGHT", 6, 0); cb.label=l; return cb end
local function CreateScrollArea(parent) local scroll=CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT",0,-8); scroll:SetPoint("BOTTOMRIGHT",-28,8); local content=CreateFrame("Frame", nil, scroll); content:SetSize(600,10); scroll:SetScrollChild(content); local function upd() local w=math.max(300,(parent:GetWidth() or 600)-28); content:SetWidth(w) end; parent:HookScript("OnSizeChanged", upd); upd(); return content end

-- PANELS
local PanelMain=CreateFrame("Frame"); PanelMain.name="RaidMarkersPanel"
local PanelLayout=CreateFrame("Frame"); PanelLayout.name="Layout"; PanelLayout.parent=PanelMain.name
local PanelBehavior=CreateFrame("Frame"); PanelBehavior.name="Behavior"; PanelBehavior.parent=PanelMain.name

local function BuildMainPanel() if PanelMain._built then return end; PanelMain._built=true; local c=CreateScrollArea(PanelMain); local h=Header(c,"RaidMarkersPanel"); h:SetPoint("TOPLEFT",16,-16); local sub=SubText(c,"Open Layout or Behavior on the left. Changes apply instantly."); sub:SetPoint("TOPLEFT",h,"BOTTOMLEFT",0,-10); c:SetHeight(120) end

local function BuildLayoutPanel()
  if PanelLayout._built then return end; PanelLayout._built=true
  local c=CreateScrollArea(PanelLayout); local y=-16
  local h=Header(c,"Layout"); h:SetPoint("TOPLEFT",16,y); y=y-28
  local tip=SubText(c,"Adjust size, orientation, spacing, grid, and look."); tip:SetPoint("TOPLEFT",16,y); y=y-24
  local box1H=220; local box1=Box(c,"Dimensions",560,box1H); box1:SetPoint("TOPLEFT",16,y); y=y-(box1H+16)
  local sSize=MakeSlider(box1,"Button size (px)",20,80,1,0,function(v) DB.iconSize=v; RefreshAll() end); sSize:SetPoint("TOPLEFT",16,-48)
  local sPad=MakeSlider(box1,"Spacing (px)",0,20,1,0,function(v) DB.padding=v; RefreshAll() end); sPad:SetPoint("LEFT", sSize, "RIGHT", 30, 0)
  local sAlpha=MakeSlider(box1,"Panel background opacity",0,1,0.05,2,function(v) DB.bgAlpha=v; RefreshAll() end); sAlpha:SetPoint("TOPLEFT", sSize, "BOTTOMLEFT", 0, -54)
  local sBorder=MakeSlider(box1,"Panel border opacity",0,1,0.05,2,function(v) DB.panelBorderAlpha=v; RefreshAll() end); sBorder:SetPoint("LEFT", sAlpha, "RIGHT", 30, 0)
  local sBtnPad=MakeSlider(box1,"Icon padding (px)",0,8,1,0,function(v) DB.btnInnerPad=v; RefreshAll() end); sBtnPad:SetPoint("TOPLEFT", sAlpha, "BOTTOMLEFT", 0, -54)

  local box2H=110; local box2=Box(c,"Grid",560,box2H); box2:SetPoint("TOPLEFT",16,y); y=y-(box2H+16)
  local sPer=MakeSlider(box2,"Buttons per row/column",1,12,1,0,function(v) DB.perLine=v; RefreshAll() end); sPer:SetPoint("TOPLEFT",16,-48)
  local cbVert=MakeCheckbox(box2,"Vertical orientation"); cbVert:SetPoint("LEFT", sPer, "RIGHT", 40, 0)
  cbVert:SetScript("OnClick", function(b) DB.vertical=b:GetChecked() and true or false; RefreshAll() end)

  local box3H=70; local box3=Box(c,"Position",560,box3H); box3:SetPoint("TOPLEFT",16,y); y=y-(box3H+16)

  local cbLock=MakeCheckbox(box3,"Lock panel (uncheck to move)")
cbLock:SetPoint("TOPLEFT",16,-34)
cbLock:SetScript("OnClick", function(b)
  DB.locked=b:GetChecked() and true or false
  Panel:EnableMouse(not DB.locked)
  UpdateLockIndicator()
end)
cbVert:SetChecked(DB.vertical)
cbLock:SetChecked(DB.locked)

local cbBehind = MakeCheckbox(box3, "Place panel behind interface windows")
cbBehind:SetPoint("TOPLEFT", cbLock, "BOTTOMLEFT", 0, -8)
cbBehind:SetScript("OnClick", function(b)
  DB.panelStrata = b:GetChecked() and "LOW" or "MEDIUM"
  Panel:SetFrameStrata(DB.panelStrata)
end)
cbBehind:SetChecked((DB.panelStrata or "LOW") == "LOW")


  sSize:ForceInit(DB.iconSize or DEFAULTS.iconSize)
  sPad:ForceInit(DB.padding or DEFAULTS.padding)
  sAlpha:ForceInit(DB.bgAlpha or DEFAULTS.bgAlpha)
  sBorder:ForceInit(DB.panelBorderAlpha or DEFAULTS.panelBorderAlpha)
  sBtnPad:ForceInit(DB.btnInnerPad or DEFAULTS.btnInnerPad)
  sPer:ForceInit(DB.perLine or DEFAULTS.perLine)

  c:SetHeight(-y+20)
end

local function BuildBehaviorPanel()
  if PanelBehavior._built then return end; PanelBehavior._built=true
  local c=CreateScrollArea(PanelBehavior); local y=-16
  local h=Header(c,"Behavior"); h:SetPoint("TOPLEFT",16,y); y=y-28
  local tip=SubText(c,"Display and action options."); tip:SetPoint("TOPLEFT",16,y); y=y-24

  local box1H=90; local box1=Box(c,"Visibility",560,box1H); box1:SetPoint("TOPLEFT",16,y); y=y-(box1H+16)
  local cbOnly=MakeCheckbox(box1,"Show only when in group/raid"); cbOnly:SetPoint("TOPLEFT",16,-34)
  cbOnly:SetScript("OnClick", function(b) DB.onlyInGroup=b:GetChecked() and true or false; RefreshAll() end)
  cbOnly:SetChecked(DB.onlyInGroup)

  local box2H=120; local box2=Box(c,"Pull / Ready",560,box2H); box2:SetPoint("TOPLEFT",16,y); y=y-(box2H+16)
  local sPull=MakeSlider(box2,"Default pull (s)",1,60,1,0,function(v) DB.pullSec=v end); sPull:SetPoint("TOPLEFT",16,-48)
  sPull:ForceInit(DB.pullSec or DEFAULTS.pullSec)

  local box3H=120; local box3=Box(c,"Minimap",560,box3H); box3:SetPoint("TOPLEFT",16,y); y=y-(box3H+16)
  local cbMini=MakeCheckbox(box3,"Show minimap icon (skull)"); cbMini:SetPoint("TOPLEFT",16,-30)
  local sMini=MakeSlider(box3,"Minimap icon size (px)",12,24,1,0,function(v) DB.minimapSize=v; Minimap_Apply() end); sMini:SetPoint("TOPLEFT",32,-64); sMini:SetPoint("RIGHT",-16,0)
  local function applyMiniState()
    local on=cbMini:GetChecked(); DB.minimapEnabled=on and true or false; Minimap_Apply()
    sMini:EnableMouse(on); local a=on and 1 or 0.35
    sMini:SetAlpha(a); sMini.Text:SetAlpha(a); sMini.Low:SetAlpha(a); sMini.High:SetAlpha(a)
    local th=sMini:GetThumbTexture(); if th then th:SetAlpha(a) end
  end
  cbMini:SetScript("OnClick", applyMiniState); cbMini:SetChecked(DB.minimapEnabled)
  sMini:ForceInit(DB.minimapSize or DEFAULTS.minimapSize); After(0, applyMiniState)

  c:SetHeight(-y+20)
end

PanelMain:SetScript("OnShow", BuildMainPanel)
PanelLayout:SetScript("OnShow", BuildLayoutPanel)
PanelBehavior:SetScript("OnShow", BuildBehaviorPanel)

-- ================== REGISTER OPTIONS ==================
local function RegisterOptions()
  if Settings and Settings.RegisterCanvasLayoutCategory then
    local cat=Settings.RegisterCanvasLayoutCategory(PanelMain, PanelMain.name)
    SettingsCategory=cat
    Settings.RegisterAddOnCategory(cat)
    Settings.RegisterCanvasLayoutSubcategory(cat, PanelLayout, PanelLayout.name)
    Settings.RegisterCanvasLayoutSubcategory(cat, PanelBehavior, PanelBehavior.name)
  else
    InterfaceOptions_AddCategory(PanelMain)
    InterfaceOptions_AddCategory(PanelLayout)
    InterfaceOptions_AddCategory(PanelBehavior)
  end
  BuildMainPanel(); BuildLayoutPanel(); BuildBehaviorPanel()
end

-- ================== INIT / EVENTS ==================
local ev=CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED"); ev:RegisterEvent("PLAYER_LOGIN"); ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event=="ADDON_LOADED" and arg1==ADDON then
    DB = copyDefaults(_G.RaidMarkersPanelDB, DEFAULTS); _G.RaidMarkersPanelDB = DB

    Panel=CreateFrame("Frame","RaidMarkersPanelFrame",UIParent,"BackdropTemplate")
    Panel:SetFrameStrata(DB.panelStrata or "LOW")
    Panel:SetToplevel(false)
    Panel:SetMovable(true); Panel:EnableMouse(true); Panel:RegisterForDrag("LeftButton")
    Panel:SetScript("OnDragStart", function(self) if not DB.locked then self:StartMoving() end end)
    Panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); local p,_,_,x,y=self:GetPoint(1); DB.point,DB.x,DB.y=p,x,y end)

    BuildButtons()
    RegisterOptions()

  elseif event=="PLAYER_LOGIN" then
    RefreshAll()

  elseif event=="GROUP_ROSTER_UPDATE" then
    if DB.onlyInGroup then if IsInGroup() or IsInRaid() then Panel:Show() else Panel:Hide() end end
  end
end)
