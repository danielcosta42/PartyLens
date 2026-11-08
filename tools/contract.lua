-- The UI is built from specs/forever/ui-contract.md alone, so the core must keep every promise it makes there:
-- each PartyLens:Method( it names exists, each event in its table is fired by the core, each settings path is in a
-- fresh save, and each page key and context reaches PartyLens.UI.
--
--   luajit tools/contract.lua   (from the repository root; exits 1 on the first failed check)
local W = dofile("tools/wowstub.lua")
local check = W.check

local PL = W.boot({})
local doc = assert(io.open("specs/forever/ui-contract.md")):read("*a")

local methods = 0
for name in doc:gmatch("PartyLens:(%w+)%(") do
  methods = methods + 1
  check(type(PL[name]) == "function", "the contract's PartyLens:" .. name .. "() exists")
end
check(methods > 40, "the contract was read (" .. methods .. " method mentions)")

local source = {}
for _, path in ipairs(W.toc()) do
  if not path:find("^Libs/") and not path:find("ChehulNet%.lua$") then
    source[#source + 1] = assert(io.open(path)):read("*a")
  end
end
source = table.concat(source, "\n")
local events = doc:match("## 1%. Event bus(.-)## 2%.")
local n = 0
for name in events:gmatch("\n| `([A-Z_]+)` |") do
  n = n + 1
  check(source:find('Fire%("' .. name .. '"') ~= nil, "the core fires " .. name)
end
check(n >= 14, "every event row was read (" .. n .. ")")

local settings = doc:match("## 2%. Settings(.-)## 3%.")
local paths = 0
for cell in settings:gmatch("\n| ([^|]+) |") do
  for token in cell:gmatch("`([%w%.%/]+)`") do
    local alts = {}
    local base, tail = token:match("^(.*%.)([%w/]+)$")
    if base and tail:find("/", 1, true) then
      for alt in tail:gmatch("[^/]+") do alts[#alts + 1] = base .. alt end
    else
      alts[1] = token
    end
    for _, path in ipairs(alts) do
      if path:find("%.") or PL.db[path] ~= nil then
        local t = PL.db
        for part in path:gmatch("[^%.]+") do
          if type(t) == "table" then t = t[part] else t = nil end
        end
        paths = paths + 1
        check(t ~= nil, "the settings path " .. path .. " is in a fresh save")
      end
    end
  end
end
check(paths >= 20, "the settings table was read (" .. paths .. " paths)")

local opened = {}
PL.UI = { Open = function(_, page, ctx) opened[#opened + 1] = { page, ctx } end, Toggle = function() end }
for page in doc:match("`pageKey` one of ([^.]+)%."):gmatch('`"(%w+)"`') do
  PL:Open(page)
  check(opened[#opened][1] == page, "Open forwards the page key " .. page)
end
check(#opened == 6, "the six pages")

W.done("contract")
