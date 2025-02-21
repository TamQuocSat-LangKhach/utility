local global_slash_targetmod = fk.CreateSkill{
  name = "global_slash_targetmod",
}

global_slash_targetmod:addEffect('targetmod', {
  global = true,
  residue_func = function(self, player, skill, scope)
    if skill.trueName == "slash_skill" and scope == Player.HistoryPhase then
      local num = player:getMark(MarkEnum.SlashResidue)
      for _, s in ipairs(MarkEnum.TempMarkSuffix) do
        num = num + player:getMark(MarkEnum.SlashResidue..s)
      end
      return num
    end
  end,
  bypass_times = function(self, player, skill, scope)
    if skill.trueName == "slash_skill" and scope == Player.HistoryPhase then
      return player:getMark(MarkEnum.SlashBypassTimes) ~= 0 or
      table.find(MarkEnum.TempMarkSuffix, function(s)
        return player:getMark(MarkEnum.SlashBypassTimes .. s) ~= 0
      end)
    end
  end,
  bypass_distances = function (self, player, skill)
    if skill.trueName == "slash_skill" then
      return player:getMark(MarkEnum.SlashBypassDistances) ~= 0 or
      table.find(MarkEnum.TempMarkSuffix, function(s)
        return player:getMark(MarkEnum.SlashBypassDistances .. s) ~= 0
      end)
    end
  end
})

return global_slash_targetmod
