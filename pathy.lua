-- This program is designed to be spawned by a special shell
-- script. File descriptors upon entry:
--
-- Stdout and stderr go to the user's terminal (or possibly to
-- user-supplied pipes or files if they used redirects) as normal.
--
-- File descriptor 3 writes to a pipe set up by the shell script.  The
-- shell script passes everything we write to fd 3 to the shell's eval
-- built-in, provided that we terminate by a normal exit with exit
-- code zero. If we terminate via signal or exit with a non-zero exit
-- code, the shell script ignores anything we might have written to fd
-- 3.  On many successful runs we will write nothing to fd 3. That's
-- fine: eval "" in shell is a no-op that succeeds.

-- Globals

local globals = {}
local commands = {}
local help = {}

-- TODO: Should extensions be case sensitive? E.g. I Python .py/.pyc
-- extensions seem to be (at least on Unix), whereas Windows
-- extensions are generally not (Microsoft file systems tend to be
-- case insensitive)
local magicvars = {
  {name="CDPATH", subdirs=true},
  {name="PATH", subdirs=false}, -- TODO: Windows: extensions={".bat", ".cmd", ".exe"}
  {name="GEM_PATH"},
  {name="PYTHONPATH", subdirs=true, extensions={".py", ".pyc"}},
}

local EXITS = {CANCELED=1, ERROR=1}
globals.exitcode = 0

globals.pathvar = "PATH"
globals.pathsep = ":"
globals.notpathsep = "[^:]+"

-- Utilities

function die(msg)
  io.stderr:write(PROGNAME..": "..msg.."\n")
  os.exit(EXITS.ERROR)
end

local function exit_on_error(fn)
  local ok, errmsg = pcall(fn)
  if not ok then
    io.stderr:write(PROGNAME..": "..errmsg.."\n")
    globals.exitcode = EXITS.ERROR
  end
end

function prompt_yn(prompt)
  while true do
    io.write(string.format("%s [yN] ", prompt))
    io.flush()
    local input = io.read()
    if not input then -- End-of-file: user pressed Ctrl+D.
      print()
      print("OK, we're giving up. Bye!")
      os.exit(EXITS.CANCELED)
    end
    input = string.lower(input)
    if input == "y" then
      return true
    elseif input == "n" or input == "" then
      return false
    else
      print("Please answer 'y' for yes or 'n' for no, or press Ctrl-C to exit.")
    end
  end
end

function get_ls_files_table()
  -- TODO: Currently always shallow. Would a deep/recursive option be useful?
  local allfiles = {}
  for dir in iter_clean_path() do
    local dirslash = dir.."/"
    local dirfiles = {}
    exit_on_error(function() list_files_into_table(dir, dirfiles) end)
    for _, name in ipairs(dirfiles) do
      table.insert(allfiles, dirslash..name)
    end
  end
  table.sort(allfiles)
  return allfiles
end

function get_ls_names_table()
  local hashtable = {}
  for dir in iter_clean_path() do
    exit_on_error(function() hash_files_into_table(dir, hashtable) end)
  end
  local allnames = {}
  for name, _ in pairs(hashtable) do
    table.insert(allnames, name)
  end
  table.sort(allnames)
  return allnames
end

function checkdirs(dirs)
  for dir in dirs do
    if true then --#[ ! -d "$dir" ]; then
      --echo "WARNING: $dir is not an existing directory" >&2
    end
  end
end

function iter_clean_path()
  local ps = (os.getenv(globals.pathvar) or "")
  return string.gmatch(ps, globals.notpathsep)
end

function get_clean_path_as_table()
  local tbl = {}
  for x in iter_clean_path() do
    table.insert(tbl, x)
  end
  return tbl
end

function set_clean_path(tbl)
  -- check if any entries envelop one another
  local out = ""
  for i, dir in ipairs(tbl) do
    if out:len() > 0 then
      out = out..globals.pathsep
    end
    out = out..dir
  end
  write_to_fd3("export "..globals.pathvar.."="..out)
end

-- Commands

help.ls = "List path entries (in the order they apply)"
function commands.ls(k)
  for s in iter_clean_path() do
    if (not k) or string.find(s:lower(), k:lower(), 1, true) then
      print(s)
    end
  end
end

help.sorted = "List path entries in alphabetical order"
function commands.sorted()
  -- TODO: sort ignore case
  local path = get_clean_path_as_table()
  table.sort(path)
  for _, dir in ipairs(path) do
    print(dir)
  end
end

help.grep = "Search contents of all files in path"
function commands.grep()
  local allfiles = get_ls_files_table()
  for _, file in ipairs(allfiles) do
  end
end

help.rm = "Remove path entries (you'll be asked for each entry)"
function commands.rm(key)
  local newpath = {}
  local hadany = false
  for s in iter_clean_path() do
    if not hadany then
      hadany = true
      print("Going through the path list in order. Answer 'y' (yes)")
      print("to the entries you want to remove. Default answer is no.")
    end
    local keep = true
    if (not key) or string.find(s:lower(), key:lower(), 1, true) then
      keep = not prompt_yn(string.format("Remove %s?", s))
    end
    if keep then
      table.insert(newpath, s)
    end
  end
  if hadany then
    set_clean_path(newpath)
  else
    print("Path is empty")
  end
