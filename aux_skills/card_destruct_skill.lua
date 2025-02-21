local cardDestructSkill = fk.CreateSkill{
  name = "#card_destruct_skill",
}

Fk:loadTranslationTable{
  ["#card_destruct_skill"] = "卡牌销毁",
  ["#destructDerivedCards"] = "%card 被销毁了",
}

cardDestructSkill:addEffect(fk.BeforeCardsMove, {
  global = true,
  mute = true,
  can_refresh = function (self, event, target, player, data)
    return player == player.room.players[1]
  end,
  on_refresh = function(self, event, target, player, data)
    local room = player.room
    local mirror_moves = {}
    local ids = {}
    for _, move in ipairs(data) do
      if move.toArea ~= Card.Void then
        local move_info = {}
        local mirror_info = {}
        for _, info in ipairs(move.moveInfo) do
          local id = info.cardId
          local card = Fk:getCardById(id)
          local yes
          if card:getMark(MarkEnum.DestructIntoDiscard) > 0 and move.toArea == Card.DiscardPile then
            yes = true
          end
          if card:getMark(MarkEnum.DestructOutMyEquip) > 0 and info.fromArea == Card.PlayerEquip then
            yes = info.fromArea == Card.PlayerEquip
          end
          if card:getMark(MarkEnum.DestructOutEquip) > 0 and (info.fromArea == Card.PlayerEquip and move.toArea ~= Card.PlayerEquip and move.toArea ~= Card.Processing) then
            yes = true
          end
          if yes then
            table.insert(mirror_info, info)
            table.insert(ids, id)
          else
            table.insert(move_info, info)
          end
        end
        if #mirror_info > 0 then
          move.moveInfo = move_info
          local mirror_move = table.clone(move)
          mirror_move.to = nil
          mirror_move.toArea = Card.Void
          mirror_move.moveInfo = mirror_info
          mirror_move.moveMark = nil
          mirror_move.moveVisible = true
          table.insert(mirror_moves, mirror_move)
        end
      end
    end
    if #ids > 0 then
      room:sendLog{ type = "#destructDerivedCards", card = ids, }
      table.insertTable(data, mirror_moves)
    end
  end,
})

return cardDestructSkill
