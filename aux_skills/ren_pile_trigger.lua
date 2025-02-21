local renPileTrigger = fk.CreateSkill{
  name = "#RenPileTrigger",
}

renPileTrigger:addEffect(fk.AfterCardsMove, {
  priority = 1.001,
  mute = true,
  can_trigger = function(self, event, target, player, data)
    local renpile = Utility.GetRenPile(player.room)
    if player.seat == 1 then
      for _, move in ipairs(data) do
        if move.toArea == Card.Void and move.extra_data and move.extra_data.addtorenpile then
          return true
        end
        if table.find(move.moveInfo, function(info) return table.contains(renpile, info.cardId) end) then
          return true
        end
      end
    end
  end,
  on_cost = Util.TrueFunc,
  on_use = function(self, event, target, player, data)
    local room = player.room
    local renpile = Utility.GetRenPile(room)
    for _, move in ipairs(data) do
      local removed
      for _, info in ipairs(move.moveInfo) do
        if table.contains(renpile, info.cardId) then
          table.removeOne(renpile, info.cardId)
          removed = true
        end
      end
      if removed then
        move.extra_data = move.extra_data or {}
        move.extra_data.removefromrenpile = true
      end
      if move.toArea == Card.Void and move.extra_data and move.extra_data.addtorenpile then
        local add = {}
        for _, info in ipairs(move.moveInfo) do
          if room:getCardArea(info.cardId) == Card.Void then
            table.insert(add, info.cardId)
          end
        end
        if #add > 0 then
          room:sendLog{
            type = "#AddToRenPile",
            arg = move.skillName,
            card = add,
          }
          table.insertTableIfNeed(renpile, add)
        end
      end
    end
    room:setBanner("@$RenPile", renpile)
    local ren_limit = 6
    if #renpile > ren_limit then
      local removeIds = table.slice(renpile, 1, #renpile - ren_limit + 1)
      room:sendLog{
        type = "#OverflowFromRenPile",
        card = removeIds,
      }
      room:moveCardTo(removeIds, Card.DiscardPile, nil, fk.ReasonPutIntoDiscardPile, "ren_overflow", nil, true)
    end
  end,
})

return renPileTrigger
