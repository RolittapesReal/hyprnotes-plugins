-- Wiki Links. Permissions: editor.complete ([[ and [[note# completion), editor.links (link clicks), notes.read (list/read/open),
-- notes.index (resolve, links, backlinks), note.read (the open note's path), notes.write (create a note from an unresolved link;
-- dangerous), ui (confirmation), ui.panel (the Links panel).

hn.setting{ id = "confirm_create", type = "bool", default = true, title = "Ask before creating a note from an unresolved link" }

local MAX_ITEMS, MAX_HEADINGS, READ_LIMIT, MAX_ROWS = 20, 50, 64 * 1024, 60

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

local function stem(path) return (((path:match("([^/]+)$") or path):gsub("%.md$", ""))) end
local function folder_of(path) return path:match("^(.*)/[^/]*$") or "" end

-- ---------------------------------------------------------------- completion
local function name_items(query)
  local items = {}
  for _, note in ipairs(hn.notes.list(query)) do
    if #items >= MAX_ITEMS then break end
    local name = stem(note.path)
    local r = hn.notes.resolve(name)
    local insert = name
    if r and r.status == "ambiguous" then insert = (note.path:gsub("%.md$", "")) end
    items[#items + 1] = { label = cut(note.title ~= "" and note.title or name, 200), detail = cut(note.path, 200), insert = cut(insert, 4000) .. "]]" }
  end
  -- Aliases (frontmatter `aliases`): the index stores one meta row per list item, so `contains` finds notes with a matching alias,
  -- but it cannot return the alias text; read the frontmatter of a few matches for it. At most 1 query + 5 reads. Failures are silent.
  if query ~= "" and #items < MAX_ITEMS then
    local rows = hn.notes.query{ from = "notes", where = { { field = "meta.aliases", op = "contains", value = cut(query, 200) } },
                                 select = { "path", "title" }, limit = 10 }
    local seen, reads, q = {}, 0, query:lower()
    for _, it in ipairs(items) do seen[it.insert] = true end
    for _, row in ipairs(rows or {}) do
      if #items >= MAX_ITEMS or reads >= 5 then break end
      local path = row.path
      if type(path) == "string" and path ~= "" then
        reads = reads + 1
        local fm = hn.notes.frontmatter(path)
        local base                                                      -- resolved once per note
        for _, a in ipairs(type(fm) == "table" and type(fm.aliases) == "table" and fm.aliases or {}) do
          if #items >= MAX_ITEMS then break end
          if type(a) == "string" and a ~= "" and a:lower():find(q, 1, true) then
            local name = stem(path)
            if not base then
              local r = hn.notes.resolve(name)
              base = (r and r.status == "ambiguous") and (path:gsub("%.md$", "")) or name
            end
            local insert = cut(base, 3000) .. "|" .. cut(a, 1000) .. "]]"
            if not seen[insert] then
              seen[insert] = true
              local title = type(row.title) == "string" and row.title ~= "" and row.title or name
              items[#items + 1] = { label = cut(a, 200), detail = cut("alias of " .. title, 200), insert = insert }
            end
          end
        end
      end
    end
  end
  return items
end

local function heading_items(name, filter)
  local r = hn.notes.resolve(name)
  if not r or r.status ~= "resolved" then return {} end
  local text = hn.notes.read(r.path)
  if not text then return {} end
  text = text:sub(1, READ_LIMIT)
  local items, fenced, f = {}, false, filter:lower()
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line:match("^%s*```") or line:match("^%s*~~~") then fenced = not fenced
    elseif not fenced then
      local title = line:match("^#+%s+(.-)%s*#*%s*$")
      if title and title ~= "" and (f == "" or title:lower():find(f, 1, true)) then
        title = cut(title, 200)
        items[#items + 1] = { label = title, detail = "heading", insert = cut(name, 4000) .. "#" .. title .. "]]" }
        if #items >= MAX_HEADINGS then break end
      end
    end
  end
  return items
end

hn.complete{
  id = "links",
  trigger = "[[",
  items = function(query)
    local name, filter = query:match("^([^#]+)#(.*)$")
    if name then return heading_items(name, filter) end
    return name_items(query)
  end,
}

-- ---------------------------------------------------------------- clicking links
-- A target becomes a path under the current note's folder, so it must not climb out, be absolute or hold odd characters.
local function safe_target(target)
  if target == "" or target:find("[%c\\]") or target:sub(1, 1) == "/" or target:sub(-1) == "/" or target:find("^%s") or target:find("%s$") then return false end
  for seg in target:gmatch("[^/]+") do
    if seg == "." or seg == ".." then return false end
  end
  return not target:find("//", 1, true) and #target <= 200
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

local function create_from(target)
  if not safe_target(target) then hn.ui.notify("Cannot create a note named \"" .. cut(target, 80) .. "\".") return end
  if hn.settings.get("confirm_create") and not hn.ui.confirm("\"" .. target .. "\" does not exist yet. Create it?") then return end
  local base = folder_of(hn.note.path() or "")
  local path = (base ~= "" and (base .. "/") or "") .. target .. ".md"
  local exists = note_exists(path)
  if exists == nil then hn.ui.notify("The note index is not available, so the note was not created.") return end
  if exists then hn.notes.open(path) return end
  if hn.notes.write(path, "# " .. (target:match("([^/]+)$") or target) .. "\n\n") then hn.notes.open(path)
  else hn.ui.notify("Could not create " .. cut(path, 200)) end
end

hn.link_handler{ pattern = function(ref) return ref.kind == "link" end }

hn.on("link.activate", function(ref)
  if ref.resolved then hn.notes.open(ref.resolved) return true end
  create_from(ref.target)
  return true
end)

-- ---------------------------------------------------------------- panel
local function section(blocks, title, rows, make)
  blocks[#blocks + 1] = { type = "heading", text = title .. " (" .. #rows .. ")", level = 2 }
  if #rows == 0 then blocks[#blocks + 1] = { type = "empty", text = "None." } return end
  local items = {}
  for i = 1, math.min(#rows, MAX_ROWS) do items[i] = make(rows[i]) end   -- the host allows 200 blocks per panel, every list item counts
  blocks[#blocks + 1] = { type = "list", items = items }
  if #rows > MAX_ROWS then blocks[#blocks + 1] = { type = "empty", text = (#rows - MAX_ROWS) .. " more" } end
end

local function fit_path(p) return #p <= 512 and p or nil end

hn.panel{
  id = "links",
  title = "Links",
  icon = "link",
  refresh_on = { "note.opened", "note.saved" },
  render = function(ctx)
    if not ctx.path then return { { type = "empty", text = "Open a note to see its links." } } end
    local back, err = hn.notes.backlinks(ctx.path, { limit = 50 })
    if not back then return { { type = "empty", text = "The link index is not available (" .. cut(tostring(err), 100) .. ")." } } end
    local out = hn.notes.links(ctx.path) or {}
    local resolved, unresolved = {}, {}
    for _, row in ipairs(out) do
      if row.resolved then resolved[#resolved + 1] = row else unresolved[#unresolved + 1] = row end
    end
    local blocks = {}
    section(blocks, "Backlinks", back, function(row)
      local src = row.src or ""
      return { type = "item", title = cut(stem(src), 200), subtitle = row.context and cut(row.context, 400) or nil, path = fit_path(src),
               line = row.line > 0 and row.line or nil, on_click = function() hn.notes.open(src) end }
    end)
    section(blocks, "Outgoing", resolved, function(row)
      local dest = row.resolved
      return { type = "item", title = cut(stem(dest), 200), subtitle = row.context and cut(row.context, 400) or nil, path = fit_path(dest), on_click = function() hn.notes.open(dest) end }
    end)
    section(blocks, "Unresolved", unresolved, function(row)
      local target = row.target
      if row.kind == "embed" then return { type = "item", title = cut(target, 200), subtitle = "Embed" } end
      return { type = "item", title = cut(target, 200), subtitle = "Click to create", on_click = function() create_from(target) end }
    end)
    return blocks
  end,
}
