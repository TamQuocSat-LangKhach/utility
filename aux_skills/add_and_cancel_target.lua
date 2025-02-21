-- 用于增加/减少目标的选人函数的ActiveSkill
local addAndCancelSkill = fk.CreateSkill{
  name = "#util_addandcanceltarget",
}

Fk:loadTranslationTable{
  ["#util_addandcanceltarget"] = "增减目标",
}

addAndCancelSkill:addEffect('active', {
  card_num = 0,
  card_filter = Util.FalseFunc,
  target_filter = function(self, player, to_select, selected, _, _, extra_data)
    if not table.contains(extra_data.targets, to_select.id) then return false end
    if selected[1] then
      if table.contains(extra_data.extra_data, selected[1].id) then
        return table.contains(extra_data.extra_data, to_select.id) and #selected < extra_data.sub_max_num
      else
        return (not table.contains(extra_data.extra_data, to_select.id)) and #selected < extra_data.add_max_num
      end
    else
      if table.contains(extra_data.extra_data, to_select) then
        return #selected < extra_data.sub_max_num
      else
        return #selected < extra_data.add_max_num
      end
    end
  end,
  target_tip = function(_, player, to_select, selected, _, selectable, extra_data)
    if not selectable or table.contains(selected, to_select) then return end
    if type(extra_data.extra_data) == "table" then
      if table.contains(extra_data.extra_data, to_select) then
        return { {content = "@@CancelTarget", type = "warning"} }
      else
        return { {content = "@@AddTarget", type = "normal"} }
      end
    end
  end,
  feasible = function(self, player, selected)
    if not selected[1] then return false end
    if table.contains(self.extra_data, selected[1]) then
      return #selected >= self.sub_min_num
    else
      return #selected >= self.add_min_num
    end
  end
})

return addAndCancelSkill
