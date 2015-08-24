-- Identifies the Lua transceiver indices associated with each weapon group (assuming none are damaged)
-- Requires there to be no extant missiles associated with Lua transceivers on the craft in question
-- Will fire all weapons in their present direction
-- Note that newly added transceivers may take low indices; rerun after all changes

i = 0
t = -99999
transceivers = {}
groupTransceivers = {}

function Update(I)
  if i > 5 then return 0 end

  for trans = 0, I:GetLuaTransceiverCount()-1 do
    if I:GetLuaControlledMissileCount(trans) > 0 then
      if not transceivers[trans] then
        transceivers[trans] = true
        table.insert(groupTransceivers[i-1], trans)
        t = I:GetTime() + 1
      end
    end
  end
          
  if I:GetTime() > t then
    if groupTransceivers[i-1] and #(groupTransceivers[i-1]) > 0 then
      table.sort(groupTransceivers[i-1])
      local s = '{'
      for k, v in ipairs(groupTransceivers[i-1]) do
        s = s .. v .. ", "
      end
      
      I:Log(string.format('Group %d transceivers: %s}', i-1, string.sub(s, 1, -3)))   
    end
    for wi = 0, I:GetWeaponCount() - 1 do
      local w = I:GetWeaponInfo(wi)
      if w.WeaponSlot == i then
        I:AimWeaponInDirection(wi, w.CurrentDirection.x, w.CurrentDirection.y, w.CurrentDirection.z, i)
        local fired = I:FireWeapon(wi, w.WeaponSlot)
        if fired then
          t = I:GetTime() + 1
          groupTransceivers[i] = {}
        end
      end
    end
    i = i+1
  end
end