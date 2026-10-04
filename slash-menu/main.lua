-- Slash Menu: type "/" at the start of a line, pick a block. Permission: editor.complete only.
-- Items are inserted as Markdown (markdown = true), so "# " becomes a real heading in the visual editor.
-- The popup is offered only at the start of a line, so "and/or" and URLs are left alone.

local function blocks()
  return {
    { label = "Heading 1", insert = "# ", md = true },
    { label = "Heading 2", insert = "## ", md = true },
    { label = "Heading 3", insert = "### ", md = true },
    { label = "Bulleted list", insert = "- ", md = true },
    { label = "Numbered list", insert = "1. ", md = true },
    { label = "Task", insert = "- [ ] ", md = true },
    { label = "Quote", insert = "> ", md = true },
    { label = "Code block", insert = "```\n\n```", md = true },
    { label = "Divider", insert = "---\n", md = true },
    { label = "Table", insert = "| Column 1 | Column 2 | Column 3 |\n| --- | --- | --- |\n|  |  |  |\n", md = true },
    { label = "Date", insert = hn.time.format("%Y-%m-%d"), detail = "today", md = true },
    { label = "Time", insert = hn.time.format("%H:%M"), detail = "now", md = true },
    { label = "Link to note", insert = "[[", md = false },
  }
end

hn.complete{
  id = "blocks",
  trigger = "/",
  items = function(query, ctx)
    if not ctx.at_line_start then return {} end
    local q = (query or ""):lower()
    local prefix, rest = {}, {}
    for _, b in ipairs(blocks()) do
      local name = b.label:lower()
      local item = { label = b.label, detail = b.detail, insert = b.insert, markdown = b.md }
      if q == "" or name:sub(1, #q) == q then prefix[#prefix + 1] = item
      elseif name:find(q, 1, true) then rest[#rest + 1] = item end
    end
    for _, item in ipairs(rest) do prefix[#prefix + 1] = item end
    return prefix
  end,
}
