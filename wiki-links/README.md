# Wiki Links

Helpers for `[[wiki links]]`.

## Features

- Type `[[` to complete note names. Names shared by several notes are inserted with their folder (`x/dup`) so the link stays unambiguous.
- Names also match the `aliases` of a note's frontmatter. An alias is offered as `Note|Alias` (the wiki alias syntax) with the detail "alias of Title". At most five alias matches are looked up per popup, and nothing is shown if the index is not available.
- Type `[[note#` to complete the headings of that note (fenced code is skipped). The note name must resolve to exactly one note.
- Click a link to a missing note to create it. The note is created in the folder of the note you are editing, with the target as its title, and opened. A nested target such as `area/Idea` creates the folder path under the current note's folder.
- The Links panel lists Backlinks, Outgoing and Unresolved links for the open note. Click a row to open that note; click an unresolved link to create it. Embeds that do not resolve are shown but cannot be created. Each section shows at most 60 rows, followed by "N more" when there are more; the number in the heading counts all rows of the section, except Backlinks, which are counted up to 50.

Targets with `..`, a leading or trailing `/`, leading or trailing spaces, a backslash, control characters or empty segments are refused and nothing is written.

## Settings

`confirm_create` (default on): ask before creating a note from an unresolved link.

## Permissions

- `editor.complete`, `editor.links`: the completion popup and link clicks.
- `notes.read`, `notes.index`, `note.read`: list and read notes, resolve names and read links, and know which note is open.
- `notes.write`: used only to create a note when you click an unresolved link. This is a dangerous permission, since it could also overwrite notes. The plugin never overwrites: it checks the index and then the file itself, and opens the note if it exists. If it cannot tell (index not available), it refuses to create and says so.
- `ui`, `ui.panel`: the confirmation prompt and the Links panel.

## Limits and notes

Renaming a note in Hyprnotes already updates links that point to it. This plugin does not touch links, so the Links panel simply reflects the updated index.
