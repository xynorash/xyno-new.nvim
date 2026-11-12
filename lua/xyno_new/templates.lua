-- Project templates (the useful part of cargo-generate, without its script engine): a picker over a PINNED
-- list of templates, each a directory (local `path`) or a git repository at an exact commit (`git` + `rev`,
-- 40 hex digits, cloned without hooks and checked out detached).
--
--   :RustNewFrom [template-name]
--
--   require("xyno_new").setup({ templates = {
--     { name = "axum service", path = "~/templates/axum", description = "axum + tracing" },
--     { name = "cli", git = "https://github.com/me/cli-template", rev = "0123...(40 hex)" },
--   } })
--
-- The built-in kinds (binary, library, workspace, member, egui) are listed first; they run the existing
-- commands. A template is copied as it is, with three placeholders replaced in text files AND in file
-- names: {{name}} (the package name), {{crate_name}} (name with '-' as '_'), {{title}} (name as Title Case).
-- Nothing is executed: a template that carries cargo-generate hooks / scripts (a `cargo-generate.toml`
-- with [hooks] or any .rhai file) is REFUSED, because running it would be running unreviewed code.
-- Symbolic links are refused; `.git`, `target` and `cargo-generate.toml` are not copied; binary files
-- (a NUL byte in the first 8 KiB) are copied untouched.
local R = require("xyno_new.rust")
local E = require("xyno_new.egui")

local M = {}

M.MAX_FILES = 2000
M.MAX_BYTES = 32 * 1024 * 1024

local SKIP = { [".git"] = true, ["target"] = true, ["cargo-generate.toml"] = true }

