---@class Utility
local Utility = require 'packages/utility/_base'

-- 不用return


--- 更改某角色蓄力技的能量或能量上限
---@param player ServerPlayer @ 角色
---@param num? integer @ 改变的能量
---@param max? integer @ 改变的能量上限
Utility.skillCharged = function(player, num, max)
  local room = player.room
  num = num or 0
  max = max or 0
  local max_num = math.max(0, player:getMark("skill_charge_max") + max)
  local new_num = math.min(max_num, math.max(0, player:getMark("skill_charge") + num))
  room:setPlayerMark(player, "skill_charge_max", max_num)
  room:setPlayerMark(player, "skill_charge", new_num)
  room:setPlayerMark(player, "@skill_charge", (max_num == 0 and new_num == 0) and 0 or (new_num.."/"..max_num))
end
Fk:loadTranslationTable{
  ["@skill_charge"] = "蓄力",
}

--- 进行谋奕/对策
---@param room Room @ 房间
---@param from ServerPlayer @ 拥有技能的角色
---@param to ServerPlayer @ 被发动技能的角色
---@param from_choices string[] @ 第一个角色的选项
---@param to_choices string[] @ 第二个角色的选项
---@param skillName string @ 技能名
---@param msg_type? integer @ 发送消息的类型 1:谋奕 2:对策 其他：不发送
---@param prompts? string|string[] @ 询问选择时的提示信息
---@return string[] @ 返回双方的选项
Utility.doStrategy = function(room, from, to, from_choices, to_choices, skillName, msg_type, prompts)
  msg_type = msg_type or 0
  if not prompts then
    if msg_type == 1 then
      prompts = {"#strategy-ask:" .. from.id, "#strategy-ask:" .. from.id}
    elseif msg_type == 2 then
      prompts = {"#countermeausre-ask:" .. from.id, "#countermeausre-ask:" .. from.id}
    else
      prompts = {"",""}
    end
  elseif type(prompts) == "string" then
    prompts = {prompts, prompts}
  end
  local req = Request:new({from, to}, "AskForChoice")
  req:setData(from, { from_choices, from_choices, skillName, prompts[1], true })
  req:setData(to, { to_choices, to_choices, skillName, prompts[2], true })
  req:setDefaultReply(from, table.random(from_choices, 1))
  req:setDefaultReply(to, table.random(to_choices, 1))
  req.focus_text = skillName
  req.receive_decode = false
  local from_c = req:getResult(from)
  local to_c = req:getResult(to)
  local same = (table.indexOf(from_choices, from_c) == table.indexOf(to_choices, to_c))
  if msg_type == 1 then
    room:sendLog{
      type = "#StrategiesResult",
      from = from.id,
      to = {to.id},
      arg = same and "strategy_failed" or "strategy_success",
      toast = true,
    }
  elseif msg_type == 2 then
    room:sendLog{
      type = "#StrategiesResult",
      from = from.id,
      to = {to.id},
      arg = same and "countermeausre_success" or "countermeausre_failed",
      toast = true,
    }
  end
  return {from_c, to_c}
end
Fk:loadTranslationTable{
  ["strategy_success"] = "谋奕 成功",
  ["strategy_failed"] = "谋奕 失败",
  ["countermeausre_success"] = "对策 成功",
  ["countermeausre_failed"] = "对策 失败",
  ["#strategy-ask"] = "请响应“谋奕”：若你与对方选择不同，则%src谋奕成功，反之%src失败",
  ["#countermeausre-ask"] = "请响应“对策”：若你与对方选择相同，则%src对策成功，反之%src失败",
  ["#StrategiesResult"] = "%from 对 %to %arg",
}

-- 仁区相关

--- 获取仁区中的牌
---@param room Room | AbstractRoom @ 房间
---@return integer[]
Utility.GetRenPile = function(room)
  local cards = room:getBanner("@$RenPile")
  if cards == nil then
    room:setBanner("@$RenPile", cards)
    return {}
  end
  return table.simpleClone(cards)
end


--- 将一些牌加入仁区
---@param player ServerPlayer @ 移动操作者
---@param cards integer|integer[]|Card|Card[] @ 要加入仁区的牌
---@param skillName? string @ 移动的技能名
Utility.AddToRenPile = function(player, cards, skillName)
  local room = player.room
  skillName = skillName or ""
  room:addSkill(Fk.skills["#RenPileTrigger"])
  local ids = Card:getIdList(cards)

  local movesSplitedByOwner = {}
  for _, cardId in ipairs(ids) do
    local moveFound = table.find(movesSplitedByOwner, function(move)
      return move.from == room.owner_map[cardId]
    end)

    if moveFound then
      table.insert(moveFound.ids, cardId)
    else
      table.insert(movesSplitedByOwner, {
        ids = { cardId },
        from = room.owner_map[cardId],
        toArea = Card.Void,
        moveReason = fk.ReasonJustMove,
        skillName = skillName,
        moveVisible = true,
        proposer = player,
        extra_data = { addtorenpile = true},
      })
    end
  end

  room:moveCards(table.unpack(movesSplitedByOwner))
