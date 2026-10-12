-- DÉBATTEMENT V3.4 - 1 capteur
-- Version simplifiée selon demande utilisateur :
--   * suppression du titre "GOUVERNE"
--   * suppression du bloc "MAX ABSOLU"
--   * conservation de l'angle courant, de la jauge, de MAX+ et MAX-
--   * RAZ MAX / ZERO / état CAPTEUR
--   * réglage "Angle pour 100 %" au pas de 0,1°

local TOUCH_START_CODE = 16640
local TOUCH_STOP_CODE  = 16641

local function tr(fr, en)
  if system.getLocale() == "fr" then return fr end
  return en
end

local function clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

local function create()
  return {
    source = nil,
    span100_tenth = 182, -- 18,2°
    raw = 0,
    zeroRaw = 0,
    angle = 0,
    maxPos = 0,
    maxNeg = 0,
    haveValue = false,
    pendingZero = true,
    pressed = nil
  }
end

local function configure(widget)
  local line = form.addLine(tr("Source Trainer", "Trainer source"))
  form.addSourceField(
    line,
    nil,
    function() return widget.source end,
    function(value)
      widget.source = value
      widget.pendingZero = true
      widget.haveValue = false
      widget.maxPos = 0
      widget.maxNeg = 0
    end
  )

  line = form.addLine(tr("Angle pour 100 %", "Angle at 100 %"))
  local f = form.addNumberField(
    line,
    nil,
    10,      -- 1,0°
    3600,    -- 360,0°
    function() return widget.span100_tenth end,
    function(value)
      widget.span100_tenth = value
      widget.maxPos = 0
      widget.maxNeg = 0
    end
  )
  f:decimals(1)
  f:suffix("°")
end

local function read(widget)
  widget.source = storage.read("source")
  local span = storage.read("span100_tenth")
  if type(span) == "number" and span >= 10 and span <= 3600 then
    widget.span100_tenth = span
  end
  widget.pendingZero = true
  return true
end

local function write(widget)
  storage.write("source", widget.source)
  storage.write("span100_tenth", widget.span100_tenth)
  return true
end

local function resetMax(widget)
  widget.maxPos = 0
  widget.maxNeg = 0
  lcd.invalidate()
end

local function zeroNow(widget)
  if widget.haveValue then
    widget.zeroRaw = widget.raw
    widget.angle = 0
    resetMax(widget)
  else
    widget.pendingZero = true
    lcd.invalidate()
  end
end

local function menu(widget)
  return {
    { tr("RAZ MAX", "RESET MAX"), function() resetMax(widget) end },
    { tr("Zéro au neutre", "Zero at neutral"), function() zeroNow(widget) end }
  }
end

local function wakeup(widget)
  if not widget.source then
    widget.haveValue = false
    lcd.invalidate()
    return
  end

  local ok, value = pcall(function() return widget.source:value() end)
  if not ok or type(value) ~= "number" then
    widget.haveValue = false
    lcd.invalidate()
    return
  end

  widget.raw = value
  widget.haveValue = true

  if widget.pendingZero then
    widget.zeroRaw = value
    widget.angle = 0
    widget.maxPos = 0
    widget.maxNeg = 0
    widget.pendingZero = false
  else
    local span100 = widget.span100_tenth / 10.0
    local angle = (value - widget.zeroRaw) * (span100 / 100.0)
    if math.abs(angle) < 0.10 then angle = 0 end
    widget.angle = angle

    if angle > widget.maxPos then widget.maxPos = angle end
    if angle < widget.maxNeg then widget.maxNeg = angle end
  end

  lcd.invalidate()
end

local function fmtSigned(v)
  if math.abs(v) < 0.05 then v = 0 end
  return string.format("%+.1f°", v)
end

