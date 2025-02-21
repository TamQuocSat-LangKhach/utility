local realcard_viewas = fk.CreateSkill{
  name = "realcard_viewas",
}

Fk:loadTranslationTable{
  ["realcard_viewas"] = "使用",
  ["#askForUseRealCard"] = "%arg：请使用一张牌",
}

realcard_viewas:addEffect('viewas', {
  card_filter = function (self, player, to_select, selected)
    return #selected == 0 and table.contains(self.optional_cards, to_select.id)
  end,
  view_as = function(self, player, cards)
    if #cards == 1 then
      local cid = cards[1]
      local mark = player:getTableMark("realcard_vs_owners")
      if mark[tostring(cid)] then
        local owner = Fk:currentRoom():getPlayerById(mark[tostring(cid)])
        Fk:filterCard(cid, owner)
      end
      return Fk:getCardById(cid)
    end
  end,
})

return realcard_viewas
