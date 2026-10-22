-- xyno-new.nvim: new Rust projects from inside Neovim. setup() defines the commands
-- (xyno_new.rust: :RustNewBin :RustNewLib :RustNewWorkspace :RustNewMember, xyno_new.egui:
-- :EguiNew); every module can also be required on its own. dashboard_keys() adds the
-- entries to the preset keys of snacks.nvim's dashboard (opt-in, see xyno_new.dashboard).
local M = {}

M.defaults = {
  commands = true, -- :RustNewBin :RustNewLib :RustNewWorkspace :RustNewMember :EguiNew
  keymaps = false, -- false | true | { bin = lhs, lib = lhs, ... } (global, normal mode)
  projects_dir = nil, -- parent directory offered by the prompts (default ~/projects if it exists, else the cwd)
  egui_template = nil, -- { repo = "emilk/eframe_template", ref = "main", base_url = "https://github.com" }
  egui_build_after_new = nil, -- true: run `cargo build` in a snacks terminal after :EguiNew
}

--- Default keys of `keymaps = true`. An entry set to false in a table is skipped.
M.default_keymaps = {
  bin = "<leader>rnb",
  lib = "<leader>rni",
  workspace = "<leader>rnw",
  member = "<leader>rnm",
  egui = "<leader>rne",
}

local ACTIONS = {
  bin = { "<cmd>RustNewBin<cr>", "New Rust binary" },
  lib = { "<cmd>RustNewLib<cr>", "New Rust library" },
  workspace = { "<cmd>RustNewWorkspace<cr>", "New Rust workspace" },
  member = { "<cmd>RustNewMember<cr>", "New member in this workspace" },
  egui = { "<cmd>EguiNew<cr>", "New egui project" },
}

--- Modules of the plugin this one needs (xyno-rust.nvim).
local REQUIRES = { "xyno_rust.rust_context", "xyno_rust.fsutil" }

--- Whether xyno-rust.nvim is there; says so in one line when it is not.
local function check_dependencies()
  for _, mod in ipairs(REQUIRES) do
    if not pcall(require, mod) then
      vim.notify(
        "xyno-new.nvim needs xyno-rust.nvim (github.com/xynorash/xyno-rust.nvim), which is not installed",
        vim.log.levels.ERROR,
        { title = "xyno-new" }
      )
      return false
    end
  end
  return true
end

--- Configure and start the plugin. Safe to call again. Returns false (after one error
--- notification, no Lua error) when xyno-rust.nvim is missing, or when Neovim is too old.
---@param opts? { commands?: boolean, keymaps?: boolean|table<string, string|false>, projects_dir?: string, egui_template?: table, egui_build_after_new?: boolean }
---@return boolean
function M.setup(opts)
  opts = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  if vim.fn.has("nvim-0.12") ~= 1 then
    vim.notify("xyno-new.nvim needs Neovim 0.12 or newer", vim.log.levels.ERROR, { title = "xyno-new" })
    return false
  end
  if not check_dependencies() then
    return false
  end
  if opts.projects_dir ~= nil then
    vim.g.xyno_new_projects_dir = opts.projects_dir
  end
  if opts.egui_template ~= nil then
    vim.g.xyno_new_egui_template = opts.egui_template
  end
  if opts.egui_build_after_new ~= nil then
    vim.g.xyno_new_egui_build_after_new = opts.egui_build_after_new
  end
  if opts.commands then
    require("xyno_new.rust").setup()
    require("xyno_new.egui").setup()
  end
  if opts.keymaps then
    local keys = opts.keymaps == true and M.default_keymaps or opts.keymaps
    for name, lhs in pairs(keys) do
      local action = ACTIONS[name]
      if action and type(lhs) == "string" then
        vim.keymap.set("n", lhs, action[1], { desc = action[2] })
      end
    end
  end
  return true
end

--- Add the dashboard entries to a snacks.nvim `dashboard.preset.keys` list (in place) and
--- return it; see xyno_new.dashboard. Calling it twice adds nothing twice.
---@param keys? table[]
---@return table[]
function M.dashboard_keys(keys)
  return require("xyno_new.dashboard").keys(keys)
end

return M