local function getLayout()
  local w, h = lcd.getWindowSize()

  local margin = math.max(10, math.floor(w * 0.018))
  local bottomH = math.max(56, math.floor(h * 0.115))
  local bottomY = h - bottomH - 8

  local panelX = margin
  local panelY = 8
  local panelW = w - 2 * margin
  local panelH = bottomY - panelY - 10

  local gap = math.max(8, math.floor(w * 0.012))
  local razW = math.floor((panelW - 2 * gap) * 0.28)
  local zeroW = math.floor((panelW - 2 * gap) * 0.40)
  local statusW = panelW - 2 * gap - razW - zeroW

  return {
    w=w, h=h,
    panelX=panelX, panelY=panelY, panelW=panelW, panelH=panelH,
    bottomY=bottomY, bottomH=bottomH,
    razX=panelX, razW=razW,
    zeroX=panelX + razW + gap, zeroW=zeroW,
    statusX=panelX + razW + gap + zeroW + gap, statusW=statusW
  }
end

local function pointIn(x, y, bx, by, bw, bh)
  return x >= bx and x <= bx + bw and y >= by and y <= by + bh
end

local function event(widget, category, value, x, y)
  if category ~= EVT_TOUCH then return false end
  local L = getLayout()

  if value == TOUCH_START_CODE then
    if pointIn(x, y, L.razX, L.bottomY, L.razW, L.bottomH) then
      widget.pressed = "raz"
      lcd.invalidate()
      return true
    elseif pointIn(x, y, L.zeroX, L.bottomY, L.zeroW, L.bottomH) then
      widget.pressed = "zero"
      lcd.invalidate()
      return true
    end

  elseif value == TOUCH_STOP_CODE then
    local p = widget.pressed
    widget.pressed = nil

    if p == "raz" and pointIn(x, y, L.razX, L.bottomY, L.razW, L.bottomH) then
      resetMax(widget)
      return true
    elseif p == "zero" and pointIn(x, y, L.zeroX, L.bottomY, L.zeroW, L.bottomH) then
      zeroNow(widget)
      return true
    end

    lcd.invalidate()
  end

  return false
end

local function drawButton(x, y, w, h, fill, title, subtitle)
  lcd.color(fill)
  lcd.drawFilledRectangle(x, y, w, h)
  lcd.color(lcd.RGB(245,245,245))
  lcd.drawRectangle(x, y, w, h)

  lcd.font(FONT_L)
  lcd.drawText(x + 10, y + 5, title)

  lcd.font(FONT_S)
  lcd.drawText(x + 10, y + h - 19, subtitle)
end

