-- DragonUI_NewEra/compat/MapDebugObjects.lua
-- GetMapDebugObjectInfo — keep the world map alive on a client whose map-debug pair disagrees.
--
-- WorldMapFrame_Update (stock 3.3.5a, lines 401-412) ends with:
--
--     local numDebugObjects = GetNumMapDebugObjects();
--     ...
--     for i = 1, numDebugObjects do
--       local name, size, x, y = GetMapDebugObjectInfo(i);
--       if ( (x ~= 0 or y ~= 0) and (size > 1 or GetCurrentMapZone() ~= WORLDMAP_WORLD_ID) ) then
--
-- `size > 1` compiles to `1 < size`, so a nil size raises "attempt to compare number with nil" —
-- operands reading backwards from the source, which is what makes the report confusing.
--
-- What it costs is ONLY the error. The loop above is the last thing WorldMapFrame_Update does
-- (lines 409-438, and the function ends at 438); the map textures, POIs, overlays and zone map are
-- all finished by then, and a client that cannot describe its debug objects was never going to
-- draw one. So this is not map breakage, it is an error raised once per map update — which is
-- still worth killing, because it fires on every update and buries real errors under itself.
--
-- On a stock client the two can never disagree, because both are dead stubs: in 3.3.5a 12340
-- GetNumMapDebugObjects is literally `fldz` + pushnumber (constant 0) and GetMapDebugObjectInfo is
-- `xor eax,eax; ret` (returns nothing, ever). The count is 0, the loop never runs, and none of this
-- can fire. That is why stock never sees it and why the stock guard was written assuming it.
--
-- It fires on a client where something NATIVE implements or detours one of the two and not the
-- other: a loaded DLL, a patched exe, a custom build. A count above zero with an info getter that
-- still answers nothing is unwinnable for the stock UI — index 1 throws before anything is drawn.
-- Not hypothetical: reported here with GetNumMapDebugObjects() = 3 and GetMapDebugObjectInfo(1)
-- returning four nils, on a global that issecurevariable called SECURE — so no addon did it, and
-- no addon can be blamed or fixed for it. We cannot know what any given player's client has been
-- patched with, so the map has to survive being lied to.
--
-- The fix passes the client's answer straight through whenever it is usable, and when it is not,
-- answers as a debug object with no position. Stock's own `(x ~= 0 or y ~= 0)` guard then skips
-- that index, which is the honest reading: an object the client cannot describe has nothing to
-- draw. A client that implements the pair properly is untouched; a client that lies costs one
-- skipped debug marker instead of a broken map.
--
-- WHY THE INFO GETTER AND NOT THE COUNT. Forcing the count to 0 also works, and is shorter, but it
-- is the wrong lever twice over. It would be read on every map update on every client, healthy or
-- not, so the taint from writing it lands on everybody; and it would suppress a client that
-- implements BOTH functions correctly, which is exactly the "works with anyone's copy" case this
-- file exists to protect. Wrapping the info getter is read only when the count is already above
-- zero, so on a healthy client (count 0) the loop never runs, the global is never read, and the
-- taint from defining it costs nothing at all. Where it IS read, the alternative is a hard error,
-- and nothing in WorldMapFrame_Update's remaining path is protected.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

local rawInfo = GetMapDebugObjectInfo

function GetMapDebugObjectInfo(index)
    if type(rawInfo) ~= "function" then
        -- The client does not ship the getter at all; stock would error on the call itself.
        return "", 0, 0, 0
    end
    local name, size, x, y = rawInfo(index)
    if type(size) == "number" and type(x) == "number" and type(y) == "number" then
        return name, size, x, y
    end
    return name or "", 0, 0, 0
end

NE.compat.mapDebugObjects = true
