-- Behavioural test for the SavedVariables default merge.
--
-- Repo infrastructure, not addon code -- it lives outside DKForce/ for the same
-- reason the other specs do: verify.sh check 3 demands every .lua there appear
-- in the TOC.
--
-- This function runs once per login against every existing character's saved
-- settings, and a mistake in it is close to unrecoverable: it either wipes
-- choices or leaves new keys missing, and the user finds out later, in a fight.
-- It replaced six hand-written copies of the same pattern, so the risk of that
-- mistake is exactly what makes it worth testing.
--
-- The slice is bounded by the header comment and the first line that is exactly
-- `end`, so if the function is moved or renamed this fails loudly rather than
-- passing vacuously.

local SOURCE = os.getenv("DKFORCE_DB_SOURCE") or "DKForce/Core.lua"
local HEADER = "-- Fill in whatever a saved table is missing, recursively."

local failures, checks = 0, 0

local function check(label, got, want)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        print(string.format("  FAIL  %-52s got %s, want %s", label, tostring(got), tostring(want)))
    end
end

local function sliceMerge()
    local f = assert(io.open(SOURCE, "r"), "cannot open " .. SOURCE)
    local lines = {}
    for line in f:lines() do lines[#lines + 1] = line end
    f:close()

    local first
    for i, line in ipairs(lines) do
        if line == HEADER then first = i break end
    end
    if not first then
        return nil, ("merge header not found in %s -- was it moved or renamed?"):format(SOURCE)
    end
    local last
    for i = first + 1, #lines do
        if lines[i] == "end" then last = i break end
    end
    if not last then return nil, "end marker not found after the header" end
    -- `local function` would not survive the chunk boundary, so expose it.
    return table.concat(lines, "\n", first, last) .. "\n_MergeDefaults = MergeDefaults"
end

local source, sliceErr = sliceMerge()
if not source then
    print("SavedVariables default merge             FAIL")
    print("  " .. sliceErr)
    os.exit(1)
end
assert(load(source, "db-merge"))()
local MergeDefaults = _MergeDefaults

if type(MergeDefaults) ~= "function" then
    print("SavedVariables default merge             FAIL")
    print("  the slice did not define MergeDefaults")
    os.exit(1)
end

-- 1. An empty database is populated outright.
local defaults = {
    enabled = true,
    size = 64,
    color = { r = 1, g = 0.5, b = 0 },
    nested = { deep = { value = 7 } },
}
local db = {}
MergeDefaults(db, defaults)
check("empty db: scalar filled", db.enabled, true)
check("empty db: number filled", db.size, 64)
check("empty db: nested value filled", db.color.g, 0.5)
check("empty db: deeply nested filled", db.nested.deep.value, 7)

-- 2. Existing choices are never overwritten.  A saved `false` is the case that
--    a naive `if not target[key]` would silently reset to the default, turning
--    every deliberately disabled feature back on at login.
db = { enabled = false, size = 20, color = { r = 0, g = 0, b = 0 } }
MergeDefaults(db, defaults)
check("saved false is kept", db.enabled, false)
check("saved number is kept", db.size, 20)
check("saved colour is kept", db.color.r, 0)

-- 3. A new key inside an existing table is added without disturbing the rest.
--    This is the whole point: the old per-table blocks meant a new default only
--    reached existing characters if someone added another block by hand.
db = { color = { r = 0.2 } }
MergeDefaults(db, defaults)
check("new sibling key added", db.color.b, 0)
check("existing sibling untouched", db.color.r, 0.2)

-- 4. The result must never share a table with the defaults, or editing one
--    character's colour would edit the shipped default -- and every other
--    character created afterwards.
db = {}
MergeDefaults(db, defaults)
db.color.r = 0.99
db.nested.deep.value = 99
check("nested table is a copy, not a reference", defaults.color.r, 1)
check("deep table is a copy too", defaults.nested.deep.value, 7)

-- 5. Keys the defaults no longer mention are left alone.  Orphans from removed
--    features are harmless, and deleting them is not this function's job.
db = { legacyKey = "keep me" }
MergeDefaults(db, defaults)
check("unknown saved key survives", db.legacyKey, "keep me")

-- 6. A saved scalar where the default is a table gets rebuilt as the table.
--    Without this the addon would index a number and error at login.
db = { color = 5 }
MergeDefaults(db, defaults)
check("scalar replaced by default table", type(db.color), "table")
check("replacement is fully populated", db.color.g, 0.5)

-- 7. A default that is absent by design stays absent.  blightfallChain omits
--    iconPosition deliberately, so the drag handler can create it on first use.
check("key absent from defaults is not invented", db.iconPosition, nil)

if failures == 0 then
    print(string.format("SavedVariables default merge             OK (%d checks)", checks))
    os.exit(0)
end
print(string.format("SavedVariables default merge             FAIL (%d/%d)", failures, checks))
os.exit(1)