local function paint(widget)
  local L = getLayout()

  local bg     = lcd.RGB(0, 0, 0)
  local dark   = lcd.RGB(7, 12, 19)
  local blue   = lcd.RGB(20, 145, 255)
  local white  = lcd.RGB(245, 245, 245)
  local soft   = lcd.RGB(160, 175, 195)
  local bar    = lcd.RGB(47, 47, 50)
  local red    = lcd.RGB(195, 25, 25)
  local yellow = lcd.RGB(245, 170, 15)
  local stat   = lcd.RGB(20, 90, 185)

  lcd.color(bg)
  lcd.drawFilledRectangle(0, 0, L.w, L.h)

  -- Panneau principal
  lcd.color(dark)
  lcd.drawFilledRectangle(L.panelX, L.panelY, L.panelW, L.panelH)
  lcd.color(blue)
  lcd.drawRectangle(L.panelX, L.panelY, L.panelW, L.panelH)

  -- Indication BT discrète
  lcd.font(FONT_M)
  if widget.haveValue then
    lcd.color(blue)
    lcd.drawText(L.panelX + L.panelW - 44, L.panelY + 8, "BT")
  else
    lcd.color(lcd.RGB(245, 90, 90))
    lcd.drawText(L.panelX + L.panelW - 54, L.panelY + 8, "BT!")
  end

  if not widget.source then
    lcd.font(FONT_XL)
    lcd.color(lcd.RGB(245, 90, 90))
    lcd.drawText(L.panelX + 18, L.panelY + 40,
      tr("Sélectionner Trainer 2 dans Réglages", "Select Trainer 2 in settings"))
  elseif not widget.haveValue then
    lcd.font(FONT_XL)
    lcd.color(lcd.RGB(245, 90, 90))
    lcd.drawText(L.panelX + 18, L.panelY + 40,
      tr("Pas de valeur Trainer", "No trainer value"))
  else
    -- Valeur principale
    lcd.font(FONT_XXXXL)
    lcd.color(blue)
    lcd.drawText(L.panelX + math.floor(L.panelW * 0.31), L.panelY + 18, fmtSigned(widget.angle))

    -- Jauge
    local gx = L.panelX + math.floor(L.panelW * 0.075)
    local gw = math.floor(L.panelW * 0.85)
    local gy = L.panelY + math.floor(L.panelH * 0.32)

    lcd.font(FONT_M)
    lcd.color(white)
    lcd.drawText(gx, gy - 25, "-45°")
    lcd.drawText(gx + math.floor(gw/2) - 6, gy - 25, "0")
    lcd.drawText(gx + gw - 42, gy - 25, "+45°")

    lcd.color(bar)
    lcd.drawFilledRectangle(gx, gy, gw, 16)

    local centerX = gx + math.floor(gw / 2)
    lcd.color(white)
    lcd.drawFilledRectangle(centerX - 1, gy - 5, 3, 26)

    local norm = clamp(widget.angle / 45.0, -1.0, 1.0)
    local posX = gx + math.floor(((norm + 1.0) / 2.0) * gw)
    lcd.color(blue)
    lcd.drawFilledRectangle(posX - 3, gy - 4, 7, 24)

    -- Section max + / max -
    local secY = L.panelY + math.floor(L.panelH * 0.53)
    lcd.color(blue)
    lcd.drawLine(L.panelX, secY, L.panelX + L.panelW, secY)
    lcd.drawLine(L.panelX + math.floor(L.panelW/2), secY,
                 L.panelX + math.floor(L.panelW/2), L.panelY + L.panelH)

    lcd.font(FONT_XL)
    lcd.color(white)
    lcd.drawText(L.panelX + math.floor(L.panelW * 0.18), secY + 10, "MAX +")
    lcd.drawText(L.panelX + math.floor(L.panelW * 0.67), secY + 10, "MAX -")

    lcd.font(FONT_XXXL)
    lcd.color(blue)
    lcd.drawText(L.panelX + math.floor(L.panelW * 0.10), secY + 46, fmtSigned(widget.maxPos))
    lcd.drawText(L.panelX + math.floor(L.panelW * 0.58), secY + 46, fmtSigned(widget.maxNeg))

    -- Ligne compacte d'information
    local cal = widget.span100_tenth / 10.0
    lcd.font(FONT_S)
    lcd.color(soft)
    lcd.drawText(L.panelX + 12, L.panelY + L.panelH - 18, string.format("100%% = %.1f°", cal))
    lcd.drawText(L.panelX + L.panelW - 82, L.panelY + L.panelH - 18, tr("Zéro OK", "Zero OK"))
  end

  -- Barre basse
  drawButton(
    L.razX, L.bottomY, L.razW, L.bottomH,
    red,
    "RAZ MAX",
    tr("Effacer les max", "Clear max")
  )

  drawButton(
    L.zeroX, L.bottomY, L.zeroW, L.bottomH,
    yellow,
    "ZERO",
    tr("Définir le neutre", "Set neutral")
  )

  drawButton(
    L.statusX, L.bottomY, L.statusW, L.bottomH,
    stat,
    tr("CAPTEUR", "SENSOR"),
    widget.haveValue and "1 / 1" or "0 / 1"
  )
end

local function init()
  system.registerWidget({
    key = "dbtv34",
    name = tr("Débattement V3.4", "Travel V3.4"),
    create = create,
    configure = configure,
    paint = paint,
    wakeup = wakeup,
    read = read,
    write = write,
    menu = menu,
    event = event,
    persistent = true,
    title = false
  })
end

return { init = init }
