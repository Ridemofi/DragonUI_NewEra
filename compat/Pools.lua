-- DragonUI_NewEra/compat/Pools.lua — CreateFramePool / CreateTexturePool (retail SharedXML Pools).
--
-- Only consumer: the embedded LibCustomGlow (Libs/), which calls both at FILE LOAD and then uses
-- only :Acquire() and :Release(obj). So this loads BEFORE the Libs block in the TOC, needs nothing
-- from NE, and implements just that surface. Each global is defined only when absent.

local function newPool(create, resetter)
  local pool = { active = {}, inactive = {} }
  function pool:Acquire()
    local obj = tremove(self.inactive)
    local new = obj == nil
    if new then obj = create(self) end
    self.active[obj] = true
    return obj, new
  end
  function pool:Release(obj)
    if not self.active[obj] then return false end
    self.active[obj] = nil
    if resetter then resetter(self, obj) end
    self.inactive[#self.inactive + 1] = obj
    return true
  end
  function pool:ReleaseAll()
    for obj in pairs(self.active) do self:Release(obj) end
  end
  return pool
end

local function hideAndClear(_, obj) obj:Hide(); obj:ClearAllPoints() end

if not CreateFramePool then
  function CreateFramePool(frameType, parent, template, resetter)
    if template == "" then template = nil end
    return newPool(function() return CreateFrame(frameType, nil, parent, template) end,
      resetter or hideAndClear)
  end
end

if not CreateTexturePool then
  function CreateTexturePool(parent, layer, subLayer, template, resetter)
    return newPool(function() return parent:CreateTexture(nil, layer, template, subLayer) end,
      resetter or hideAndClear)
  end
end
