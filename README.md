# Hyprnotes plugins

The plugins maintained for [Hyprnotes](../hyprnotes). Each subfolder is one complete plugin (a `plugin.json` manifest, a `main.lua` entry point and a README) that uses the same plugin API as any third-party plugin, with only the permissions its manifest lists. This repository is the source for the future plugin marketplace.

- `slash-menu`: type `/` at the start of a line to insert headings, lists, tasks, quotes, code blocks, dividers, tables, the date or a note link.
- `journal`: daily notes and Markdown templates (today, previous and next day, new note from a template).
- `tasks`: a side panel with open tasks, recent notes, notes by tag and saved one-line queries.
- `wiki-links`: `[[` completion with aliases and headings, create-on-click for missing notes, and a Links panel with backlinks.

They are not bundled in the Hyprnotes application package. Until the marketplace exists you can install one straight from its folder:

    hyprnotes --install-plugin <id>

To build a distributable package from a folder:

    hyprnotes --pack-plugin <id>

Installing a plugin does not enable it. You review and grant its permissions first, as with every other plugin.

## Tests

The plugins are tested from the Hyprnotes repository (`tests/unit/plugins_official_test.cpp` and two tests in `app_plugins_test.cpp`), which runs them against the real plugin host. By default Hyprnotes looks for this repository next to itself (`../hyprnotes-plugins`); pass `-DHN_PLUGINS_DIR=/path/to/hyprnotes-plugins` to CMake to use another location. Without it those tests are skipped.
