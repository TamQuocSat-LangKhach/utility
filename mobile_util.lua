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
  -- local data1 = json.encode({ from_choices, from_choices, skillName, prompts[1], true })
  -- from.request_data = data1
  -- local data2 = json.encode({ to_choices, to_choices, skillName, prompts[2], true })
  -- to.request_data = data2
  -- room:notifyMoveFocus({from,to}, "AskForChoice")
  -- room:doBroadcastRequest("AskForChoice", {from,to})
  -- local from_c = from.reply_ready and from.client_reply or table.random(from_choices)
  -- local to_c = to.reply_ready and to.client_reply or table.random(to_choices)
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

local afterRenMove = fk.CreateTriggerSkill{
  name = "#AfterRenMove",
  priority = 0.001,

  refresh_events = {fk.AfterCardsMove},
  can_refresh = function(self, event, target, player, data)
    if player.seat == 1 and player.room.tag["ren"] then
      for _, move in ipairs(data) do
        if move.toArea ~= Card.Void then
          for _, info in ipairs(move.moveInfo) do
            if table.contains(player.room.tag["ren"], info.cardId) then
              return true
            end
          end
        end
      end
    end
  end,
  on_refresh = function(self, event, target, player, data)
    local room = player.room
    for _, move in ipairs(data) do
      if move.toArea ~= Card.Void then
        for _, info in ipairs(move.moveInfo) do
          if table.contains(room.tag["ren"], info.cardId) then
            Utility.NotifyRenPile(room)
            room.logic:trigger("fk.AfterRenMove", nil, info)
          end
        end
      end
    end
  end,
}
Fk:addSkill(afterRenMove)

---@param room Room @ 房间
---@return integer[]
Utility.GetRenPile = function(room)
  local cards = room.tag["ren"] or {}
  room.tag["ren"] = table.filter(cards, function (id)
    return room:getCardArea(id) == Card.Void
  end)
  return table.simpleClone(room.tag["ren"])
end

---@param room Room @ 房间
Utility.NotifyRenPile = function(room)
  room:sendLog{
    type = "#NotifyRenPile",
    arg = #Utility.GetRenPile(room),
    card = Utility.GetRenPile(room),
  }
  room:setBanner("@$RenPile", table.simpleClone(room.tag["ren"]))
end

---@param room Room @ 房间
---@param card integer|integer[]|Card|Card[] @ 要加入仁区的牌/id/intList
---@param skillName string @ 移动的技能名
---@param proposer integer @ 移动操作者的id
Utility.AddToRenPile = function(room, card, skillName, proposer)
  room.logic:addTriggerSkill(AfterRenMove)
  local ids = Card:getIdList(card)
  room.tag["ren"] = room.tag["ren"] or {}
  local add, remove = {}, {}
  local ren_cards = table.simpleClone(room.tag["ren"])
  local ren_limit = 6
  for i = 1, ren_limit do
    local id = ids[i]
    if not id then break end
    table.insert(ren_cards, id)
    table.insert(add, id)
  end
  if #ren_cards > ren_limit then
    for i = #ren_cards - ren_limit, 1, -1 do
      table.insert(remove, table.remove(room.tag["ren"], i))
    end
  end
  local moveInfos = {}
  if #add > 0 then
    table.insertTable(room.tag["ren"], add)
    table.insert(moveInfos, {
      ids = add,
      from = room.owner_map[add[1]],
      toArea = Card.Void,
      moveReason = fk.ReasonJustMove,
      skillName = skillName,
      moveVisible = true,
      proposer = proposer,
    })
    room:sendLog{
      type = "#AddToRenPile",
      arg = #add,
      card = add,
    }
  end
  if #remove > 0 then
    local info = {
      ids = remove,
      toArea = Card.DiscardPile,
      moveReason = fk.ReasonPutIntoDiscardPile,
      skillName = "ren_overflow",
      moveVisible = true,
    }
    table.insert(moveInfos, info)
    room:sendLog{
      type = "#OverflowFromRenPile",
      arg = #remove,
      card = remove,
    }
  end
  if #moveInfos > 0 then
    room:moveCards(table.unpack(moveInfos))
  end
  Utility.NotifyRenPile(room)
end

Fk:loadTranslationTable{
  ["#NotifyRenPile"] = "“仁”区现有 %arg 张牌 %card",
  ["#AddToRenPile"] = "%arg 张牌被移入“仁”区 %card",
  ["#OverflowFromRenPile"] = "%arg 张牌从“仁”区溢出 %card",
  ["$RenPile"] = "仁区",
  ["@$RenPile"] = "仁区",
}

-- 整肃相关
--- 整肃记录技能
local mobile_zhengsu_recorder = fk.CreateTriggerSkill{
  name = "mobile_zhengsu_recorder",

  refresh_events = {fk.CardUsing, fk.AfterCardsMove, fk.EventPhaseEnd},
  can_refresh = function(self, event, target, player, data)
    if player.dead then return end
    local mark1, mark2, mark3 = "@zhengsu_bianzhen-turn", "@zhengsu_leijin-turn", "@zhengsu_mingzhi-turn"
    local check_play = player.phase == Player.Play and
    ((player:getMark(mark1) == "" or type(player:getMark(mark1)) == "table")
    or (player:getMark(mark2) == "" or type(player:getMark(mark2)) == "table"))
    local check_discard = player.phase == Player.Discard and
    (player:getMark(mark3) == "" or type(player:getMark(mark3)) == "table")
    if event == fk.CardUsing then
      return target == player and check_play
    elseif event == fk.AfterCardsMove then
      return check_discard
    else
      return target == player and (check_play or check_discard)
    end
  end,
  on_refresh = function(self, event, target, player, data)
    local room = player.room
    local broadcastFailure = function (p, choice)
      room:setPlayerMark(p, "@"..choice.."-turn", "zhengsu_failure")
      for _, v in ipairs(p:getTableMark("zhengsu_skill-turn")) do
        if choice == v[3] then
          room:getPlayerById(v[1]):broadcastSkillInvoke(v[2], 3)
        end
      end
    end
    if event == fk.CardUsing then
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
    elseif event == fk.AfterCardsMove then
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
    elseif event == fk.EventPhaseEnd then
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
    end
  end,
}
Fk:addSkill(mobile_zhengsu_recorder)

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
  local choice = room:askForChoice(player, choices, skillName, prompt, true)
  local mark_name = "@" .. choice .. "-turn"
  if target:getMark(mark_name) == 0 then
    room:setPlayerMark(target, mark_name, "")
  end
  room:addTableMark(target, "zhengsu_skill-turn", {player.id, skillName, choice})
  room.logic:addTriggerSkill(mobile_zhengsu_recorder)
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
    local use = parentUseData.data[1]
    if use.card.type == Card.TypeEquip and use.from == player.id then
      equipUsing = Card:getIdList(use.card)
    end
  end
  local ids = {}
  for _, move in ipairs(data) do
    for _, info in ipairs(move.moveInfo) do
      if not table.contains(equipUsing, info.cardId) then
        if move.from == player.id and (info.fromArea == Card.PlayerHand or info.fromArea == Card.PlayerEquip) then
          table.insert(ids, info.cardId)
        end
      else
        if (move.to ~= player.id or move.toArea ~= Card.PlayerEquip) and info.fromArea == Card.Processing then
          table.insert(ids, info.cardId)
        end
      end
    end
  end
  return ids
end









