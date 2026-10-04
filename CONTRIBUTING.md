# Contributing a plugin

## Layout

Each plugin is one folder at the top of the repository:

    my-plugin/
      plugin.json   manifest
      main.lua      entry point (the name is set by `entry`)
      README.md     what it does and why it needs each permission

`hyprnotes --new-plugin NAME` creates a working folder, and `hyprnotes --check-plugin DIR` validates it exactly as the installer does.

## plugin.json

Required: `id`, `name`, `version` (`MAJOR.MINOR.PATCH`, optional `-suffix`), `author`, `description`, `api` (1 or 2), `tier` (`script`), `entry`, `permissions`, `min_app`. Add `net_hosts` if you request the `network` permission. `tags` is an optional list of up to 8 short words (24 characters each) used for display in Browse; they are not verified.

Request only the permissions the plugin needs.

## Releasing a change

1. Bump `version` in `plugin.json` for every change, however small. A released version is never rebuilt; the script refuses to publish different content under a version already listed in `index.json`.
2. Run `tools/build-registry.sh` (set `HYPRNOTES` to the binary if it is not on your PATH). It checks and packs each plugin into `dist/` and rewrites `index.json`. It prints any permissions added or removed compared with the previous version.
3. Attach `dist/<id>-<version>.hnplugin` to a release tagged `<id>-<version>` and commit `index.json`.

## Review

Review is a human check of the code, the README and the permission list. It is not a security audit, and plugins in the marketplace are third-party code. A version bump that adds permissions is looked at again for that reason. Users still review and grant permissions themselves before a plugin is enabled.

## Native plugins

Native plugins (such as `hyprnotes-markdown-extras`) have their own build and release path and are not built by `tools/build-registry.sh`. They cannot be installed from the in-app Browse tab until package signing exists.
