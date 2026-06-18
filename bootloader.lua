-- CCBoot v1.0 | ComputerCraft EFI Bootloader
-- Place as /startup.lua on your computer

local EFI_DIR = "/efi"
local TIMEOUT = 5        -- giây auto-boot vào CraftOS
local BOOT_VER = "1.0"

-------------------------------------------------------------------------------
-- Utilities
-------------------------------------------------------------------------------

local W, H = term.getSize()

local function col(fg, bg)
  if term.isColor() then
    if fg then term.setTextColor(fg) end
    if bg then term.setBackgroundColor(bg) end
  end
end

local function clearLine(y, bg)
  term.setCursorPos(1, y)
  if bg then col(nil, bg) end
  term.write((" "):rep(W))
end

local function centerWrite(y, text, fg, bg)
  if fg or bg then col(fg, bg) end
  term.setCursorPos(math.max(1, math.floor((W - #text) / 2) + 1), y)
  term.write(text)
end

local function hline(y, fg, bg)
  col(fg or colors.gray, bg or colors.black)
  term.setCursorPos(1, y)
  term.write(("-"):rep(W))
end

-------------------------------------------------------------------------------
-- EFI Metadata Parser
--
-- Dong dau (line 1) cua moi .efi PHAI la comment metadata theo format:
--   -- name=<ten>; desc=<mo ta>; version=<ver>; author=<tac gia>
--
-- "name" la bat buoc, cac truong con lai optional.
-------------------------------------------------------------------------------

local function parseMeta(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local firstLine = f:read("*l")
  f:close()

  -- Phai bat dau bang "--"
  if not firstLine or not firstLine:match("^%s*%-%-") then
    return nil
  end

  -- Strip comment prefix
  local raw = firstLine:gsub("^%s*%-%-%s*", "")

  local meta = { path = path }
  -- Parse key=value; key=value; ...
  -- Value co the co dau ngoac kep hoac khong
  for key, val in raw:gmatch('(%w+)%s*=%s*"?([^;\"]+)"?') do
    meta[key:lower()] = val:match("^%s*(.-)%s*$")
  end

  -- "name" bat buoc
  if not meta.name or meta.name == "" then return nil end

  meta.desc    = meta.desc    or meta.description or "(no description)"
  meta.version = meta.version or "?"
  meta.author  = meta.author  or "Unknown"

  return meta
end

-------------------------------------------------------------------------------
-- Scan /efi
-------------------------------------------------------------------------------

local function scanEFI()
  if not fs.exists(EFI_DIR) then
    fs.makeDir(EFI_DIR)
  end

  local entries = {}
  local ok, list = pcall(fs.list, EFI_DIR)
  if not ok then return entries end

  -- Sort de menu nhat quan
  table.sort(list)

  for _, fname in ipairs(list) do
    if fname:match("%.efi$") then
      local fullPath = fs.combine(EFI_DIR, fname)
      local meta = parseMeta(fullPath)
      if meta then
        entries[#entries + 1] = meta
      end
    end
  end

  return entries
end

-------------------------------------------------------------------------------
-- Draw Menu
-------------------------------------------------------------------------------

local ENTRY_H = 3   -- so dong moi entry chiem

local function buildList(efiEntries)
  -- CraftOS luon la option dau tien
  local list = {
    { name = "CraftOS", desc = "Default ComputerCraft shell", isCraftOS = true }
  }
  for _, e in ipairs(efiEntries) do
    list[#list + 1] = e
  end
  return list
end

local function drawMenu(list, sel, countdown)
  term.clear()
  col(colors.white, colors.black)

  -- Header
  clearLine(1, colors.blue)
  centerWrite(1, string.format(" CCBoot v%s ", BOOT_VER), colors.white, colors.blue)

  clearLine(2, colors.black)
  col(colors.cyan, colors.black)
  centerWrite(2, string.format("Found %d EFI entr%s", #list - 1,
    (#list - 1 == 1) and "y" or "ies"), colors.cyan, colors.black)

  hline(3)

  -- Entries (tu dong 4 tro di)
  local contentH = H - 5   -- tru header(3) + hline + footer(2)
  local startY   = 4
  local maxShow  = math.floor(contentH / ENTRY_H)

  -- Scroll so entry duoc chon luon hien thi
  local offset = 0
  if sel > maxShow then
    offset = sel - maxShow
  end

  for i = 1 + offset, math.min(#list, maxShow + offset) do
    local e = list[i]
    local drawY = startY + (i - 1 - offset) * ENTRY_H

    if drawY + 1 > H - 2 then break end

    if i == sel then
      -- Highlighted
      clearLine(drawY, colors.white)
      col(colors.black, colors.white)
      term.setCursorPos(2, drawY)
      if e.isCraftOS then
        term.write("> CraftOS")
      else
        term.write(string.format("> %s  [v%s]", e.name, e.version))
      end

      -- Sub-line
      clearLine(drawY + 1, colors.gray)
      col(colors.black, colors.gray)
      term.setCursorPos(5, drawY + 1)
      local sub
      if e.isCraftOS then
        sub = "Boot default ComputerCraft shell"
      else
        sub = string.format("%s  (by %s)", e.desc, e.author)
      end
      if #sub > W - 5 then sub = sub:sub(1, W - 8) .. "..." end
      term.write(sub)

      col(colors.white, colors.black)
      clearLine(drawY + 2, colors.black)
    else
      -- Normal
      col(colors.white, colors.black)
      clearLine(drawY, colors.black)
      term.setCursorPos(2, drawY)
      if e.isCraftOS then
        term.write("  CraftOS")
      else
        term.write(string.format("  %s  [v%s]", e.name, e.version))
      end

      col(colors.lightGray, colors.black)
      clearLine(drawY + 1, colors.black)
      term.setCursorPos(5, drawY + 1)
      local sub
      if e.isCraftOS then
        sub = "Boot default ComputerCraft shell"
      else
        sub = string.format("%s  (by %s)", e.desc, e.author)
      end
      if #sub > W - 5 then sub = sub:sub(1, W - 8) .. "..." end
      term.write(sub)

      col(colors.black, colors.black)
      clearLine(drawY + 2, colors.black)
    end
  end

  -- Footer
  hline(H - 1)
  clearLine(H, colors.black)
  col(colors.yellow, colors.black)
  term.setCursorPos(2, H)

  local hint = "[Up/Down] Move  [Enter] Boot"
  if countdown and countdown > 0 then
    hint = hint .. string.format("  | Auto-boot CraftOS in %ds", countdown)
  end
  term.write(hint)

  col(colors.white, colors.black)
end

-------------------------------------------------------------------------------
-- Boot handlers
-------------------------------------------------------------------------------

local function bootCraftOS()
  term.clear()
  term.setCursorPos(1, 1)
  col(colors.white, colors.black)
  print("Booting CraftOS...")
  sleep(0.2)
  -- Return tu startup.lua → CraftOS shell load binh thuong
end

local function bootEFI(entry)
  term.clear()
  term.setCursorPos(1, 1)
  col(colors.lime, colors.black)
  print(string.format("[ CCBoot ] Loading %s v%s", entry.name, entry.version))
  col(colors.white, colors.black)
  print(string.format("           %s", entry.path))
  sleep(0.3)

  -- Set working dir ve root truoc khi chay
  shell.setDir("/")

  -- Load file, truyen _ENV de EFI co the dung shell, term, etc. binh thuong
  local fn, err = loadfile(entry.path, "t", _ENV)
  if not fn then
    col(colors.red, colors.black)
    printError("Failed to load EFI: " .. tostring(err))
    sleep(4)
    return false
  end

  -- Thuc thi
  local ok, rerr = pcall(fn)
  if not ok then
    col(colors.red, colors.black)
    printError("EFI runtime error: " .. tostring(rerr))
    sleep(4)
    return false
  end

  return true
end

-------------------------------------------------------------------------------
-- Main
-------------------------------------------------------------------------------

local function main()
  local efiEntries = scanEFI()
  local list       = buildList(efiEntries)
  local sel        = 1
  local countdown  = TIMEOUT
  local timerID    = os.startTimer(1)

  while true do
    drawMenu(list, sel, countdown)

    local ev, p1 = os.pullEvent()

    if ev == "timer" and p1 == timerID then
      -- Countdown tick
      countdown = countdown - 1
      if countdown <= 0 then
        bootCraftOS()
        return
      end
      timerID = os.startTimer(1)

    elseif ev == "key" then
      -- Phim bat ky → huy countdown
      countdown = -1
      os.cancelTimer(timerID)

      if p1 == keys.up then
        sel = (sel > 1) and (sel - 1) or #list
      elseif p1 == keys.down then
        sel = (sel < #list) and (sel + 1) or 1
      elseif p1 == keys.enter or p1 == keys.space then
        if list[sel].isCraftOS then
          bootCraftOS()
          return
        else
          local success = bootEFI(list[sel])
          if success then
            return
          end
          -- Boot that bai → quay lai menu, bat lai countdown
          countdown = TIMEOUT
          timerID   = os.startTimer(1)
        end
      end
    end
  end
end

main()