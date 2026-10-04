-- Tasks and Saved Queries. Permissions: ui.panel (the panel), notes.index (queries), notes.read (open a note),
-- ui (prompts and messages), storage (the saved queries).
-- A filter is one line of terms. Tasks terms: open | done | text:<word>. Notes terms: tag:<name> | in:<folder> | title:<word> | recent:<days>.
-- The two groups cannot be mixed. The filter compiles to a hn.notes.query table, never SQL.

local FETCH, SHOW, MAX_SAVED, MAX_TAGS = 500, 100, 32, 100   -- fetch up to FETCH rows, render at most SHOW
local active = nil     -- the view shown in the panel; nil = built-in open tasks view; kind "tags" = the tag list

-- Cut s to at most n bytes without splitting a UTF-8 sequence (host limits are in bytes).
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

local function load() local q = hn.storage.get("queries"); return type(q) == "table" and q or {} end

local function compile(filter)
  filter = (filter or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if filter == "" then return nil, "Type at least one term, for example: open text:milk" end
  if #filter > 300 then return nil, "That filter is too long (300 characters at most)" end
  local task_where, note_where = {}, {}
  for term in filter:gmatch("%S+") do
    local key, value = term:match("^(%a+):(.+)$")
    local word = term:lower()
    if word == "open" then task_where[#task_where + 1] = { field = "done", op = "=", value = false }
    elseif word == "done" then task_where[#task_where + 1] = { field = "done", op = "=", value = true }
    elseif key and (key:lower() == "text") then task_where[#task_where + 1] = { field = "text", op = "contains", value = value }
    elseif key and key:lower() == "tag" then
      local tag = value:lower():gsub("^#", "")
      if tag == "" then return nil, "tag: needs a tag name, for example tag:work" end
      note_where[#note_where + 1] = { field = "tag", op = "=", value = tag }
    elseif key and key:lower() == "in" then
      local folder = value:gsub("/+$", "")
      if folder == "" then return nil, "in: needs a folder name, for example in:projects" end
      -- like is not escaped by the index (ESCAPE is backslash), so escape backslash, % and _ here; the trailing % is the prefix match.
      note_where[#note_where + 1] = { field = "folder", op = "like", value = (folder:gsub("[\\%%_]", "\\%0")) .. "%" }
    elseif key and key:lower() == "title" then note_where[#note_where + 1] = { field = "title", op = "contains", value = value }
    elseif key and key:lower() == "recent" then
      local days = tonumber(value)
      if not days or days < 1 or days > 3650 or days ~= math.floor(days) then return nil, "recent: needs a whole number of days (1-3650)" end
      note_where[#note_where + 1] = { field = "mtime", op = ">=", value = (hn.time.now() - days * 86400) * 1000 }   -- the index stores milliseconds
    else return nil, "Unknown term \"" .. cut(term, 40) .. "\". Use open, done, text:, tag:, in:, title: or recent:" end
  end
  if #task_where > 0 and #note_where > 0 then return nil, "Do not mix task terms (open, done, text:) with note terms (tag:, in:, title:, recent:)" end
  if #task_where > 0 then
    return { from = "tasks", where = task_where, order = { { field = "path" }, { field = "line" } }, select = { "path", "line", "text", "done" }, limit = FETCH }, "tasks"
  end
  return { from = "notes", where = note_where, order = { { field = "mtime", dir = "desc" } }, select = { "path", "title", "mtime" }, limit = FETCH }, "notes"
end

local OPEN_TASKS = { from = "tasks", where = { { field = "done", op = "=", value = false } }, order = { { field = "path" }, { field = "line" } }, select = { "path", "line", "text", "done" }, limit = FETCH }
local RECENT = { from = "notes", order = { { field = "mtime", dir = "desc" } }, select = { "path", "title", "mtime" }, limit = 30 }

local function items_for(rows, kind)
  local items = {}
  for i = 1, math.min(#rows, SHOW) do
    local row = rows[i]
    local path = row.path
    -- The panel caps item titles at 200 bytes and subtitles at 400.
    items[i] = kind == "tasks"
      and { type = "item", title = cut(row.text, 200), subtitle = cut(path, 400), path = path, line = row.line, on_click = function() hn.notes.open(path) end }
      or { type = "item", title = cut((row.title ~= nil and row.title ~= "") and row.title or path, 200), subtitle = cut(path, 400), path = path, on_click = function() hn.notes.open(path) end }
  end
  return items
end

local function buttons()
  local b = {
    { type = "button", label = "Open tasks", on_click = function() active = nil hn.panel_refresh("tasks") end },
    { type = "button", label = "By tag", on_click = function() active = { name = "By tag", kind = "tags" } hn.panel_refresh("tasks") end },
    { type = "button", label = "Recent notes", on_click = function() active = { name = "Recent notes", spec = RECENT, kind = "notes" } hn.panel_refresh("tasks") end },
  }
  for i, q in ipairs(load()) do
    local name, filter = q.name, q.filter
    b[#b + 1] = { type = "button", label = name, on_click = function()
      local spec, kind = compile(filter)
      if spec then active = { name = name, spec = spec, kind = kind } hn.panel_refresh("tasks") else hn.ui.notify(kind) end
    end }
  end
  return b
end

-- The tag list: one row per note with its tags as a list (the index cannot group), so count them here.
-- Only the 500 most recently changed notes are scanned.
local function tag_blocks(blocks)
  local rows, err = hn.notes.query({ from = "notes", select = { "tag" }, order = { { field = "mtime", dir = "desc" } }, limit = FETCH })
  if not rows then
    blocks[#blocks + 1] = { type = "empty", text = "The index is not available (" .. tostring(err) .. ")." }
    return blocks
  end
  local count, names = {}, {}
  for _, row in ipairs(rows) do
    for _, t in ipairs(type(row.tag) == "table" and row.tag or {}) do
      if not count[t] then count[t] = 0 names[#names + 1] = t end
      count[t] = count[t] + 1
    end
  end
  table.sort(names)
  blocks[#blocks + 1] = { type = "heading", text = "Tags (" .. #names .. ")" .. (#rows >= FETCH and " in your 500 latest notes" or "") }
  if #names == 0 then blocks[#blocks + 1] = { type = "empty", text = "No tags yet." } return blocks end
  local items = {}
  for i = 1, math.min(#names, MAX_TAGS) do
    local t = names[i]
    local n = count[t]
    items[i] = { type = "item", title = cut(t, 200), subtitle = n .. (n == 1 and " note" or " notes"), on_click = function()
      local spec = compile("tag:" .. t)
      if spec then active = { name = "Tag " .. cut(t, 100), spec = spec, kind = "notes" } hn.panel_refresh("tasks") end
    end }
  end
  blocks[#blocks + 1] = { type = "list", items = items }
  if #names > MAX_TAGS then blocks[#blocks + 1] = { type = "empty", text = (#names - MAX_TAGS) .. " more tags not shown" } end
  return blocks
end

hn.panel{
  id = "tasks",
  title = "Tasks",
  icon = "checklist",
  refresh_on = { "note.saved" },
  render = function()
    local view = active or { name = "Open tasks", spec = OPEN_TASKS, kind = "tasks" }
    local blocks = buttons()
    if view.kind == "tags" then return tag_blocks(blocks) end
    local rows, err = hn.notes.query(view.spec)
    if not rows then
      blocks[#blocks + 1] = { type = "empty", text = "The index is not available (" .. tostring(err) .. ")." }
      return blocks
    end
    local hit = #rows >= view.spec.limit   -- the fetch itself was cut off, so the real count is unknown
    blocks[#blocks + 1] = { type = "heading", text = view.name .. " (" .. #rows .. (hit and "+" or "") .. ")" }
    if #rows == 0 then blocks[#blocks + 1] = { type = "empty", text = "Nothing matches." }
    else
      blocks[#blocks + 1] = { type = "list", items = items_for(rows, view.kind) }
      if #rows > SHOW then blocks[#blocks + 1] = { type = "empty", text = (#rows - SHOW) .. (hit and "+" or "") .. " more not shown" } end
    end
    return blocks
  end,
}

hn.command{
  id = "save-query",
  title = "Tasks: save a query",
  run = function()
    local saved = load()
    if #saved >= MAX_SAVED then hn.ui.notify("You already have " .. MAX_SAVED .. " saved queries (the maximum). Delete one first.") return end
    local name = hn.ui.prompt("Save query", "Name", "")
    if not name or name:match("^%s*$") then return end
    local filter = hn.ui.prompt("Save query", "Filter (open, done, text:, tag:, in:, title:, recent:)", "")
    if not filter then return end
    local spec, problem = compile(filter)
    if not spec then hn.ui.notify(problem) return end
    name = cut(name, 80)
    saved[#saved + 1] = { name = name, filter = filter }
    hn.storage.set("queries", saved)
    hn.ui.notify("Saved \"" .. name .. "\"")
    hn.panel_refresh("tasks")
  end,
}

local function pick_saved(title)
  local saved = load()
  if #saved == 0 then hn.ui.notify("No saved queries yet. Use \"Tasks: save a query\".") return nil end
  local names = {}
  for i, q in ipairs(saved) do names[i] = cut(q.name .. "  -  " .. q.filter, 380) end   -- ui.pick items are capped at 400 bytes
  local i = hn.ui.pick(title, names)
  return i and saved, i
end

hn.command{
  id = "run-query",
  title = "Tasks: run a saved query",
  run = function()
    local saved, i = pick_saved("Run query")
    if not saved then return end
    local q = saved[i]
    local spec, kind = compile(q.filter)
    if not spec then hn.ui.notify(kind) return end
    active = { name = q.name, spec = spec, kind = kind }
    hn.panel_refresh("tasks")
  end,
}

hn.command{
  id = "delete-query",
  title = "Tasks: delete a saved query",
  run = function()
    local saved, i = pick_saved("Delete query")
    if not saved then return end
    local gone = table.remove(saved, i)
    if active and active.name == gone.name then active = nil end
    hn.storage.set("queries", saved)
    hn.ui.notify("Deleted \"" .. gone.name .. "\"")
    hn.panel_refresh("tasks")
  end,
}