--- Validate the `templates` option. Returns the clean list and a list of problems.
function M.validate(list)
  local out, bad = {}, {}
  if list == nil then
    return out, bad
  end
  if type(list) ~= "table" then
    return out, { "templates must be a list" }
  end
  local seen = {}
  for i, t in ipairs(list) do
    local where = ("templates[%d]"):format(i)
    if type(t) ~= "table" or type(t.name) ~= "string" or vim.trim(t.name) == "" then
      bad[#bad + 1] = where .. " needs a name"
    elseif seen[t.name] then
      bad[#bad + 1] = where .. (" name %q is used twice"):format(t.name)
    elseif (t.path == nil) == (t.git == nil) then
      bad[#bad + 1] = where .. " needs exactly one of `path` or `git`"
    elseif t.path ~= nil and type(t.path) ~= "string" then
      bad[#bad + 1] = where .. ".path must be a string"
    elseif
      t.git ~= nil and (type(t.git) ~= "string" or type(t.rev) ~= "string" or not t.rev:match("^%x+$") or #t.rev ~= 40)
    then
      bad[#bad + 1] = where .. " git templates need `rev` = a full 40-hex commit (a branch name can move)"
    elseif
      t.git
      and not (
        t.git:match("^https://")
        or t.git:match("^ssh://")
        or t.git:match("^git@")
        or t.git:match("^file://")
        or t.git:match("^/")
      )
    then
      bad[#bad + 1] = where .. ".git must be an https://, ssh://, git@ or local address"
    else
      seen[t.name] = true
      out[#out + 1] = {
        name = t.name,
        path = t.path,
        git = t.git,
        rev = t.rev,
        description = type(t.description) == "string" and t.description or nil,
      }
    end
  end
  return out, bad
end

M.list = {}

function M.set(list)
  M.list = list or {}
end

local function title_of(name)
  local words = {}
  for w in name:gmatch("[^%-_]+") do
    words[#words + 1] = w:sub(1, 1):upper() .. w:sub(2)
  end
  return table.concat(words, " ")
end

--- Replace the three placeholders.
function M.fill(text, name)
  local crate = name:gsub("%-", "_")
  return (
    text
      :gsub("{{%s*name%s*}}", function()
        return name
      end)
      :gsub("{{%s*crate_name%s*}}", function()
        return crate
      end)
      :gsub("{{%s*title%s*}}", function()
        return title_of(name)
      end)
  )
end

--- Walk a template directory. Returns the list of { rel, abs } files, or nil and the reason it is refused.
function M.scan(root)
  local files, total = {}, 0
  local function walk(dir, rel)
    for name, typ in vim.fs.dir(dir) do
      if not (rel == "" and SKIP[name]) and not (rel ~= "" and (name == ".git" or name == "target")) then
        local abs = dir .. "/" .. name
        local r = rel == "" and name or (rel .. "/" .. name)
        local st = vim.uv.fs_lstat(abs)
        if not st then
          return nil, "cannot read " .. r
        end
        if st.type == "link" then
          return nil, "contains a symbolic link: " .. r
        elseif st.type == "directory" then
          local ok, why = walk(abs, r)
          if not ok then
            return nil, why
          end
        elseif st.type == "file" then
          if name:match("%.rhai$") then
            return nil, "contains a script (" .. r .. "): templates are copied, never executed"
          end
          total = total + st.size
          files[#files + 1] = { rel = r, abs = abs, size = st.size }
          if #files > M.MAX_FILES or total > M.MAX_BYTES then
            return nil,
              "is larger than the limit (" .. M.MAX_FILES .. " files, " .. math.floor(M.MAX_BYTES / 1048576) .. " MB)"
          end
        end
      end
    end
    return true
  end
  local cg = root .. "/cargo-generate.toml"
  if vim.uv.fs_stat(cg) then
    local fd = io.open(cg, "rb")
    local t = fd and fd:read(65536) or ""
    if fd then
      fd:close()
    end
    if t:find("%[hooks%]") or t:find("pre%-?hook") or t:find("post%-?hook") then
      return nil, "carries cargo-generate hooks: templates are copied, never executed"
    end
  end
  local ok, why = walk(root, "")
  if not ok then
    return nil, why
  end
  table.sort(files, function(a, b)
    return a.rel < b.rel
  end)
  return files
end

--- Copy a template directory to `dest` (which must not exist). Returns true or nil, reason.
function M.copy(src, dest, name)
  local files, why = M.scan(src)
  if not files then
    return nil, why
  end
  if #files == 0 then
    return nil, "is empty"
  end
  if vim.uv.fs_stat(dest) then
    return nil, dest .. " exists already"
  end
  local made = {}
  local function fail(msg)
    vim.fn.delete(dest, "rf")
    return nil, msg
  end
  vim.fn.mkdir(dest, "p")
  for _, f in ipairs(files) do
    local rel = M.fill(f.rel, name)
    if rel:find("%.%.") or rel:sub(1, 1) == "/" then
      return fail("a file name expands to a path outside the project: " .. f.rel)
    end
    local target = dest .. "/" .. rel
    vim.fn.mkdir(vim.fs.dirname(target), "p")
    local fd = io.open(f.abs, "rb")
    if not fd then
      return fail("cannot read " .. f.rel)
    end
    local data = fd:read("*a")
    fd:close()
    if not data:sub(1, 8192):find("\0", 1, true) then
      data = M.fill(data, name)
    end
    local out, err = io.open(target, "wb")
    if not out then
      return fail(tostring(err))
    end
    out:write(data)
    out:close()
    vim.uv.fs_chmod(target, vim.uv.fs_stat(f.abs).mode % 4096)
    made[#made + 1] = rel
  end
  return made
end

--- Clone a pinned git template into a temp directory; cb(dir, err). The caller deletes dir.
function M.fetch(t, cb)
  local tmp = vim.fn.tempname()
  local function run(argv, nxt)
    vim.system(argv, { text = true, timeout = 120000, env = { GIT_TERMINAL_PROMPT = "0" } }, function(r)
      vim.schedule(function()
        if r.code ~= 0 then
          vim.fn.delete(tmp, "rf")
          return cb(nil, "git: " .. vim.trim((r.stderr or ""):match("[^\n]+") or "failed"))
        end
        nxt()
      end)
    end)
  end
  run({
    "git",
    "-c",
    "core.hooksPath=/dev/null",
    "-c",
    "protocol.ext.allow=never",
    "clone",
    "--no-checkout",
    "--quiet",
    "--",
    t.git,
    tmp,
  }, function()
    run({ "git", "-C", tmp, "-c", "advice.detachedHead=false", "checkout", "--quiet", t.rev }, function()
      cb(tmp)
    end)
  end)
end

local function expand(p)
  return vim.fs.normalize(vim.fn.expand(p))
end

--- Create `name` under `parent` from template `t`; cb(err, dir).
function M.create(t, name, parent, cb)
  local dest = vim.fs.normalize(parent) .. "/" .. name
  local function from(src, cleanup)
    local made, why = M.copy(src, dest, name)
    if cleanup then
      vim.fn.delete(src, "rf")
    end
    if not made then
      return cb(("template %q %s"):format(t.name, why))
    end
    cb(nil, dest, made)
  end
  if t.path then
    local src = expand(t.path)
    if vim.fn.isdirectory(src) ~= 1 then
      return cb(("template %q: %s is not a directory"):format(t.name, src))
    end
    return from(src, false)
  end
  M.fetch(t, function(dir, err)
    if not dir then
      return cb(("template %q: %s"):format(t.name, err))
    end
    from(dir, true)
  end)
end

local BUILTIN = {
  {
    name = "binary",
    desc = "cargo new --bin",
    run = function()
      R.new_project("binary")
    end,
  },
  {
    name = "library",
    desc = "cargo new --lib",
    run = function()
      R.new_project("library")
    end,
  },
  {
    name = "workspace",
    desc = "workspace with a first member",
    run = function()
      R.new_workspace()
    end,
  },
  {
    name = "member",
    desc = "member crate in this workspace",
    run = function()
      R.new_member()
    end,
  },
  {
    name = "egui",
    desc = "eframe template (pinned)",
    run = function()
      vim.cmd("EguiNew")
    end,
  },
}

function M.entries()
  local out = {}
  for _, b in ipairs(BUILTIN) do
    out[#out + 1] = { label = b.name, desc = b.desc .. " [built in]", builtin = b }
  end
  for _, t in ipairs(M.list) do
    local where = t.path and ("path " .. t.path) or ("git " .. t.git .. " @ " .. t.rev:sub(1, 8))
    out[#out + 1] = { label = t.name, desc = (t.description and (t.description .. "; ") or "") .. where, template = t }
  end
  return out
end

local function ask(prompt, default, check, cb)
  vim.ui.input({ prompt = prompt, default = default }, function(v)
    if not v then
      return
    end
    local ok, why = check(v)
    if not ok then
      vim.notify("xyno-new: " .. why, vim.log.levels.WARN)
      return ask(prompt, v, check, cb)
    end
    cb(ok)
  end)
end

local function start(t, name_arg)
  local function with_name(name)
    ask("Parent directory: ", E.default_parent(), function(p)
      p = expand(p)
      if vim.fn.isdirectory(p) ~= 1 then
        return nil, p .. " is not a directory"
      end
      if vim.uv.fs_stat(p .. "/" .. name) then
        return nil, p .. "/" .. name .. " exists already"
      end
      return p
    end, function(parent)
      M.create(t, name, parent, function(err, dir)
        if err then
          return vim.notify("xyno-new: " .. err, vim.log.levels.ERROR)
        end
        vim.cmd("cd " .. vim.fn.fnameescape(dir))
        for _, f in ipairs({ "src/main.rs", "src/lib.rs", "README.md", "Cargo.toml" }) do
          if vim.uv.fs_stat(dir .. "/" .. f) then
            vim.cmd.edit(vim.fn.fnameescape(dir .. "/" .. f))
            break
          end
        end
        vim.notify(("xyno-new: created %s from template %q"):format(dir, t.name))
      end)
    end)
  end
  if name_arg and name_arg ~= "" and R.name(name_arg) then
    return with_name((R.name(name_arg)))
  end
  ask("Project name: ", name_arg, function(v)
    local n, why = R.name(v)
    if not n then
      return nil, why
    end
    return n
  end, with_name)
end
M._start = start

--- :RustNewFrom [name]
function M.pick(name)
  local entries = M.entries()
  local function go(e)
    if not e then
      return
    end
    if e.builtin then
      return e.builtin.run()
    end
    start(e.template)
  end
  if name and name ~= "" then
    for _, e in ipairs(entries) do
      if e.label == name then
        return go(e)
      end
    end
    return vim.notify(("xyno-new: no template %q (:RustNewFrom lists them)"):format(name), vim.log.levels.WARN)
  end
  vim.ui.select(entries, {
    prompt = "New project from template",
    format_item = function(e)
      return ("%-16s %s"):format(e.label, e.desc)
    end,
  }, go)
end

function M.setup()
  vim.api.nvim_create_user_command("RustNewFrom", function(a)
    M.pick(a.args)
  end, {
    nargs = "?",
    complete = function(lead)
      return vim.tbl_filter(
        function(l)
          return l:find(lead, 1, true) == 1
        end,
        vim.tbl_map(function(e)
          return e.label
        end, M.entries())
      )
    end,
    desc = "New project from a pinned template (built-in kinds and your template list)",
  })
end

return M
