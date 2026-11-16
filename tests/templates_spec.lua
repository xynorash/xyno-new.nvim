-- xyno_new.templates: option validation, placeholder filling, the scan that refuses scripts / symlinks /
-- hooks, a real copy, a real pinned git template (a local repo; the rev must be the exact commit), and the
-- :RustNewFrom flow with a stubbed prompt.
-- xyno-os: linux,macos (git, symlinks)
local H = require("xyno_new_test.helpers")
local T = require("xyno_new.templates")
require("xyno_new").setup()

local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
end

local function make_template()
  local d = H.tmpdir()
  write(d .. "/Cargo.toml", '[package]\nname = "{{name}}"\nversion = "0.1.0"\nedition = "2021"\n')
  write(d .. "/src/main.rs", 'fn main() { println!("{{title}} / {{crate_name}}"); }\n')
  write(d .. "/{{name}}.md", "# {{name}}\n")
  write(d .. "/blob.bin", "\0{{name}}\0")
  write(d .. "/.git/config", "[core]\n")
  write(d .. "/target/x", "junk")
  write(d .. "/cargo-generate.toml", '[template]\ncargo_generate_version = ">=0.9"\n')
  return d
end

describe("validate", function()
  it("accepts path and pinned git entries", function()
    local rev = ("a"):rep(40)
    local list, bad = T.validate({
      { name = "a", path = "~/x", description = "d" },
      { name = "b", git = "https://example.org/t", rev = rev },
    })
    H.eq({}, bad)
    H.eq(2, #list)
  end)
  it("rejects a moving ref, both/neither source, duplicates, odd addresses", function()
    local _, bad = T.validate({
      { name = "a", git = "https://example.org/t", rev = "main" },
      { name = "b", path = "/x", git = "https://x/y", rev = ("a"):rep(40) },
      { name = "c" },
      { name = "d", path = "/x" },
      { name = "d", path = "/y" },
      { name = "e", git = "ext::sh -c id", rev = ("a"):rep(40) },
      "nope",
    })
    H.eq(6, #bad, vim.inspect(bad))
    H.match(bad[1], "40-hex", true)
    H.match(bad[5], "address", true)
  end)
end)

describe("fill / scan / copy", function()
  it("fills the three placeholders, with spaces inside the braces too", function()
    H.eq("my-app my_app My App", T.fill("{{name}} {{ crate_name }} {{title}}", "my-app"))
    H.eq("{{other}}", T.fill("{{other}}", "x"))
  end)

  it(
    "copies text with placeholders replaced, file names too, skips .git / target / cargo-generate.toml, keeps binaries",
    function()
      local src = make_template()
      local dest = H.tmpdir() .. "/out"
      local made = assert(T.copy(src, dest, "my-app"))
      H.has(made, "my-app.md")
      H.eq(
        '[package]\nname = "my-app"\nversion = "0.1.0"\nedition = "2021"\n',
        io.open(dest .. "/Cargo.toml"):read("*a")
      )
      H.match(io.open(dest .. "/src/main.rs"):read("*a"), "My App / my_app", true)
      H.eq("# my-app\n", io.open(dest .. "/my-app.md"):read("*a"))
      H.eq("\0{{name}}\0", io.open(dest .. "/blob.bin", "rb"):read("*a"))
      H.is_nil(vim.uv.fs_stat(dest .. "/.git"))
      H.is_nil(vim.uv.fs_stat(dest .. "/target"))
      H.is_nil(vim.uv.fs_stat(dest .. "/cargo-generate.toml"))
    end
  )

  it("refuses scripts, hooks and symlinks (nothing is created)", function()
    local a = make_template()
    write(a .. "/hooks/init.rhai", "print(1)")
    local dest = H.tmpdir() .. "/o1"
    local ok, why = T.copy(a, dest, "x")
    H.is_nil(ok)
    H.match(why, "never executed", true)
    H.is_nil(vim.uv.fs_stat(dest))

    local b = make_template()
    write(b .. "/cargo-generate.toml", '[hooks]\npre = ["a.rhai"]\n')
    local _, why2 = T.copy(b, H.tmpdir() .. "/o2", "x")
    H.match(why2, "hooks", true)

    local c = make_template()
    vim.uv.fs_symlink("/etc/passwd", c .. "/leak")
    local _, why3 = T.copy(c, H.tmpdir() .. "/o3", "x")
    H.match(why3, "symbolic link", true)
  end)

  it("refuses an existing destination and a file name that escapes", function()
    local src = make_template()
    local exist = H.tmpdir()
    local _, why = T.copy(src, exist, "x")
    H.match(why, "exists already", true)
    local evil = H.tmpdir()
    write(evil .. "/a.txt", "x")
    vim.uv.fs_rename(evil .. "/a.txt", evil .. "/{{name}}.txt")
    local _, why2 = T.copy(evil, H.tmpdir() .. "/o", "../../etc/x")
    H.match(why2, "outside the project", true)
  end)
end)

describe("git templates", function()
  local function repo()
    local d = make_template()
    local function git(...)
      local r = vim.system({ "git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t", ... }, { text = true }):wait()
      assert(r.code == 0, r.stderr)
      return vim.trim(r.stdout)
    end
    git("init", "-q")
    git("add", "-A", "-f")
    git("commit", "-q", "-m", "one")
    local first = git("rev-parse", "HEAD")
    write(d .. "/src/main.rs", "fn main() { /* second */ }\n")
    git("commit", "-qam", "two")
    return d, first
  end

  it("creates the project from the pinned commit, not from the branch head", function()
    if vim.fn.executable("git") ~= 1 then
      return H.skip_file("git not installed")
    end
    local d, first = repo()
    local out
    T.create({ name = "g", git = d, rev = first }, "pinned", H.tmpdir(), function(err, dir)
      out = { err = err, dir = dir }
    end)
    H.wait_for(function()
      return out
    end, 30000, "clone")
    H.is_nil(out.err)
    H.match(io.open(out.dir .. "/src/main.rs"):read("*a"), "Pinned / pinned", true)
    H.is_nil(vim.uv.fs_stat(out.dir .. "/.git"))
  end)

  it("a wrong commit is an error, no directory is left", function()
    if vim.fn.executable("git") ~= 1 then
      return H.skip_file("git not installed")
    end
    local d = repo()
    local parent = H.tmpdir()
    local out
    T.create({ name = "g", git = d, rev = ("0"):rep(40) }, "nope", parent, function(err)
      out = { err = err }
    end)
    H.wait_for(function()
      return out
    end, 30000, "clone")
    H.match(out.err, "git:", true)
    H.is_nil(vim.uv.fs_stat(parent .. "/nope"))
  end)
end)

describe(":RustNewFrom", function()
  it("lists built-in kinds then the pinned templates; a named one runs the whole flow", function()
    local src = make_template()
    T.set((T.validate({ { name = "svc", path = src, description = "demo" } })))
    local e = T.entries()
    H.eq(
      { "binary", "library", "workspace", "member", "egui", "svc" },
      vim.tbl_map(function(x)
        return x.label
      end, e)
    )
    local parent = H.tmpdir()
    local orig = vim.ui.input
    local answers = { "demo-app", parent }
    vim.ui.input = function(_, cb)
      cb(table.remove(answers, 1))
    end
    local n = {}
    local orig_notify = vim.notify
    vim.notify = function(m)
      n[#n + 1] = m
    end
    vim.cmd("RustNewFrom svc")
    H.wait_for(function()
      return vim.uv.fs_stat(parent .. "/demo-app/Cargo.toml")
    end, 5000, "project")
    vim.ui.input = orig
    vim.notify = orig_notify
    H.match(io.open(parent .. "/demo-app/Cargo.toml"):read("*a"), 'name = "demo-app"', true)
    H.eq(vim.fs.normalize(parent .. "/demo-app/src/main.rs"), vim.fs.normalize(vim.api.nvim_buf_get_name(0)))
    H.match(n[#n], 'from template "svc"', true)
  end)
  it("an unknown name says so", function()
    T.set({})
    local n = {}
    local o = vim.notify
    vim.notify = function(m)
      n[#n + 1] = m
    end
    vim.cmd("RustNewFrom nope")
    vim.notify = o
    H.match(n[1], "no template", true)
  end)
end)
