# Slash Menu

A Notion-style block picker for the editor. Type `/` at the start of a line and a popup lists the blocks you can insert; keep typing to narrow it (`/head` shows the three heading levels, `/task` a checkbox). Names that start with what you typed come first.

Blocks: Heading 1, 2 and 3, Bulleted list, Numbered list, Task, Quote, Code block, Divider, Table, Date (inserts today's date, 2026-10-01 style), Time (the current time, 14:05 style) and Link to note.

All except Link to note are inserted as Markdown, so `# ` becomes a real heading in the visual editor. "Link to note" inserts `[[`, which hands over to the normal note-link completion.

## Permissions

- `editor.complete`: the completion popup. The plugin cannot read or change your notes, touch files or use the network.

## Limits

The menu only appears at the start of a line, so `and/or` or a URL never triggers it.