end

Fk:loadTranslationTable{
  ["#AddToRenPile"] = "%card 因%arg 移入“仁”区",
  ["#OverflowFromRenPile"] = "%card 从“仁”区溢出",
  ["$RenPile"] = "仁区",
  ["@$RenPile"] = "仁区",
  ["RenPile_href"] = "仁区是一个存于场上，用于存放牌的公共区域。<br>仁区中的牌上限为6张，当仁区中的牌超过6张时，最先置入仁区中的牌将置入弃牌堆。",
  ["#RenPileTrigger"] = "仁区",
}

-- 整肃相关

---@param player ServerPlayer @ 发起整肃的玩家
---@param target ServerPlayer @ 执行整肃的玩家
---@param skillName string @ 技能名
---@param prompt string @ 提示信息
--- 发起整肃
Utility.startZhengsu = function(player, target, skillName, prompt)
  skillName = skillName or ""
  prompt = prompt or ""
  local room = player.room
  local choices = {"zhengsu_leijin", "zhengsu_bianzhen", "zhengsu_mingzhi"}
  local choice = room:askToChoice(player, {
    choices = choices,
    skill_name = skillName,
    prompt = prompt,
    detailed = true,
  })
  local mark_name = "@" .. choice .. "-turn"
  if target:getMark(mark_name) == 0 then
    room:setPlayerMark(target, mark_name, "")
  end
  room:addTableMark(target, "zhengsu_skill-turn", {player.id, skillName, choice})
  room.logic:addTriggerSkill(Fk.skills["mobile_zhengsu_recorder"])
end

---@param player ServerPlayer @ 发起整肃的玩家
---@param target ServerPlayer @ 获得奖励的玩家
---@param reward string|null @ 要获得的奖励（"draw2"|"recover"）
---@param skillName string @ 技能名
--- 获得整肃奖励
Utility.rewardZhengsu = function(player, target, reward, skillName)
  reward = reward or "draw2"
  local room = player.room
  if reward == "draw2" then
    room:drawCards(target, 2, skillName)
  elseif reward == "recover" then
    if target:isWounded() then
      room:recover({
        who = target,
        num = 1,
        recoverBy = target,
        skillName = skillName
      })
    end
  end
end

---@param player ServerPlayer @ 发起整肃的玩家
---@param target ServerPlayer @ 执行整肃的玩家
---@param skillName string @ 技能名
--- 检查整肃成功
Utility.checkZhengsu = function(player, target, skillName)
  for _, v in ipairs(target:getTableMark("zhengsu_skill-turn")) do
    if v[2] == skillName and v[1] == player.id then
      return target:getMark("@" .. v[3].. "-turn") == "zhengsu_success"
    end
  end
  return false
end

Fk:loadTranslationTable{
  ["zhengsu_leijin"] = "擂进",
  ["@zhengsu_leijin-turn"] = "擂进",
  [":zhengsu_leijin"] = "出牌阶段内，至少使用3张牌，使用牌点数递增",
  ["zhengsu_bianzhen"] = "变阵",
  ["@zhengsu_bianzhen-turn"] = "变阵",
  [":zhengsu_bianzhen"] = "出牌阶段内，至少使用2张牌，使用牌花色相同",
  ["zhengsu_mingzhi"] = "鸣止",
  ["@zhengsu_mingzhi-turn"] = "鸣止",
  [":zhengsu_mingzhi"] = "弃牌阶段内，至少弃置2张牌，弃置牌花色均不同",
  ["zhengsu_failure"] = "失败",
  ["zhengsu_success"] = "成功",

  ["zhengsu_desc"] = "<b>#整肃：</b>"..
  "<br>技能发动者从擂进、变阵、鸣止中选择一项令目标执行，若本回合“整肃”成功，则弃牌阶段结束时获得“整肃奖励”。"..
  "<br><b>擂进：</b>出牌阶段内，使用的所有牌点数需递增，且至少使用三张牌。"..
  "<br><b>变阵：</b>出牌阶段内，使用的所有牌花色需相同，且至少使用两张牌。"..
  "<br><b>鸣止：</b>弃牌阶段内，弃置的所有牌花色均不同，且至少弃置两张牌。"..
  "<br><b>整肃奖励：</b>摸两张牌或回复1点体力。",
}

