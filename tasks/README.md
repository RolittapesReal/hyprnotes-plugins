# Tasks and Saved Queries

A side panel (Tasks) with four views: open tasks, recent notes, notes by tag, and your saved queries. Click a row to open the note. "By tag" lists the tags in your library (with how many notes use each); click a tag to see its notes, the same view as the filter `tag:<name>`.

## Filters

A filter is one line of space-separated terms (keywords are case-insensitive). Use terms from one group only.

Tasks terms:

- `open` - tasks not done yet
- `done` - finished tasks
- `text:<word>` - task text contains the word

Notes terms:

- `tag:<name>` - notes with the tag (a leading `#` is ignored)
- `in:<folder>` - notes whose folder starts with this text (a path prefix: `in:proj` also matches `projects2`)
- `title:<word>` - title contains the word
- `recent:<days>` - modified in the last N days (1-3650)

Examples: `open text:milk`, `done`, `tag:work in:projects recent:7`, `title:plan`.

A filter with no terms, an unknown term, mixed groups or more than 300 characters is rejected with a message and nothing is saved.

## Commands

- Tasks: save a query (name, then filter). At most 32 saved queries.
- Tasks: run a saved query (shows it in the panel).
- Tasks: delete a saved query.

## Permissions

- `notes.read`: open a note when you click a row.
- `notes.index`: run the task, note and tag queries.
- `ui.panel`: the Tasks panel.
- `ui`: prompts for saving a query, the picker, and messages.
- `storage`: keep your saved queries.

## Limits

- Up to 500 rows are fetched and the first 100 are shown, followed by a line such as "240 more not shown". The heading shows the real count, or "500+" when the fetch itself hit the cap. Narrow the filter to see the rest.
- The tag list is built from your 500 most recently changed notes and shows at most 100 tags.
- Ticking tasks from the panel is not supported (it would need whole-file writes).
- The panel reads the search index, so unsaved edits show up after the next autosave.
- If the index is not available the panel says so; this is not counted as a plugin failure.
