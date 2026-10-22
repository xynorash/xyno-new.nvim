-- Minimal init for the end-to-end smoke test: lazy.nvim loads this checkout and its one
-- dependency, xyno-rust.nvim, through `dir =` and calls setup().
-- XYNO_LAZY: path of a lazy.nvim clone; XYNO_RUST: path of an xyno-rust.nvim checkout.
-- Run:  XYNO_LAZY=... XYNO_RUST=... nvim --headless -u tests/e2e/init.lua -c "luafile tests/e2e/smoke.lua"
local repo = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))))
vim.o.swapfile = false
vim.opt.rtp:prepend(assert(vim.env.XYNO_LAZY, "XYNO_LAZY not set"))
require("lazy").setup({
  {
    dir = assert(vim.env.XYNO_RUST, "XYNO_RUST not set"),
    name = "xyno-rust.nvim",
    lazy = true,
  },
  {
    dir = repo,
    name = "xyno-new.nvim",
    dependencies = { "xyno-rust.nvim" },
    lazy = false,
    opts = {},
    main = "xyno_new",
  },
}, {
  install = { missing = false },
  checker = { enabled = false },
  change_detection = { enabled = false },
  performance = { reset_packpath = false, rtp = { reset = false } },
})
