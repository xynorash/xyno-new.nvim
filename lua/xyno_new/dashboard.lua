-- Entries for the preset keys of snacks.nvim's dashboard: "New Rust Binary" (b),
-- "New Rust Library" (i), "New Rust Workspace" (w) and "New egui Project" (e). Opt-in:
-- nothing calls this unless you do (xyno_new.dashboard_keys(keys)).
-- The stock keys of the LazyVim dashboard use f n p g r c s x l q; the four above are free.
-- "New egui Project" goes right before "Quit" (else last); the three Rust entries go right
-- before "New egui Project" (else before "Quit", else last).
local M = {}

M.rust_entries = {
  { icon = "\xef\x92\x89 ", key = "b", desc = "New Rust Binary", action = ":RustNewBin" },
  { icon = "\xef\x80\xaa ", key = "i", desc = "New Rust Library", action = ":RustNewLib" },
  { icon = "\xf3\xb0\x99\x85 ", key = "w", desc = "New Rust Workspace", action = ":RustNewWorkspace" },
}

M.egui_entry = { icon = "\xf3\xb0\x8f\x97 ", key = "e", desc = "New egui Project", action = ":EguiNew" }

local function add_egui(keys)
  for _, k in ipairs(keys) do
    if k.key == "e" then
      return
    end
  end
  local at = #keys + 1
  for i, k in ipairs(keys) do
    if k.desc == "Quit" then
      at = i
      break
    end
  end
  table.insert(keys, at, vim.deepcopy(M.egui_entry))
end

local function add_rust(keys)
  for _, k in ipairs(keys) do
    if k.action == ":RustNewBin" then
      return
    end
  end
  local at = #keys + 1
  for i, k in ipairs(keys) do
    if k.desc == "New egui Project" then
      at = i
      break
    elseif k.desc == "Quit" then
      at = i
    end
  end
  for n, e in ipairs(M.rust_entries) do
    table.insert(keys, at + n - 1, vim.deepcopy(e))
  end
end

--- Insert the entries into `keys` (a list of snacks dashboard keys; a new list when nil)
--- and return it. Idempotent.
---@param keys? table[]
---@return table[]
function M.keys(keys)
  keys = keys or {}
  add_egui(keys)
  add_rust(keys)
  return keys
end

return M
