# xyno-new.nvim

New Rust projects from inside Neovim: a binary, a library, a workspace (with the version and edition inherited from the workspace) or an egui app, each behind a few guarded prompts, plus optional entries for the snacks.nvim dashboard.

I use this in my own Rust setup, [xynovim](https://github.com/xynorash/xynovim), and pulled it out as a standalone plugin.

## Why

`cargo new` makes a binary or a library, but not a workspace, and starting a project means leaving the editor to find a directory, check the name rules and `cd`. This asks for the name and the parent directory, applies cargo's name rules before anything is created, builds the workspace layout cargo has no command for, leaves nothing behind when a step fails, and opens the new project's source file. `:EguiNew` starts from the current [eframe_template](https://github.com/emilk/eframe_template) instead of a stale copy.

## Requirements

- Neovim 0.12+
- [xyno-rust.nvim](https://github.com/xynorash/xyno-rust.nvim) (a required dependency: `xyno_rust.rust_context` finds the workspace for `:RustNewMember`, `xyno_rust.fsutil` is used for the nesting check). If it is missing, `setup()` prints one error line and defines nothing.
- `cargo` in `$PATH`
- `git` (optional): used for `git init -b main` in a workspace and for `:EguiNew`, and to prefill the author prompts. Without it those steps are skipped with a note.
- for `:EguiNew`: `curl` and `unzip` (on Windows `tar` instead of `unzip`), network access to github.com for the first download (the ZIP is cached, with its ETag, and used when offline), and `rustc` for the minimum-version warning
- optional: [snacks.nvim](https://github.com/folke/snacks.nvim) for the dashboard entries and for `egui_build_after_new`

## Install (lazy.nvim)

```lua
{
  "xynorash/xyno-new.nvim",
  dependencies = { "xynorash/xyno-rust.nvim" },
  cmd = { "RustNewBin", "RustNewLib", "RustNewWorkspace", "RustNewMember", "EguiNew" },
  opts = {},
  keys = {
    { "<leader>rnb", "<cmd>RustNewBin<cr>", desc = "New Rust binary" },
    { "<leader>rni", "<cmd>RustNewLib<cr>", desc = "New Rust library" },
    { "<leader>rnw", "<cmd>RustNewWorkspace<cr>", desc = "New Rust workspace" },
    { "<leader>rnm", "<cmd>RustNewMember<cr>", desc = "New member in this workspace" },
    { "<leader>rne", "<cmd>EguiNew<cr>", desc = "New egui project" },
  },
}
```

Because the commands are listed in `cmd`, lazy.nvim loads the plugin when you run one of them; `setup()` then defines them (the first run of a command through `cmd` is forwarded by lazy.nvim).

## Options

`require("xyno_new").setup(opts)`; the defaults:

```lua
{
  commands = true,             -- :RustNewBin :RustNewLib :RustNewWorkspace :RustNewMember :EguiNew
  keymaps = false,             -- false | true | { bin = lhs, lib = lhs, ... } (global, normal mode)
  projects_dir = nil,          -- parent directory offered by the prompts; nil: ~/projects if it exists, else the cwd
  egui_template = nil,         -- { repo = "emilk/eframe_template", ref = "main", base_url = "https://github.com" }
  egui_build_after_new = nil,  -- true: run `cargo build` in a snacks terminal after :EguiNew
}
```

`projects_dir`, `egui_template` and `egui_build_after_new` are stored in `vim.g.xyno_new_projects_dir`, `vim.g.xyno_new_egui_template` and `vim.g.xyno_new_egui_build_after_new`, which the modules read; you can set those variables directly instead. `egui_template.base_url` must be an `https://`, `http://` or `file://` URL (the file form is how the specs use a local fake template).

No global keymap is set by default. `keymaps = true` maps `<leader>rnb`, `rni`, `rnw`, `rnm`, `rne` (binary, library, workspace, member, egui). A table maps only the actions you list, to the keys you choose (`false` skips one).

## Commands

| Command | What it does |
| --- | --- |
| `:RustNewBin [name]` | `cargo new --bin --vcs git`: asks for the name (taken from the argument when it is valid) and the parent directory, then switches to the project and opens `src/main.rs`. |
| `:RustNewLib [name]` | The same with `--lib` and `src/lib.rs`. A name with hyphens shows the crate identifier it will have in Rust code. |
| `:RustNewWorkspace [name]` | Asks for the workspace name, the parent directory, the kind of the first member (binary or library) and its name. Writes `Cargo.toml` (`[workspace]` with `members = ["crates/*"]`, `[workspace.package]` with `version` and the edition your cargo uses for new projects, an empty `[workspace.dependencies]`), `.gitignore`, creates the first member with `cargo new --vcs none crates/<member>` so that its version and edition inherit from the workspace, and runs `git init -b main` (no commit). Asks first when the parent lies in another workspace's members or in a git work tree. |
| `:RustNewMember [name]` | Adds a binary or library crate to the workspace of the current buffer (or the cwd). It adds the path to an explicit `members` list, or relies on a glob. Refuses a name that clashes with an existing member (hyphen or underscore) or a directory that exists. |
| `:EguiNew [name]` | Downloads the current eframe_template as a ZIP (never a copy kept in the plugin), asks for the crate name, author name, author e-mail (both may be empty) and the parent directory, and personalises it the way the template's README and `fill_template.sh` describe: crate name, authors, window and page title, the web build file names in `assets/sw.js`. Nothing from the template is executed. The template's `rust-toolchain` file is never copied; its `rust-version` stays as the minimum, and a warning says when your `rustc` is older. |

A prompt that is cancelled ends the command silently, and a failed step removes what that run created. Only one project is created at a time.

## Dashboard entries (opt-in)

`require("xyno_new").dashboard_keys(keys)` inserts four entries into a list of snacks.nvim dashboard keys, in place, and returns it: `b` New Rust Binary, `i` New Rust Library, `w` New Rust Workspace, `e` New egui Project. The Rust three go right before the egui entry, which goes right before "Quit" (or last when there is none). Calling it twice adds nothing twice; an existing key `e` is respected. The key letters are free in LazyVim's stock dashboard (`f n p g r c s x l q` are taken). Nothing happens unless you call it:

```lua
{
  "folke/snacks.nvim",
  opts = function(_, opts)
    opts.dashboard = opts.dashboard or {}
    opts.dashboard.preset = opts.dashboard.preset or {}
    opts.dashboard.preset.keys = require("xyno_new").dashboard_keys(opts.dashboard.preset.keys or {})
  end,
}
```

The entries run `:RustNewBin` and the others, so the plugin has to be loaded when you press them: list the commands in `cmd` as above, or load it with `lazy = false`.

## Lua API

| Module | Public functions |
| --- | --- |
| `xyno_new` | `setup(opts)`, `dashboard_keys(keys?)`, `defaults`, `default_keymaps` |
| `xyno_new.rust` | `setup()`, `new_project(kind, name?)`, `new_workspace(name?)`, `new_member(name?)`, `running()`, the text functions `name`, `lib_note`, `first_line`, `parse_edition`, `resolver`, `workspace_toml`, `inherit`, `workspace_info`, `add_member_path`, `layout`, `nesting_warning`, and `cargo_edition()`, `reset_edition()`, `create_project(p, cb)`, `create_workspace(p, cb)`, `create_member(p, cb)` |
| `xyno_new.egui` | `setup()`, `new(name?)`, `create(p, cb)`, `validate_name`, `cargo_name`, `check_author`, `format_author`, `edit_cargo_toml`, `edit_cargo_lock`, `readme`, `config()`, `default_parent()`, `expand_dir(s)`, `parse_version`, `check_rust_version(dir, done?)` and the other pure text functions |
| `xyno_new.dashboard` | `keys(keys?)`, `rust_entries`, `egui_entry` |

`:help xyno-new-api` lists the main ones.

## How it works

Every external command is an argv list run asynchronously (a small coroutine helper around `vim.system`), so the editor stays responsive and nothing goes through a shell. The text edits (name rules, the workspace manifest, inheriting `version` and `edition`, adding a member path, personalising the template) are pure functions. The edition is read once per session from a throwaway `cargo new`, never hard-coded; the resolver is `3` for edition 2024 and newer, else `2`. A failed step restores or removes only what the run created.

## Platforms

- Linux: tested by the specs in this repository (`nvim -l tests/run.lua`) with a real cargo; the egui flow runs against a local fake template (file:// and a small http server inside the test Neovim), plus one test against the real template that skips without network.
- Windows: the Windows branches of the original code are kept (`tar` instead of `unzip`), but I have no evidence for them. In xynovim's CI the specs for this code were skipped whole on Windows.
- macOS: the specs carry the `linux,macos` header and ran there in xynovim's CI, whose macOS runs were not stable overall (one fully green run, others flaky or failed elsewhere), so I do not claim it works.
- The dashboard entries are a snacks.nvim feature; the rendering of the dashboard in a terminal (tmux) was checked by the original specs in xynovim's config, not by the specs here.

## Extracted from xynovim

These modules come from [xynovim](https://github.com/xynorash/xynovim), my Neovim configuration for Rust (`config.rust_new` and `config.egui_new`, and the two dashboard plugin specs). The code is the same apart from the namespace (`config.*` became `xyno_new.*` and `xyno_rust.*`), `setup()` taking options, the `vim.g.xynovim_*` variables now being `vim.g.xyno_new_*`, the dashboard code being the opt-in function `dashboard_keys()` instead of lazy.nvim plugin specs, the notification ids, cache directory and the user agent carrying this plugin's name, and the "next steps" hint naming `:RustTargets` instead of a key.

## Tests

```sh
nvim -l tests/run.lua                                   # specs, each file in its own headless nvim
XYNO_RUST=/path/to/xyno-rust.nvim nvim -l tests/run.lua # where xyno-rust.nvim is (default: a sibling directory)
XYNO_LAZY=/path/to/lazy.nvim XYNO_RUST=/path/to/xyno-rust.nvim nvim --headless -u tests/e2e/init.lua -c "luafile tests/e2e/smoke.lua"
```

Specs that need cargo, curl, unzip or python3 skip with a message when it is missing.

## License

MIT, Copyright (c) 2026 Xynorash.