--- 从移动事件数据中获得一名角色失去的牌数。由于手杀服规，使用装备牌不算失去装备，需要排除
---@param player ServerPlayer
---@param data table
---@return integer[] @ 失去的牌
Utility.getLostCardsFromMove = function(player, data)
  local equipUsing = {}
  local parentUseData = player.room.logic:getCurrentEvent():findParent(GameEvent.UseCard)
  if parentUseData then
    local use = parentUseData.data
    if use.card.type == Card.TypeEquip and use.from == player then
      equipUsing = Card:getIdList(use.card)
    end
  end
  local ids = {}
  for _, move in ipairs(data) do
    for _, info in ipairs(move.moveInfo) do
      if not table.contains(equipUsing, info.cardId) then
        if move.from == player and (info.fromArea == Card.PlayerHand or info.fromArea == Card.PlayerEquip) then
          table.insert(ids, info.cardId)
        end
      else
        if (move.to ~= player or move.toArea ~= Card.PlayerEquip) and info.fromArea == Card.Processing then
          table.insert(ids, info.cardId)
        end
      end
    end
  end
  return ids
end

Fk:addQmlMark{
  name = "mou__xieli",
  qml_path = function(name, value, p)
    return "packages/utility/qml/XiejiBox"
  end,
  how_to_show = function(name, value, p)
    if type(value) == "table" then
      local target = Fk:currentRoom():getPlayerById(value[1])
      if target then return Fk:translate("seat#" .. target.seat) end
    end
    return " "
  end,
}

---@param player ServerPlayer @ 发起协力的角色
---@param target ServerPlayer @ 协力的合作角色
---@return boolean @是否协力成功
Utility.checkXieli = function (player, target)
  local room = player.room
  local mark = player:getTableMark("@[mou__xieli]")
  if #mark == 0 then return false end
  local pid = mark[1]
  if pid == target.id then
    local choice = mark[2]
    local event_id = mark[3]
    if choice == "xieli_tongchou" then
      local n = 0
      local events = room.logic:getActualDamageEvents(999, function(e)
        return e.data.from == player or e.data.from == target
      end, nil, event_id)
      for _, e in ipairs(events) do
        n = n + e.data.damage
      end
      return n >= 4
    elseif choice == "xieli_bingjin" then
      local n = 0
      room.logic:getEventsByRule(GameEvent.MoveCards, 999, function(e)
        for _, move in ipairs(e.data) do
          if move.moveReason == fk.ReasonDraw and (move.to == player or move.to == target) then
            for _, info in ipairs(move.moveInfo) do
              if info.fromArea == Card.DrawPile then
                n = n + 1
              end
            end
          end
        end
        return false
      end, event_id)
      return n >= 8
    elseif choice == "xieli_shucai" then
      local suits = {}
      room.logic:getEventsByRule(GameEvent.MoveCards, 999, function(e)
        for _, move in ipairs(e.data) do
          if move.moveReason == fk.ReasonDiscard and (move.from == player or move.from == target) then
            for _, info in ipairs(move.moveInfo) do
              if info.fromArea == Card.PlayerHand or info.fromArea == Card.PlayerEquip then
                local suit = Fk:getCardById(info.cardId).suit
                if suit ~= Card.NoSuit then
                  table.insertIfNeed(suits, suit)
                end
              end
            end
          end
        end
        return false
      end, event_id)
      return #suits == 4
    elseif choice == "xieli_luli" then
      local suits = {}
      room.logic:getEventsByRule(GameEvent.UseCard, 999, function(e)
        local use = e.data
        if use.from == player or use.from == target then
          local suit = use.card.suit
          if suit ~= Card.NoSuit then
            table.insertIfNeed(suits, suit)
          end
        end
      end, event_id)
      if #suits == 4 then return true end
      room.logic:getEventsByRule(GameEvent.RespondCard, 999, function(e)
        local resp = e.data
        if resp.from == player or resp.from == target then
          local suit = resp.card.suit
          if suit ~= Card.NoSuit then
            table.insertIfNeed(suits, suit)
          end
        end
      end, event_id)
      return #suits == 4
    end
  end
  return false
end

Fk:loadTranslationTable{
  ["@[mou__xieli]"] = "协力",
  ["xieli_tongchou"] = "同仇",
  [":xieli_tongchou"] = "你与其造成的伤害值之和不小于4",
  ["xieli_bingjin"] = "并进",
  [":xieli_bingjin"] = "你与其总计摸过至少8张牌",
  ["xieli_shucai"] = "疏财",
  [":xieli_shucai"] = "你与其弃置的牌中包含4种花色",
  ["xieli_luli"] = "勠力",
  [":xieli_luli"] = "你与其使用或打出的牌中包含4种花色",
}