end

help.putfirst = "Add or move the given entry to the beginning of the path"
function commands.putfirst(...)
  local path = get_clean_path_as_table()
  for i, newdir in ipairs(table.pack(...)) do
    table.insert(path, i, newdir)
  end
  set_clean_path(path)
end

help.putlast = "Add or move the given entry to the end of the path"
function commands.putlast(...)
  local path = get_clean_path_as_table()
  for _, newdir in ipairs(table.pack(...)) do
    table.insert(path, newdir)
  end
  set_clean_path(path)
end

function ls_files(key, get_list)
  local allfiles = get_list()
  for _, file in ipairs(allfiles) do
    if (not key) or string.find(file:lower(), key:lower(), 1, true) then
      print(file)
    end
  end
end

help["ls-files"] = "List all files in path (full pathnames)"
commands["ls-files"] = function(key)
  ls_files(key, get_ls_files_table)
end

help["ls-names"] = "List all files in path (names only)"
commands["ls-names"] = function(key)
  ls_files(key, get_ls_names_table)
end

help["which"] = "See which file matches in path"
function commands.which(name)
  for dir in iter_clean_path() do
  end
end

help["doctor"] = "Find potential path problems"
function commands.doctor()
  local ntotal = 0
  for dir in iter_clean_path() do  -- TODO: should iter the dirty path
    local diags = get_directory_diagnostics(dir)
    local problems = {}
    if diags.error then
      table.insert(problems, diags.error)
    end
    if diags.is_world_writable then
      table.insert(problems, "is world-writable")
    end
    if #problems > 0 then
      print(dir)
      for _, problem in ipairs(problems) do
        print("* "..problem)
      end
    end
    ntotal = ntotal + #problems
  end
  if ntotal > 1 then
    print(string.format("%d problems found", ntotal))
  elseif ntotal == 1 then
    print("1 problem found")
  else
    print("No problems found :)")
  end
end

help["shadow"] = "Show name conflicts"
function commands.shadow()
  local namedirs = {}
  for dir in iter_clean_path() do
    local dirnames = {}
    exit_on_error(function() list_files_into_table(dir, dirnames) end)
    for _, name in ipairs(dirnames) do
      namedirs[name] = namedirs[name] or {}
      table.insert(namedirs[name], dir)
    end
  end
  local shadownames = {}
  for name, dirs in pairs(namedirs) do
    if #dirs > 1 then
      table.insert(shadownames, name)
    end
  end
  table.sort(shadownames)
  for _, name in ipairs(shadownames) do
    print(name)
    for _, dir in ipairs(namedirs[name]) do
      print("* "..dir)
    end
  end
end

function commands.version()
  print(string.format("%s %s (%s)", PROGNAME, PROGVERSION, _VERSION))
end

function commands.help()
  local maxlen = 0
  local tbl = {}
  for name, _ in pairs(commands) do
    if help[name] then
      maxlen = math.max(maxlen, #name)
      table.insert(tbl, name)
    end
  end
  table.sort(tbl)
  print("This is "..PROGNAME..", helping you work with PATH and similar envars.")
  print("Try `man "..PROGNAME.."` for a complete guide.")
  print()
  for _, name in ipairs(tbl) do
    print(PROGNAME.." "..name..string.rep(" ", maxlen-#name+2)..help[name])
  end
end

function complete()
  local cword = tonumber(arg[2])
  if not (cword and cword % 1 == 0 and cword > 0 and cword < #arg) then
    -- cword is not a valid index into arg so don't offer any completions.
  elseif cword == 1 then
    for name, _ in pairs(commands) do
      print(name)
    end
  else
    -- TODO: cword > 1, completion depends on command
  end
end

function main()
  if arg[1] == "complete" then
    complete()
  elseif arg[1] == "user" then
    assert_fd3_is_pipe() -- Sanity check so we don't accidentally overwrite curious users' files or something.
    -- We can cheat here: since we know the first arg is "user", it can't be an
    -- option.
    local opts
    exit_on_error(function() arg, opts = getopt(arg, "vq", "V") end)
    if opts.V then globals.pathvar = opts.V end
    local cmd = commands[#arg < 2 and "help" or arg[2]]
    if not cmd then die("unknown command: "..arg[2]) end
    local cmdargs = {}
    for i = 3,#arg do
      table.insert(cmdargs, arg[i])
    end
    cmd(unpack(cmdargs))
    os.exit(globals.exitcode)
  elseif arg[1] == "fail" then  -- For debugging the shell script
    write_to_fd3("this will not be run")
    os.exit(123)
  else
    error("bad first arg: "..tostring(arg[1]))
  end
end

main()
