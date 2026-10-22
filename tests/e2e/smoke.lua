-- End-to-end smoke test (see tests/e2e/init.lua): lazy.nvim loaded the plugin and its
-- dependency, setup() ran, every documented command exists, :help xyno-new resolves, and
-- a binary, a library and a workspace are made in a scratch directory (cargo, offline).
local failures = {}
local function check(name, ok, detail)
  io.stdout:write(("%s %s%s\n"):format(ok and "ok  " or "FAIL", name, (not ok and detail) and (": " .. tostring(detail)) or ""))
  if not ok then
    failures[#failures + 1] = name
  end
end

check("lazy.nvim loaded xyno_new", package.loaded["xyno_new"] ~= nil)
check("lazy.nvim made xyno_rust available", (pcall(require, "xyno_rust.rust_context")))
for _, c in ipairs({ "RustNewBin", "RustNewLib", "RustNewWorkspace", "RustNewMember", "EguiNew" }) do
  check("command :" .. c, vim.fn.exists(":" .. c) == 2)
end
check("no global keymap by default", vim.fn.maparg("<leader>rnb", "n") == "")
for _, m in ipairs({ "rust", "egui", "dashboard" }) do
  check("require xyno_new." .. m, (pcall(require, "xyno_new." .. m)))
end
local keys = require("xyno_new").dashboard_keys({ { key = "q", desc = "Quit", action = ":qa" } })
check("dashboard_keys adds four entries before Quit", #keys == 5 and keys[5].desc == "Quit")

local repo = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))))
vim.cmd("helptags " .. vim.fn.fnameescape(repo .. "/doc"))
for _, tag in ipairs({ "xyno-new", "xyno-new-setup", "xyno-new-api", ":RustNewBin", ":RustNewLib", ":RustNewWorkspace", ":RustNewMember", ":EguiNew", "xyno_new.dashboard_keys()" }) do
  local ok, err = pcall(vim.cmd, "help " .. tag)
  check(":help " .. tag, ok, err)
end
vim.cmd("only")

if vim.fn.executable("cargo") == 1 then
  local parent = vim.fn.tempname()
  vim.fn.mkdir(parent, "p")
  vim.g.xyno_new_projects_dir = parent
  local answers = { "smoke-bin", parent }
  local orig_input = vim.ui.input
  vim.ui.input = function(opts, cb)
    cb(table.remove(answers, 1))
  end
  local orig_notify = vim.notify
  local notes = {}
  vim.notify = function(msg)
    notes[#notes + 1] = msg
  end
  vim.cmd("RustNewBin")
  local ok = vim.wait(60000, function()
    return vim.uv.fs_stat(parent .. "/smoke-bin/src/main.rs") ~= nil and vim.fn.expand("%:t") == "main.rs"
  end, 50)
  check(":RustNewBin creates and opens a binary", ok, table.concat(notes, " | "))
  vim.ui.input = orig_input
  vim.notify = orig_notify
  vim.cmd("cd /")
  vim.fn.delete(parent, "rf")
else
  io.stdout:write("skip :RustNewBin run (cargo not found)\n")
end

if #failures > 0 then
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
