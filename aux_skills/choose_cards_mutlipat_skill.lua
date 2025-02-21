local choose_cards_mutlipat_skill = fk.CreateSkill{
  name = "choose_cards_mutlipat_skill",
}

Fk:loadTranslationTable{
  ["choose_cards_mutlipat_skill"] = "选牌",
  ["#askForCardByMultiPatterns"] = "选牌",
}

choose_cards_mutlipat_skill:addEffect('active', {
  interaction = function(self, player)
    local patterns = self.patterns
    if not patterns then return end
    return UI.ComboBox {choices = table.map(patterns, function(v, i) return v[4] end) }
  end,
  card_filter = function(self, player, to_select, selected)
    local patterns, choice = self.patterns, self.interaction.data
    if not patterns or not choice then return end
    if self.discard_skill and player:prohibitDiscard(to_select) then return end
    for _, v in ipairs(patterns) do
      if v[4] == choice then
        return #selected < v[3] and Exppattern:Parse(v[1]):match(Fk:getCardById(to_select))
      end
    end
  end,
  target_filter = Util.FalseFunc,
  feasible = function(self, player, _, cards)
    local patterns, choice = self.patterns, self.interaction.data
    if not patterns or not choice then return end
    for _, v in ipairs(patterns) do
      if v[4] == choice then
        return #cards <= v[3] and #cards >= v[2]
      end
    end
  end,
})

return choose_cards_mutlipat_skill
