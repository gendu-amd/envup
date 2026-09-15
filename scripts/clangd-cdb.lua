-- Convert a Docker-view compile_commands.json into the host's path namespace.
-- Usage: nvim --clean --headless -l clangd-cdb.lua INPUT OUTPUT MAPPINGS
-- MAPPINGS is tab-separated: container path<TAB>host path, most specific first.

local input, output, mapping_file
if type(arg) == "table" then
  input, output, mapping_file = arg[1], arg[2], arg[3]
else
  input, output, mapping_file = ...
end
if not input or not output or not mapping_file then
  error "usage: clangd-cdb.lua INPUT OUTPUT MAPPINGS"
end

local function read(path)
  local file = assert(io.open(path, "rb"))
  local value = file:read "*a"
  file:close()
  return value
end

local mappings = {}
for line in read(mapping_file):gmatch "[^\r\n]+" do
  local container, host = line:match "^([^\t]+)\t(.+)$"
  if container and host then
    mappings[#mappings + 1] = { container = container, host = host }
  end
end
assert(#mappings > 0, "no Docker mount mappings supplied")

local function replace_plain(value, from, to)
  local out, at = {}, 1
  while true do
    local first, last = value:find(from, at, true)
    if not first then
      out[#out + 1] = value:sub(at)
      return table.concat(out)
    end
    out[#out + 1] = value:sub(at, first - 1)
    out[#out + 1] = to
    at = last + 1
  end
end

local changed = 0
local function translate_string(value)
  local out, at = {}, 1
  while at <= #value do
    local best, best_first, best_last
    for _, mapping in ipairs(mappings) do
      local first, last = value:find(mapping.container, at, true)
      if first and (not best_first or first < best_first or (first == best_first and #mapping.container > #best.container)) then
        best, best_first, best_last = mapping, first, last
      end
    end
    if not best then
      out[#out + 1] = value:sub(at)
      break
    end
    out[#out + 1] = value:sub(at, best_first - 1)
    out[#out + 1] = best.host
    at = best_last + 1
  end
  return table.concat(out)
end

local function translate(value)
  if type(value) == "string" then
    local original = value
    value = translate_string(value)
    if value ~= original then
      changed = changed + 1
    end
    return value
  end
  if type(value) == "table" then
    for key, item in pairs(value) do
      value[key] = translate(item)
    end
  end
  return value
end

local database = vim.json.decode(read(input))
assert(type(database) == "table", "compile database is not a JSON array")
translate(database)

vim.fn.mkdir(vim.fs.dirname(output), "p")
local temporary = output .. ".tmp." .. tostring(vim.uv.os_getpid())
local file = assert(io.open(temporary, "wb"))
file:write(replace_plain(vim.json.encode(database), "\\/", "/"), "\n")
file:close()
assert(vim.uv.fs_rename(temporary, output))
print(("translated %d entries (%d path-bearing strings changed)"):format(#database, changed))
