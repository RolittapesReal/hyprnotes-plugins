-- Journal and Templates. Permissions: notes.read (read templates), notes.index (does a note exist, list templates), notes.write
-- (create the daily note and notes from templates; dangerous), note.read (the open note's path/title), note.edit (insert a template), ui (pick / prompt / notify).
-- Templates are plain Markdown files in the templates folder of the library. Variables: {{date}} {{time}} {{title}} {{weekday}}.

hn.setting{ id = "daily_folder", type = "string", default = "daily", title = "Folder for daily notes" }
hn.setting{ id = "date_format", type = "string", default = "%Y-%m-%d", title = "Daily note file name (strftime, without .md)" }
hn.setting{ id = "templates_folder", type = "string", default = "templates", title = "Folder with templates" }
hn.setting{ id = "daily_template", type = "string", default = "", title = "Daily template file inside the templates folder (optional)" }

local DEFAULT_DAILY = "# {{date}}\n\n## Plan\n\n## Notes\n"

-- Cut s to at most n bytes without splitting a UTF-8 sequence.
local function cut(s, n)
  if #s <= n then return s end
  local i = n + 1
  while i > 1 do
    local b = s:byte(i)
    if b < 0x80 or b >= 0xC0 then break end
    i = i - 1
  end
  return s:sub(1, i - 1)
end

local function clean_folder(s) return (tostring(s or ""):gsub("\\", "/"):gsub("^/+", ""):gsub("/+$", "")) end
local function join(folder, name) folder = clean_folder(folder); return (folder ~= "" and (folder .. "/") or "") .. name end
local function stem(path) return (path:match("([^/]+)$") or path):gsub("%.md$", "") end

-- {{date}} and {{weekday}} describe `epoch` (utc: format it in UTC); without one they mean today. {{time}} is always the clock now.
local function expand(text, title, epoch, utc)
  local vars = {
    date = hn.time.format("%Y-%m-%d", epoch, utc), time = hn.time.format("%H:%M"),
    weekday = hn.time.format("%A", epoch, utc), title = title or "",
  }
  return (text:gsub("{{(%w+)}}", function(name) return vars[name] end))   -- unknown names return nil: left untouched
end

-- nil when the date format cannot be used (non-ASCII, empty or too long output): hn.time.format raises then.
local function daily_path(epoch, utc)
  local ok, name = pcall(hn.time.format, hn.settings.get("date_format"), epoch, utc)
  if not ok then return nil end
  return join(hn.settings.get("daily_folder"), name .. ".md")
end

-- Civil date <-> day number (proleptic Gregorian), no os library in the sandbox.
local function days_from_civil(y, m, d)
  y = m <= 2 and y - 1 or y
  local era = (y >= 0 and y or y - 399) // 400
  local yoe = y - era * 400
  local doy = (153 * (m + (m > 2 and -3 or 9)) + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
  return era * 146097 + doe - 719468
end

-- Only files directly inside the templates folder count. nil means the index is not available (already told the user).
local function templates()
  local folder = clean_folder(hn.settings.get("templates_folder"))
  local rows = hn.notes.query{ from = "notes", where = { { field = "folder", op = "=", value = folder } },
                               select = { "path", "title" }, order = { { field = "path" } }, limit = 100 }
  if not rows then hn.ui.notify("The note index is not available, so templates could not be listed.") return nil end
  local found = {}
  for _, row in ipairs(rows) do
    if row.path and row.path:sub(-3) == ".md" then found[#found + 1] = row.path end
  end
  table.sort(found)
  return found
end

local function no_templates()
  hn.ui.notify("No templates yet. Add Markdown notes to the \"" .. clean_folder(hn.settings.get("templates_folder")) .. "\" folder.")
end

local function pick_template()
  local list = templates()
  if not list then return nil end
  if #list == 0 then no_templates() return nil end
  local names = {}
  for i, p in ipairs(list) do names[i] = stem(p) end
  local i = hn.ui.pick("Template", names)
  if not i then return nil end
  local text = hn.notes.read(list[i])
  if not text then hn.ui.notify("Could not read " .. list[i]) return nil end
  return text
end

-- The host refuses odd note paths with an error, so check first and tell the user instead.
local function valid_path(p)
  if p == "" or #p > 512 or p:sub(1, 1) == "/" or p:find("[%c\\]") or p:find("//", 1, true) then return false end
  for seg in p:gmatch("[^/]+") do
    if seg == "." or seg == ".." then return false end
  end
  return true
end

-- Does the note exist? The index can lag behind the disk (sync is asynchronous), so "no row" is not enough: a note that is on
-- disk but not indexed yet must never be overwritten. hn.notes.frontmatter reads the file itself (a table, even without
-- frontmatter, means it exists). true / false / nil (could not tell: do not create).
local function note_exists(path)
  local rows = hn.notes.query{ from = "notes", where = { { field = "path", op = "=", value = path } }, select = { "path" }, limit = 1 }
  if not rows then return nil end
  if #rows > 0 then return true end
  local fm, err = hn.notes.frontmatter(path)
  if type(fm) == "table" then return true end
  if err == "not found" then return false end
  return nil
end

local function ensure_daily(path, epoch, utc)
  if not path then hn.ui.notify("The daily note path is not valid. Check the journal settings.") return false end
  if not valid_path(path) then hn.ui.notify("The daily note path " .. cut(path, 120) .. " is not valid. Check the journal settings.") return false end
  local exists = note_exists(path)
  if exists == nil then hn.ui.notify("The note index is not available, so today's note was not created.") return false end
  if exists then return true end
  local text = DEFAULT_DAILY
  local file = hn.settings.get("daily_template")
  local tpath = join(hn.settings.get("templates_folder"), file)
  if file ~= "" and valid_path(tpath) then
    local t = hn.notes.read(tpath)
    if t then text = t end
  end
  if hn.notes.write(path, expand(text, stem(path), epoch, utc)) then return true end
  hn.ui.notify("Could not create " .. cut(path, 120))
  return false
end

local function open_day(path, epoch, utc)
  if ensure_daily(path, epoch, utc) then hn.notes.open(path) end
end

local function shifted_day(delta)
  local current = hn.note.path()
  local y, m, d = (current or ""):match("(%d%d%d%d)%-(%d%d)%-(%d%d)%.md$")
  local base_path = join(hn.settings.get("daily_folder"), "")
  if y and (current or ""):sub(1, #base_path) == base_path then
    local days = days_from_civil(tonumber(y), tonumber(m), tonumber(d)) + delta
    local epoch = days * 86400 + 43200                        -- noon UTC: no time-zone edge cases
    return daily_path(epoch, true), epoch, true
  end
  -- Relative to today in local time. A DST change can shift this by an hour, which only matters within an hour of midnight.
  local epoch = hn.time.now() + delta * 86400
  return daily_path(epoch), epoch, false
end

hn.command{ id = "today", title = "Journal: open today's note", run = function() local t = hn.time.now(); open_day(daily_path(t), t) end }
hn.command{ id = "previous-day", title = "Journal: previous day", run = function() open_day(shifted_day(-1)) end }
hn.command{ id = "next-day", title = "Journal: next day", run = function() open_day(shifted_day(1)) end }

hn.command{
  id = "new-from-template",
  title = "Journal: new note from template",
  run = function()
    local text = pick_template()
    if not text then return end
    local title = hn.ui.prompt("New note", "Title", "")
    if not title or title:match("^%s*$") then return end
    local path = hn.notes.create(title, expand(text, title))
    if path then hn.notes.open(path) else hn.ui.notify("Could not create the note") end
  end,
}

hn.command{
  id = "insert-template",
  title = "Journal: insert template",
  run = function()
    local text = pick_template()
    if text then hn.note.insert(expand(text, hn.note.title())) end
  end,
}

hn.toolbar_button{ id = "today", title = "Today", icon = "calendar", run = function() local t = hn.time.now(); open_day(daily_path(t), t) end }
