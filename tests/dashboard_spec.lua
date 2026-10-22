-- xyno_new.dashboard / xyno_new.dashboard_keys: the opt-in entries for the preset keys of
-- snacks.nvim's dashboard (pure list manipulation, no snacks needed).
local H = require("xyno_new_test.helpers")
local N = require("xyno_new")

local function stock()
  return {
    { icon = "s1", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
    { icon = "s2", key = "n", desc = "New File", action = ":ene | startinsert" },
    { icon = "s3", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
    { icon = "s4", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
    { icon = "s5", key = "L", desc = "Lazy", action = ":Lazy" },
    { icon = "s6", key = "q", desc = "Quit", action = ":qa" },
  }
end

local WANT = {
  { "b", "New Rust Binary", ":RustNewBin" },
  { "i", "New Rust Library", ":RustNewLib" },
  { "w", "New Rust Workspace", ":RustNewWorkspace" },
}

local function positions(keys)
  local pos = {}
  for i, k in ipairs(keys) do
    pos[k.desc] = i
  end
  return pos
end

describe("dashboard_keys", function()
  it("three Rust entries and the egui entry: unique keys, distinct icons, in order, before Quit", function()
    local keys = N.dashboard_keys(stock())
    local seen, icons = {}, {}
    for _, k in ipairs(keys) do
      H.is_nil(seen[k.key], "duplicate dashboard key " .. tostring(k.key))
      seen[k.key] = true
      H.is_nil(icons[k.icon or ""], "duplicate icon for " .. tostring(k.desc))
      icons[k.icon or ""] = true
    end
    local pos = positions(keys)
    for n, w in ipairs(WANT) do
      local i = H.ok(pos[w[2]], w[2] .. " is in the list")
      H.eq(w[1], keys[i].key)
      H.eq(w[3], keys[i].action)
      H.ok(keys[i].icon and #keys[i].icon > 0)
      if n > 1 then
        H.eq(pos[WANT[n - 1][2]] + 1, i, "the three are consecutive")
      end
    end
    H.eq("e", keys[pos["New egui Project"]].key)
    H.eq(":EguiNew", keys[pos["New egui Project"]].action)
    H.eq(pos["New Rust Workspace"] + 1, pos["New egui Project"], "the egui entry follows the three")
    H.eq(pos["Quit"] - 1, pos["New egui Project"], "the egui entry stays right before Quit")
    H.eq(10, #keys)
  end)

  it("the existing entries are unchanged and keep their order", function()
    local keys = N.dashboard_keys(stock())
    local order = {}
    for _, k in ipairs(keys) do
      order[#order + 1] = k.key
    end
    H.eq({ "f", "n", "g", "r", "L", "b", "i", "w", "e", "q" }, order)
  end)

  it("is idempotent", function()
    local keys = N.dashboard_keys(stock())
    local again = N.dashboard_keys(vim.deepcopy(keys))
    H.eq(keys, again)
    H.eq(keys, N.dashboard_keys(keys))
  end)

  it("edits the list in place and returns it", function()
    local keys = stock()
    H.ok(N.dashboard_keys(keys) == keys)
    H.eq(10, #keys)
  end)

  it("without Quit the entries go last; without an argument a new list comes back", function()
    local keys = N.dashboard_keys({ { key = "f", desc = "Find File", action = ":x" } })
    H.eq({ "f", "b", "i", "w", "e" }, vim.tbl_map(function(k)
      return k.key
    end, keys))
    local fresh = N.dashboard_keys()
    H.eq(4, #fresh)
  end)

  it("a key `e` already in use is respected: no egui entry, the Rust entries stay", function()
    local keys = stock()
    table.insert(keys, 1, { key = "e", desc = "Explorer", action = ":Ex" })
    N.dashboard_keys(keys)
    local pos = positions(keys)
    H.is_nil(pos["New egui Project"])
    H.ok(pos["New Rust Binary"])
    H.eq(pos["Quit"] - 3, pos["New Rust Binary"])
  end)

  it("the entries do not alias the module tables", function()
    local keys = N.dashboard_keys(stock())
    keys[6].desc = "changed"
    H.eq("New Rust Binary", require("xyno_new.dashboard").rust_entries[1].desc)
  end)
end)
