--- 整肃记录技能
local mobile_zhengsu_recorder = fk.CreateSkill{
  name = "mobile_zhengsu_recorder",
}

local broadcastFailure = function (p, choice)
  local room = p.room

  room:setPlayerMark(p, "@"..choice.."-turn", "zhengsu_failure")
  for _, v in ipairs(p:getTableMark("zhengsu_skill-turn")) do
    if choice == v[3] then
      room:getPlayerById(v[1]):broadcastSkillInvoke(v[2], 3)
    end
  end
end

mobile_zhengsu_recorder:addEffect(fk.CardUsing, {
  can_refresh = function(self, event, target, player, data)
    if player.dead then return end
    local mark1, mark2 = "@zhengsu_bianzhen-turn", "@zhengsu_leijin-turn"
    return target == player and player.phase == Player.Play and
      ((player:getMark(mark1) == "" or type(player:getMark(mark1)) == "table")
      or (player:getMark(mark2) == "" or type(player:getMark(mark2)) == "table"))
  end,
  on_refresh = function(self, event, target, player, data)
    local room = player.room
    local mark = player:getMark("@zhengsu_leijin-turn")
    if (mark == "" or type(mark) == "table") and data.card.number > 0 then
      if mark == "" then
        mark = {}
      else
        mark = table.map(mark, function(v) return Card:strToNumber(v) end)
      end
      table.insert(mark, data.card.number)
      if #mark > 3 then table.remove(mark, 1) end
      if #mark > 1 and mark[#mark] <= mark[#mark-1] then
        broadcastFailure(player, "zhengsu_leijin")
      else
        mark = table.map(mark, function(v) return Card:getNumberStr(v) end)
        room:setPlayerMark(player, "@zhengsu_leijin-turn", mark)
      end
    end
    mark = player:getMark("@zhengsu_bianzhen-turn")
    if (mark == "" or type(mark) == "table") then
      local suit = data.card:getSuitString(true)
      if suit ~= "log_nosuit" then
        if mark == "" then mark = {} end
        if table.find(mark, function(v) return v ~= suit end) then
          broadcastFailure(player, "zhengsu_bianzhen")
          return
        elseif #mark < 2 then
          table.insert(mark, suit)
        end
        room:setPlayerMark(player, "@zhengsu_bianzhen-turn", mark)
      end
    end
  end,
})

mobile_zhengsu_recorder:addEffect(fk.AfterCardsMove, {
  can_refresh = function(self, event, target, player, data)
    if player.dead then return end
    local mark3 = "@zhengsu_mingzhi-turn"
    return player.phase == Player.Discard and
      (player:getMark(mark3) == "" or type(player:getMark(mark3)) == "table")
  end,
  on_refresh = function(self, event, target, player, data)
    local room = player.room
    local mark = player:getTableMark("@zhengsu_mingzhi-turn")
    for _, move in ipairs(data) do
      if move.from == player.id and move.skillName == "phase_discard" then
        for _, info in ipairs(move.moveInfo) do
          if info.fromArea == Card.PlayerHand then
            local suit = Fk:getCardById(info.cardId):getSuitString(true)
            if not table.insertIfNeed(mark, suit) then
              broadcastFailure(player, "zhengsu_mingzhi")
              return
            end
          end
        end
      end
    end
    room:setPlayerMark(player, "@zhengsu_mingzhi-turn", mark)
  end,
})

mobile_zhengsu_recorder:addEffect(fk.EventPhaseEnd, {
  can_refresh = function(self, event, target, player, data)
    if player.dead then return end
    local mark1, mark2, mark3 = "@zhengsu_bianzhen-turn", "@zhengsu_leijin-turn", "@zhengsu_mingzhi-turn"
    local check_play = player.phase == Player.Play and
    ((player:getMark(mark1) == "" or type(player:getMark(mark1)) == "table")
    or (player:getMark(mark2) == "" or type(player:getMark(mark2)) == "table"))
    local check_discard = player.phase == Player.Discard and
    (player:getMark(mark3) == "" or type(player:getMark(mark3)) == "table")
    return target == player and (check_play or check_discard)
  end,
  on_refresh = function(self, event, target, player, data)
    local room = player.room
    local mark1, mark2, mark3 = "@zhengsu_bianzhen-turn", "@zhengsu_leijin-turn", "@zhengsu_mingzhi-turn"
    if player.phase == Player.Play then
      if player:getMark(mark1) ~= 0 then
        if #player:getTableMark(mark1) >= 2 then
          room:setPlayerMark(player, mark1, "zhengsu_success")
        else
          broadcastFailure(player, "zhengsu_bianzhen")
        end
      end
      if player:getMark(mark2) ~= 0 then
        if #player:getTableMark(mark2) >= 3 then
          room:setPlayerMark(player, mark2, "zhengsu_success")
        else
          broadcastFailure(player, "zhengsu_leijin")
        end
      end
    else
      if #player:getTableMark(mark3) >= 2 then
        room:setPlayerMark(player, mark3, "zhengsu_success")
      else
        broadcastFailure(player, "zhengsu_mingzhi")
      end
    end
  end,
})

return mobile_zhengsu_recorder
