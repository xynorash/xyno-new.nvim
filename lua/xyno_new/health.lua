-- :checkhealth xyno_new
local M = {}

function M.check()
  local h = vim.health
  h.start("xyno-new")
  if vim.fn.has("nvim-0.12") == 1 then
    h.ok("Neovim " .. tostring(vim.version()))
  else
    h.error("Neovim 0.12 or newer is required")
  end
  for _, mod in ipairs({ "xyno_rust.rust_context", "xyno_rust.fsutil" }) do
    if pcall(require, mod) then
      h.ok(mod .. " (xyno-rust.nvim)")
    else
      h.error(mod .. " not found", { "install xynorash/xyno-rust.nvim" })
    end
  end
  for _, t in ipairs({
    { "cargo", "error", "RustNew* run `cargo new`" },
    { "git", "warn", "no repository is created for a new workspace without it" },
    { "curl", "warn", ":EguiNew downloads the template with curl" },
    { "unzip", "warn", ":EguiNew unpacks the template with unzip (tar on Windows)" },
  }) do
    if vim.fn.executable(t[1]) == 1 then
      h.ok(t[1] .. " found")
    elseif t[1] == "unzip" and vim.fn.has("win32") == 1 and vim.fn.executable("tar") == 1 then
      h.ok("tar found (reads ZIP files on Windows)")
    else
      h[t[2]](t[1] .. " not found: " .. t[3])
    end
  end

  h.start("xyno-new: the egui template")
  local E = require("xyno_new.egui")
  local c, err = E.config()
  if not c then
    return h.error("template configuration: " .. tostring(err))
  end
  h.info("source: " .. c.url)
  if c.pinned then
    h.ok(("pinned to commit %s (%s): the project does not change under you"):format(E.PINNED_REF:sub(1, 7), E.PINNED_DATE))
  elseif c.ref:match("^%x+$") and #c.ref >= 7 then
    h.ok("pinned to the commit " .. c.ref:sub(1, 12) .. " (your setting)")
  else
    h.warn(("ref `%s` is a branch or tag name: it can move, and the template may then not match what this plugin was tested with"):format(c.ref), {
      "leave egui_template.ref unset for the pinned commit",
    })
  end
  if c.scheme == "https" then
    h.ok("https:// base URL")
  else
    h.warn(c.scheme .. ":// base URL accepted through allow_insecure = true", { "use an https:// mirror, or a local path only for testing" })
  end
  local dir = vim.fn.stdpath("cache") .. "/xyno-new"
  h.info("download cache: " .. dir .. (vim.uv.fs_stat(dir .. "/egui-template.zip") and " (a template is cached for offline use)" or " (empty)"))
end

return M
