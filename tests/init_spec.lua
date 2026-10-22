-- xyno_new.setup(): commands, keymaps, options, and the check for xyno-rust.nvim.
local H = require("xyno_new_test.helpers")
local N = require("xyno_new")

local COMMANDS = { "RustNewBin", "RustNewLib", "RustNewWorkspace", "RustNewMember", "EguiNew" }

local saved = {}
before_each(function()
  for _, k in ipairs({ "xyno_new_projects_dir", "xyno_new_egui_template", "xyno_new_egui_build_after_new" }) do
    saved[k] = vim.g[k]
    vim.g[k] = nil
  end
  for _, c in ipairs(COMMANDS) do
    pcall(vim.api.nvim_del_user_command, c)
  end
end)

after_each(function()
  for k, v in pairs(saved) do
    vim.g[k] = v
  end
  for _, c in ipairs(COMMANDS) do
    pcall(vim.api.nvim_del_user_command, c)
  end
  for _, lhs in pairs(N.default_keymaps) do
    pcall(vim.keymap.del, "n", lhs)
  end
end)

describe("setup", function()
  it("defines every command and sets no keymap", function()
    H.ok(N.setup())
    for _, c in ipairs(COMMANDS) do
      H.eq(2, vim.fn.exists(":" .. c), c)
    end
    for _, lhs in pairs(N.default_keymaps) do
      H.eq("", vim.fn.maparg(lhs, "n"), lhs)
    end
  end)

  it("commands = false defines none", function()
    H.ok(N.setup({ commands = false }))
    for _, c in ipairs(COMMANDS) do
      H.eq(0, vim.fn.exists(":" .. c), c)
    end
  end)

  it("keymaps = true maps the defaults, a table only the listed ones, false skips one", function()
    N.setup({ keymaps = true })
    for name, lhs in pairs(N.default_keymaps) do
      H.ok(vim.fn.maparg(lhs, "n") ~= "", name)
    end
    H.has(vim.fn.maparg(N.default_keymaps.bin, "n"), "RustNewBin")
    for _, lhs in pairs(N.default_keymaps) do
      pcall(vim.keymap.del, "n", lhs)
    end
    N.setup({ keymaps = { bin = "<leader>zb", lib = false } })
    H.has(vim.fn.maparg("<leader>zb", "n"), "RustNewBin")
    H.eq("", vim.fn.maparg(N.default_keymaps.lib, "n"))
    H.eq("", vim.fn.maparg(N.default_keymaps.egui, "n"))
    pcall(vim.keymap.del, "n", "<leader>zb")
  end)

  it("the options set the variables the modules read", function()
    N.setup({ projects_dir = "/some/where", egui_build_after_new = true, egui_template = { ref = "v1" } })
    H.eq("/some/where", vim.g.xyno_new_projects_dir)
    H.eq(true, vim.g.xyno_new_egui_build_after_new)
    H.eq({ ref = "v1" }, vim.g.xyno_new_egui_template)
    H.eq("/some/where", require("xyno_new.egui").default_parent())
  end)

  it("without options the variables stay as they are", function()
    vim.g.xyno_new_projects_dir = "/mine"
    N.setup({})
    H.eq("/mine", vim.g.xyno_new_projects_dir)
  end)

  it("is safe to call twice", function()
    H.ok(N.setup())
    H.ok(N.setup())
    H.eq(2, vim.fn.exists(":RustNewBin"))
  end)
end)

describe("xyno-rust.nvim missing", function()
  it("one error notification, no Lua error, no commands", function()
    local hidden = {}
    for _, m in ipairs({ "xyno_rust.rust_context", "xyno_rust.fsutil" }) do
      hidden[m] = package.loaded[m]
      package.loaded[m] = nil
    end
    -- LuaJIT's package.loaders: only a loader that refuses xyno_rust is left
    local saved_loaders = {}
    for i, f in ipairs(package.loaders) do
      saved_loaders[i] = f
    end
    local n = #package.loaders
    package.loaders[1] = function(name)
      if name:match("^xyno_rust") then
        return "\n\tno module '" .. name .. "'"
      end
    end
    for i = 2, n do
      package.loaders[i] = nil
    end
    package.loaders[2] = function(name)
      if not name:match("^xyno_rust") then
        for _, f in ipairs(saved_loaders) do
          local r = f(name)
          if type(r) == "function" then
            return r
          end
        end
      end
      return "\n\tno module"
    end
    local cap = H.capture_notify()
    local ok, res = pcall(N.setup)
    for i = 1, n do
      package.loaders[i] = saved_loaders[i]
    end
    for m, v in pairs(hidden) do
      package.loaded[m] = v
    end
    H.ok(ok, "setup() must not raise")
    H.eq(false, res)
    H.eq(1, #cap.list, "exactly one notification")
    H.has(cap.list[1].msg, "xyno-rust.nvim")
    H.not_ok(cap.list[1].msg:find("\n", 1, true), "one line")
    H.eq(vim.log.levels.ERROR, cap.list[1].level)
    for _, c in ipairs(COMMANDS) do
      H.eq(0, vim.fn.exists(":" .. c), c)
    end
  end)
end)
