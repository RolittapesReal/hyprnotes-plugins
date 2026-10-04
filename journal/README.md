# Journal and Templates

Daily notes and Markdown templates.

## Commands

- `journal:today` opens today's daily note, creating it first if it does not exist. An existing note is never overwritten.
- `journal:previous-day` and `journal:next-day` step from the open daily note to the neighbouring day (created if missing). If the open note is not a daily note, they step relative to today.
- `journal:new-from-template` asks for a template and a title, creates the note and opens it.
- `journal:insert-template` inserts a template into the open note.

There is also a toolbar button, Today, which does the same as `journal:today`.

## Templates

Templates are plain Markdown notes in the templates folder of your library (default `templates`). Only `.md` files directly in that folder count; files in sub-folders are not used. At most 100 templates are listed. Variables are replaced when a template is used:

- `{{date}}` as `YYYY-MM-DD`
- `{{time}}` as `HH:MM`
- `{{weekday}}` as the weekday name
- `{{title}}` as the title of the new or open note

Unknown names such as `{{foo}}` are left as they are. If the folder has no templates, the commands say so and write nothing.

## Settings

- `daily_folder` (default `daily`): folder for daily notes.
- `date_format` (default `%Y-%m-%d`): strftime format of the file name, without `.md`.
- `templates_folder` (default `templates`): folder with templates.
- `daily_template` (default empty): a file inside the templates folder used for new daily notes. Empty means a built-in Plan and Notes layout.

## Permissions

- `notes.read`: read template files.
- `notes.index`: check whether a note exists (a failed read is not proof that it does not, and the index can lag behind the disk, so the plugin asks the index and then checks the file's front matter) and list the templates. If the index is not available the plugin says so and creates nothing.
- `notes.write`: create daily notes and notes from templates. This is a dangerous permission; the plugin only creates new notes and never overwrites an existing one.
- `note.read`: the open note's path and title.
- `note.edit`: insert a template into the open note.
- `ui`: pick a template, ask for a title, show messages.

## Limits and edge cases

`journal:previous-day` and `journal:next-day` recognise the open note as a daily note only when its file name ends in a `YYYY-MM-DD` date and it sits inside the daily folder. With another `date_format` (for example `%d-%m-%Y`) the open note is not recognised and the commands step from today instead. Both commands create the target note if it is missing. Daily notes and template notes expand `{{date}}`, `{{time}}`, `{{title}}` and `{{weekday}}`; for a daily note `{{date}}` and `{{weekday}}` describe that day, while `{{time}}` is the current time.

If a setting produces an invalid note path (for example a `date_format` such as `../%Y`, a leading `/`, a backslash, control characters, or non-ASCII characters in the format), the plugin shows a message and does nothing.
