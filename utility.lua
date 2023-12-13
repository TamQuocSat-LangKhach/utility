-- 这个文件用来堆一些常用的函数，视情况可以分成多个文件
-- 因为不是拓展包，所以不能用init.lua（否则会被当拓展包加载并报错）
-- 因为本体里面已经有util了所以命名为完整版utility

-- 要使用的话在拓展开头加一句 local U = require "packages/utility/utility" 即可(注意别加.lua)

local Utility = require 'packages/utility/_base'

-- 在指定历史范围中找符合条件的事件（逆序）
---@param room Room
---@param eventType integer @ 要查找的事件类型
---@param func fun(e: GameEvent): boolean @ 过滤用的函数
---@param n integer @ 最多找多少个
---@param end_id integer @ 查询历史范围：从最后的事件开始逆序查找直到id为end_id的事件（不含）
---@return GameEvent[] @ 找到的符合条件的所有事件，最多n个但不保证有n个
Utility.getEventsByRule = function(room, eventType, n, func, end_id)
  local ret = {}
	local events = room.logic.event_recorder[eventType] or Util.DummyTable
  for i = #events, 1, -1 do
    local e = events[i]
    if e.id <= end_id then break end
    if func(e) then
      table.insert(ret, e)
      if #ret >= n then break end
    end
  end
  return ret
end

-- 用来判定一些卡牌在此次移动事件发生之后没有再被移动过。
--
-- 根据规则集，如果需要在卡牌移动后对参与此事件的卡牌进行操作，是需要过一遍这个检测的(=ﾟωﾟ)ﾉ
---@param room Room
---@param cards integer[] @ 待判定的卡牌
---@param end_id? integer @ 查询历史范围：从最后的事件开始逆序查找直到id为end_id的事件（不含），缺省值为当前移动事件的id
---@return integer[] @ 返回满足条件的卡牌的id列表
Utility.moveCardsHoldingAreaCheck = function(room, cards, end_id)
  if #cards == 0 then return {} end
  if end_id == nil then
    local move_event = room.logic:getCurrentEvent():findParent(GameEvent.MoveCards, true)
    if move_event == nil then return {} end
    end_id = move_event.id
  end
  local ret = table.simpleClone(cards)
  Utility.getEventsByRule(room, GameEvent.MoveCards, 1, function (e)
    for _, move in ipairs(e.data) do
      for _, info in ipairs(move.moveInfo) do
        table.removeOne(ret, info.cardId)
      end
    end
    return (#ret == 0)
  end, end_id)
  return ret
end




-- 使用牌的合法性检测
---@param room Room
---@param player ServerPlayer @ 使用来源
---@param card Card @ 被使用的卡牌
---@param times_limited? boolean @ 是否有次数限制
---@return bool
Utility.canUseCard = function(room, player, card, times_limited)
  if player:prohibitUse(card) then return false end
  if not times_limited then
    room:setPlayerMark(player, MarkEnum.BypassTimesLimit .. "-tmp", 1)
  end
  local can_use = player:canUse(card)
  if not times_limited then
    room:setPlayerMark(player, MarkEnum.BypassTimesLimit .. "-tmp", 0)
  end
  return can_use
end

-- 一名角色A对角色B使用牌的合法性检测
---@param room Room
---@param from ServerPlayer @ 使用来源
---@param to ServerPlayer @ 目标角色
---@param card Card @ 被使用的卡牌
---@param distance_limited? boolean @ 是否有距离关系的限制
---@param times_limited? boolean @ 是否有次数限制
---@return bool
Utility.canUseCardTo = function(room, from, to, card, distance_limited, times_limited)
  if from:prohibitUse(card) or from:isProhibited(to, card) then return false end
  if not times_limited then
    room:setPlayerMark(from, MarkEnum.BypassTimesLimit .. "-tmp", 1)
  end
  local can_use = from:canUse(card)
  if not times_limited then
    room:setPlayerMark(from, MarkEnum.BypassTimesLimit .. "-tmp", 0)
  end
  return can_use and card.skill:modTargetFilter(to.id, {}, from.id, card, distance_limited)
end

-- 获取使用牌的合法额外目标（【借刀杀人】等带副目标的卡牌除外）
---@param room Room
---@param data CardUseStruct @ 使用事件的data
---@param bypass_distances boolean? @ 是否无距离关系的限制
---@param use_AimGroup boolean? @ 某些场合需要使用AimGroup，by smart Ho-spair
---@return integer[] @ 返回满足条件的player的id列表
Utility.getUseExtraTargets = function(room, data, bypass_distances, use_AimGroup)
  if not (data.card.type == Card.TypeBasic or data.card:isCommonTrick()) then return {} end
  if data.card.skill:getMinTargetNum() > 1 then return {} end --stupid collateral
  local tos = {}
  local current_targets = use_AimGroup and AimGroup:getAllTargets(data.tos) or TargetGroup:getRealTargets(data.tos)
  for _, p in ipairs(room.alive_players) do
    if not table.contains(current_targets, p.id) and not room:getPlayerById(data.from):isProhibited(p, data.card) then
      if data.card.skill:modTargetFilter(p.id, {}, data.from, data.card, not bypass_distances) then
        table.insert(tos, p.id)
      end
    end
  end
  return tos
end

-- 判断一名角色为一个使用事件的唯一目标
--
-- 规则集描述为目标角色数为1，是不包括死亡角色且不计算重复目标的
---@param player ServerPlayer @ 目标角色
---@param data CardUseStruct @ 使用事件的data
---@param event Event @ 使用事件的时机（需判断使用TargetGroup还是AimGroup，by smart Ho-spair）
---@return boolean
Utility.isOnlyTarget = function(player, data, event)
  if data.tos == nil then return false end
  local tos = {}
  if table.contains({ fk.TargetSpecifying, fk.TargetConfirming, fk.TargetSpecified, fk.TargetConfirmed }, event) then
    tos = AimGroup:getAllTargets(data.tos)
  else
    tos = TargetGroup:getRealTargets(data.tos)
  end
  if not table.contains(tos, player.id) then return false end
  for _, p in ipairs(player.room.alive_players) do
    if p ~= player and table.contains(tos, p.id) then
      return false
    end
  end
  return true
end

-- 判断一张牌是否为非转化的卡牌（不为转化使用且对应实体牌数为1且两者牌名相同）
---@param card Card @ 待判别的卡牌
---@return boolean
Utility.isPureCard = function(card)
  return not card:isVirtual() and card.trueName == Fk:getCardById(card.id, true).trueName
end

-- 判断一张虚拟牌是否有对应的实体牌（规则集定义）
---@param card Card @ 待判别的卡牌
---@param room Room
---@return boolean
Utility.hasFullRealCard = function(room, card)
  local cardlist = card:isVirtual() and card.subcards or {card.id}
  return #cardlist > 0 and table.every(cardlist, function (id)
    return room:getCardArea(id) == Card.Processing
  end)
end

-- 令两名角色交换特定的牌（FIXME：暂时只能正面朝上移动过）
---@param room Room
---@param player ServerPlayer @ 移动的操作者（proposer）
---@param targetOne ServerPlayer @ 移动的目标1玩家
---@param targetTwo ServerPlayer @ 移动的目标2玩家
---@param cards1 integer[] @ 从属于目标1的卡牌
---@param cards2 integer[] @ 从属于目标2的卡牌
---@param skillName string @ 技能名
Utility.swapCards = function(room, player, targetOne, targetTwo, cards1, cards2, skillName)
  local moveInfos = {}
  if #cards1 > 0 then
    table.insert(moveInfos, {
      from = targetOne.id,
      ids = cards1,
      toArea = Card.Processing,
      moveReason = fk.ReasonExchange,
      proposer = player.id,
      skillName = skillName,
    })
  end
  if #cards2 > 0 then
    table.insert(moveInfos, {
      from = targetTwo.id,
      ids = cards2,
      toArea = Card.Processing,
      moveReason = fk.ReasonExchange,
      proposer = player.id,
      skillName = skillName,
    })
  end
  if #moveInfos > 0 then
    room:moveCards(table.unpack(moveInfos))
  end
  moveInfos = {}
  if not targetTwo.dead then
    local to_ex_cards = table.filter(cards1, function (id)
      return room:getCardArea(id) == Card.Processing
    end)
    if #to_ex_cards > 0 then
      table.insert(moveInfos, {
        ids = to_ex_cards,
        fromArea = Card.Processing,
        to = targetTwo.id,
        toArea = Card.PlayerHand,
        moveReason = fk.ReasonExchange,
        proposer = player.id,
        skillName = skillName,
      })
    end
  end
  if not targetOne.dead then
    local to_ex_cards = table.filter(cards2, function (id)
      return room:getCardArea(id) == Card.Processing
    end)
    if #to_ex_cards > 0 then
      table.insert(moveInfos, {
        ids = to_ex_cards,
        fromArea = Card.Processing,
        to = targetOne.id,
        toArea = Card.PlayerHand,
        moveReason = fk.ReasonExchange,
        proposer = player.id,
        skillName = skillName,
      })
    end
  end
  if #moveInfos > 0 then
    room:moveCards(table.unpack(moveInfos))
  end
  table.insertTable(cards1, cards2)
  local dis_cards = table.filter(cards1, function (id)
    return room:getCardArea(id) == Card.Processing
  end)
  if #dis_cards > 0 then
    room:moveCardTo(dis_cards, Card.DiscardPile, nil, fk.ReasonPutIntoDiscardPile, skillName, nil, true, player.id)
  end
end

-- 令两名角色交换手牌（FIXME：暂时只能正面朝上移动过）
---@param room Room
---@param player ServerPlayer @ 移动的操作者（proposer）
---@param targetOne ServerPlayer @ 移动的目标1玩家
---@param targetTwo ServerPlayer @ 移动的目标2玩家
---@param skillName string @ 技能名
Utility.swapHandCards = function(room, player, targetOne, targetTwo, skillName)
  Utility.swapCards(room, player, targetOne, targetTwo, table.clone(targetOne.player_cards[Player.Hand]),
  table.clone(targetTwo.player_cards[Player.Hand]), skillName)
end

-- 获取角色对应Mark并初始化为table
---@param player Player @ 要被获取标记的那个玩家
---@param mark string @ 标记
---@return table
Utility.getMark = function(player, mark)
  return type(player:getMark(mark)) == "table" and player:getMark(mark) or {}
end


--- 判断一张牌能否移动至某角色的装备区
---@param target Player @ 接受牌的角色
---@param cardId integer @ 移动的牌
---@param convert? boolean @ 是否可以替换装备（默认可以）
---@return boolean 
Utility.canMoveCardIntoEquip = function(target, cardId, convert)
  convert = (convert == nil) and true or convert
  local card = Fk:getCardById(cardId)
  if not (card.sub_type >= 3 and card.sub_type <= 7) then return false end
  if target.dead or table.contains(target:getCardIds("e"), cardId) then return false end
  if target:hasEmptyEquipSlot(card.sub_type) or (#target:getEquipments(card.sub_type) > 0 and convert) then
    return true
  end
  return false
end


--- 将一张牌移动至某角色的装备区，若不合法则置入弃牌堆。目前没做相同副类别装备同时置入的适配(甘露神典韦)
---@param room Room @ 房间
---@param target ServerPlayer @ 接受牌的角色
---@param cards integer|integer[] @ 移动的牌
---@param skillName? string @ 技能名
---@param convert? boolean @ 是否可以替换装备（默认可以）
---@param proposer? ServerPlayer @ 操作者
Utility.moveCardIntoEquip = function (room, target, cards, skillName, convert, proposer)
  convert = (convert == nil) and true or convert
  skillName = skillName or ""
  cards = type(cards) == "table" and cards or {cards}
  local moves = {}
  for _, cardId in ipairs(cards) do
    local card = Fk:getCardById(cardId)
    local fromId = room.owner_map[cardId]
    local proposerId = proposer and proposer.id or nil
    if Utility.canMoveCardIntoEquip(target, cardId, convert) then
      if target:hasEmptyEquipSlot(card.sub_type) then
        table.insert(moves,{ids = {cardId}, from = fromId, to = target.id, toArea = Card.PlayerEquip, moveReason = fk.ReasonPut,skillName = skillName,proposer = proposerId})
      else
        local existingEquip = target:getEquipments(card.sub_type)
        local throw = #existingEquip == 1 and existingEquip[1] or
        room:askForCardChosen(proposer or target, target, {card_data = { {"convertEquip",existingEquip} } }, "convertEquip","#convertEquip")
        table.insert(moves,{ids = {throw}, from = target.id, toArea = Card.DiscardPile, moveReason = fk.ReasonPutIntoDiscardPile, skillName = skillName,proposer = proposerId})
        table.insert(moves,{ids = {cardId}, from = fromId, to = target.id, toArea = Card.PlayerEquip, moveReason = fk.ReasonPut,skillName = skillName,proposer = proposerId})
      end
    else
      table.insert(moves,{ids = {cardId}, from = fromId, toArea = Card.DiscardPile, moveReason = fk.ReasonPutIntoDiscardPile,skillName = skillName})
    end
  end
  room:moveCards(table.unpack(moves))
end
Fk:loadTranslationTable{
  ["convertEquip"] = "替换装备",
  ["#convertEquip"] = "选择一张装备牌被替换",
}

--- 询问玩家交换两堆卡牌中的任意张。
---@param player ServerPlayer @ 要询问的玩家
---@param name1 string @ 第一行卡牌名称
---@param name2 string @ 第一行卡牌名称
---@param cards1 integer[] @ 第一行的卡牌
---@param cards2 integer[] @ 第二行的卡牌
---@param prompt string @ 操作提示（FXIME:暂时无效）
---@param n? integer @ 至多可交换的卡牌数量（不填或负数则无限制）
---@return integer[]
Utility.askForExchange = function(player, name1, name2, cards1, cards2, prompt, n)
  n = n or -1
  return player.room:askForPoxi(player, "qml_exchange", {
    { name1, cards1 },
    { name2, cards2 },
  }, {prompt, n})
end

Fk:addPoxiMethod{
  name = "qml_exchange",
  card_filter = function(to_select, selected, data, extra_data)
    if data == nil or extra_data == nil then return false end
    local cards = data[1][2]
    local x = #table.filter(selected, function (id)
      return table.contains(cards, id)
    end)
    local max_x = extra_data[2]
    if table.contains(cards, to_select) then
      return x < max_x
    end
    return #selected < x + max_x
  end,
  feasible = function(selected, data, extra_data)
    if data == nil then return false end
    local cards = data[1][2]
    return #table.filter(selected, function (id)
      return table.contains(cards, id)
    end) *2 == #selected
  end,
  prompt = function ()
    return "选择要交换的卡牌"
  end
}

Fk:loadTranslationTable{
  ["qml_exchange"] = "换牌",
}

--- 询问玩家选择牌和选项
---@param player ServerPlayer @ 要询问的玩家
---@param cards integer[] @ 待选卡牌
---@param choices string[] @ 可选选项列表（在min和max范围内选择cards里的牌才会被点亮的选项）
---@param skillname string @ 烧条技能名
---@param prompt string @ 操作提示
---@param cancel_choices? string[] @ 可选选项列表（不选择牌时的选项）
---@param min? integer  @ 最小选牌数（默认为1）
---@param max? integer  @ 最大选牌数（默认为1）
---@param all_cards? integer[]  @ 会显示的所有卡牌
---@return integer[], string
Utility.askforChooseCardsAndChoice = function(player, cards, choices, skillname, prompt, cancel_choices, min, max, all_cards)
  cancel_choices = (cancel_choices == nil) and {} or cancel_choices
  min = min or 1
  max = max or 1
  assert(min <= max, "limits error: The upper limit should be less than the lower limit")
  assert(#cards >= min or #cancel_choices > 0, "limits Error: No enough cards")
  assert(#choices > 0 or #cancel_choices > 0, "should have choice to choose")
  local result = player.room:askForCustomDialog(player, skillname,
  "packages/utility/qml/ChooseCardsAndChoiceBox.qml", {
    all_cards or cards,
    choices,
    prompt,
    cancel_choices,
    min,
    max,
    all_cards and table.filter(all_cards, function (id)
      return not table.contains(cards, id)
    end) or {}
  })
  if result ~= "" then
    local reply = json.decode(result)
    return reply.cards, reply.choice
  end
  if #cancel_choices > 0 then
    return {}, cancel_choices[1]
  end
  return table.random(cards, min), choices[1]
end

--- 询问玩家观看一些卡牌并选择一项
---@param player ServerPlayer @ 要询问的玩家
---@param cards integer[] @ 待选卡牌
---@param choices string[] @ 可选选项列表
---@param skillname string @ 烧条技能名
---@param prompt? string @ 操作提示
---@return string
Utility.askforViewCardsAndChoice = function(player, cards, choices, skillname, prompt)
  local _, result = Utility.askforChooseCardsAndChoice(player, cards, {}, skillname, prompt or "#AskForChoice", choices)
  return result
end

--- 让玩家观看一些卡牌（用来取代fillAG式观看）。
---@param player ServerPlayer @ 要询问的玩家
---@param cards integer[] @ 待选卡牌
---@param skillname? string @ 烧条技能名
---@param prompt? string @ 操作提示
Utility.viewCards = function(player, cards, skillname, prompt)
  Utility.askforChooseCardsAndChoice(player, cards, {}, skillname or "utility_viewcards", prompt or "$ViewCards", {"OK"})
end

Fk:loadTranslationTable{
  ["utility_viewcards"] = "观看卡牌",
  ["$ViewCards"] = "请观看卡牌",
}


--- 将一些卡牌同时分配给一些角色。请确保这些牌的所有者一致
---@param room Room @ 房间
---@param list table<integer[]> @ 分配牌和角色的数据，键为字符串化的角色id，值为分配给其的牌
---@param proposer? integer @ 操作者的id
---@param skillName? string @ 技能名
Utility.doDistribution = function (room, list, proposer, skillName)
  skillName = skillName or "distribution_skill"
  local moveInfos = {}
  for str, cards in pairs(list) do
    local to = tonumber(str)
    local toP = room:getPlayerById(to)
    local handcards = toP:getCardIds("h")
    cards = table.filter(cards, function (id) return not table.contains(handcards, id) end)
    if #cards > 0 then
      table.insert(moveInfos, {
      ids = cards,
      from = room.owner_map[cards[1]],
      to = to,
      toArea = Card.PlayerHand,
      moveReason = fk.ReasonGive,
      proposer = proposer,
      skillName = skillName,})
    end
  end
  if #moveInfos > 0 then
    room:moveCards(table.unpack(moveInfos))
  end
end


--- 询问将卡牌分配给任意角色。
---@param player ServerPlayer @ 要询问的玩家
---@param cards integer[] @ 要分配的卡牌
---@param targets ServerPlayer[] @ 可以获得卡牌的角色
---@param skillName? string @ 技能名，影响焦点信息。默认为“分配”
---@param minNum? integer @ 最少交出的卡牌数，默认0
---@param maxNum? integer @ 最多交出的卡牌数，默认所有牌
---@param prompt? string @ 询问提示信息
---@param expand_pile? string @ 可选私人牌堆名称，如要分配你武将牌上的牌请填写
---@param skipMove? boolean @ 是否跳过移动。默认不跳过
---@param single_max? integer|table @ 限制每人能获得的最大牌数。输入整数或(以角色id为键以整数为值)的表
---@return table<integer[]> @ 返回一个表，键为取整后字符串化的角色id，值为分配给其的牌
Utility.askForDistribution = function(player, cards, targets, skillName, minNum, maxNum, prompt, expand_pile, skipMove, single_max)
  local room = player.room
  local _cards = table.simpleClone(cards)
  targets = table.map(targets, Util.IdMapper)
  room:sortPlayersByAction(targets)
  skillName = skillName or "distribution_skill"
  minNum = minNum or 0
  maxNum = maxNum or #cards
  local getString = function(n) return string.format("%.0f", n) end
  local list = {}
  for _, pid in ipairs(targets) do
    list[getString(pid)] = {}
  end
  local data = { expand_pile = expand_pile }
  room:setPlayerMark(player, "distribution_targets", targets)
  local residueMap = {}
  if type(single_max) == "table" then
    for pid, v in pairs(single_max) do
      residueMap[getString(pid)] = v
    end
  end
  local residue_sum = 0
  local residue_num = type(single_max) == "number" and single_max or 9999
  for _, pid in ipairs(targets) do
    local num = residueMap[getString(pid)] or residue_num
    room:setPlayerMark(room:getPlayerById(pid), "distribution_residue", num)
    residue_sum = residue_sum + num
  end
  minNum = math.min(minNum, #_cards, residue_sum)

  while maxNum > 0 and #_cards > 0 do
    room:setPlayerMark(player, "distribution_cards", _cards)
    room:setPlayerMark(player, "distribution_maxnum", maxNum)
    prompt = prompt or ("#distribution_skill:::"..minNum..":"..maxNum)
    local success, dat = room:askForUseActiveSkill(player, "distribution_skill", prompt, minNum == 0, data, true)
    if success and dat then
      local to = dat.targets[1]
      local give_cards = dat.cards
      for _, id in ipairs(give_cards) do
        table.insert(list[getString(to)], id)
        table.removeOne(_cards, id)
        room:setCardMark(Fk:getCardById(id), "@distribution_to", Fk:translate(room:getPlayerById(to).general))
      end
      minNum = math.max(0, minNum - #give_cards)
      maxNum = maxNum - #give_cards
      room:removePlayerMark(room:getPlayerById(to), "distribution_residue", #give_cards)
    else
      break
    end
  end

  for _, id in ipairs(cards) do
    room:setCardMark(Fk:getCardById(id), "@distribution_to", 0)
  end
  for _, pid in ipairs(targets) do
    if minNum == 0 or #_cards == 0 then break end
    local p = room:getPlayerById(pid)
    local num = math.min(p:getMark("distribution_residue"), minNum, #_cards)
    if num > 0 then
      for i = num, 1, -1 do
        local c = table.remove(_cards, i)
        table.insert(list[getString(pid)], c)
        minNum = minNum - 1
      end
    end
  end
  if not skipMove then
    Utility.doDistribution(room, list, player.id, skillName)
  end

  return list
end
local distribution_skill = fk.CreateActiveSkill{
  name = "distribution_skill",
  mute = true,
  min_card_num = 1,
  card_filter = function(self, to_select, selected)
    return #selected < Self:getMark("distribution_maxnum") and table.contains(Self:getMark("distribution_cards"), to_select)
  end,
  target_num = 1,
  target_filter = function(self, to_select, selected, selected_cards)
    return #selected == 0 and #selected_cards > 0 and table.contains(Self:getMark("distribution_targets"), to_select)
    and #selected_cards <= (Fk:currentRoom():getPlayerById(to_select):getMark("distribution_residue"))
  end,
}
Fk:addSkill(distribution_skill)
Fk:loadTranslationTable{
  ["#distribution_skill"] = "请分配这些牌，至少%arg张，剩余%arg2张",
  ["distribution_skill"] = "分配",
  ["@distribution_to"] = "",
}



--- 询问玩家使用一张虚拟卡。注意此函数不判断使用次数限制
---@param room Room @ 房间
---@param player ServerPlayer @ 要询问的玩家
---@param name string @ 使用虚拟卡名
---@param selected_subcards? integer[] @ 虚拟牌的子牌，默认空
---@param skillName? string @ 技能名
---@param prompt? string @ 询问提示信息。默认为：请视为使用xx
---@param cancelable? boolean @ 是否可以取消，默认可以。请勿给借刀设置不可取消
---@param bypass_distances? boolean @ 是否无距离限制。默认有
---@param extraUse? boolean @ 是否不计入次数。默认不计入
---@param extra_data? table @ 额外信息，因技能而异了
---@param skipUse? boolean @ 是否跳过使用。默认不跳过
---@return CardUseStruct @ 返回卡牌使用框架
Utility.askForUseVirtualCard = function(room, player, name, selected_subcards, skillName, prompt, cancelable, bypass_distances, extraUse, extra_data, skipUse)
  selected_subcards = selected_subcards or {}
  extraUse = (extraUse == nil) and true or extraUse
  skillName = skillName or ""
  prompt = prompt or ("#askForUseVirtualCard:::"..skillName..":"..name)
  cancelable = (cancelable == nil) and true or cancelable
  local card = Fk:cloneCard(name)
  card:addSubcards(selected_subcards)
  card.skillName = skillName
  if player:prohibitUse(card) then return end
  local targets = {}
  for _, p in ipairs(room.alive_players) do
    if not player:isProhibited(p, card) and card.skill:modTargetFilter(p.id, {}, player.id, card, not bypass_distances) then
      table.insert(targets, p.id)
    end
  end
  if #targets == 0 then return end
  extra_data = extra_data or {}
  extra_data.view_as_name = name
  extra_data.selected_subcards = selected_subcards
  if bypass_distances then room:setPlayerMark(player, MarkEnum.BypassDistancesLimit .. "-tmp", 1) end -- FIXME: 缺少直接传入无限制的手段
  local success, dat = room:askForUseViewAsSkill(player, "virtual_viewas", prompt, cancelable, extra_data)
  if bypass_distances then room:setPlayerMark(player, MarkEnum.BypassDistancesLimit .. "-tmp", 0) end -- FIXME: 缺少直接传入无限制的手段
  local tos = {}
  if success and dat then
    tos = dat.targets
  else
    if cancelable then return end
    if card.name == "collateral" then return end -- ignore collateral
    local min_card_num = card.skill.min_target_num or 1
    if min_card_num > 0 then -- exclude ex_nihilo, savage_assault
      tos = table.random(targets, min_card_num)
    end
  end
  local use = {
    from = player.id,
    tos = table.map(tos, function(p) return {p} end),
    card = card,
    extraUse = extraUse,
  }
  if not skipUse then
    room:useCard(use)
  end
  return use
end

local virtual_viewas = fk.CreateViewAsSkill{
  name = "virtual_viewas",
  card_filter = Util.FalseFunc,
  view_as = function(self)
    local card = Fk:cloneCard(self.view_as_name)
    card:addSubcards(self.selected_subcards)
    return card
  end,
}
Fk:addSkill(virtual_viewas)
Fk:loadTranslationTable{
  ["virtual_viewas"] = "使用虚拟牌",
  ["#askForUseVirtualCard"] = "%arg：请视为使用 %arg2",
}



--- 判断当前使用/打出事件是否是在使用手牌
---@param player ServerPlayer @ 要判断的使用者
---@param data CardUseStruct @ 当前事件的data
---@return boolean
Utility.IsUsingHandcard = function(player, data)
  local cards = data.card:isVirtual() and data.card.subcards or {data.card.id}
  if #cards == 0 then return end
  local yes = false
  local use = player.room.logic:getCurrentEvent()
  use:searchEvents(GameEvent.MoveCards, 1, function(e)
    if e.parent and e.parent.id == use.id then
      local subcheck = table.simpleClone(cards)
      for _, move in ipairs(e.data) do
        if move.from == player.id and (move.moveReason == fk.ReasonUse or move.moveReason == fk.ReasonResonpse) then
          for _, info in ipairs(move.moveInfo) do
            if table.removeOne(subcheck, info.cardId) and info.fromArea == Card.PlayerHand then
              --continue
            else
              break
            end
          end
        end
      end
      if #subcheck == 0 then
        yes = true
      end
    end
  end)
  return yes
end


--- 询问玩家使用一张手牌中的实体卡。注意此函数不判断使用次数限制
---@param room Room @ 房间
---@param player ServerPlayer @ 要询问的玩家
---@param cards? integer[] @ 可以使用的卡牌，默认为所有手牌
---@param pattern? string @ 选卡规则，与可选卡牌取交集
---@param skillName? string @ 技能名
---@param prompt? string @ 询问提示信息。默认为：请视为使用一张牌
---@param extra_data? table @ 额外信息，因技能而异了
---@param skipUse? boolean @ 是否跳过使用。默认不跳过
---@return CardUseStruct|nil @ 返回卡牌使用框架
Utility.askForUseRealCard = function(room, player, cards, pattern, skillName, prompt, extra_data, skipUse)
  cards = cards or player:getCardIds("h")
  pattern = pattern or "."
  skillName = skillName or ""
  prompt = prompt or ("#askForUseRealCard:::"..skillName)
  local cardIds = {}
  room:setPlayerMark(player, MarkEnum.BypassTimesLimit .. "-tmp", 1) -- FIXME: 缺少直接传入无限制的手段
  for _, cid in ipairs(cards) do
    local card = Fk:getCardById(cid)
    if Exppattern:Parse(pattern):match(card) then
      if player:canUse(card) and not player:prohibitUse(card) then
        table.insert(cardIds, cid)
      end
    end
  end
  extra_data = extra_data or {}
  extra_data.optional_cards = cardIds
  local success, dat = room:askForUseViewAsSkill(player, "realcard_viewas", prompt, true, extra_data)
  room:setPlayerMark(player, MarkEnum.BypassTimesLimit .. "-tmp", 0) -- FIXME: 缺少直接传入无限制的手段
  if not (success and dat) then return end
  local use = {
    from = player.id,
    tos = table.map(dat.targets, function(p) return {p} end),
    card = Fk:getCardById(dat.cards[1]),
    extraUse = true,
  }
  if not skipUse then
    room:useCard(use)
  end
  return use
end
local realcard_viewas = fk.CreateViewAsSkill{
  name = "realcard_viewas",
  card_filter = function (self, to_select, selected)
    return #selected == 0 and table.contains(self.optional_cards, to_select)
  end,
  view_as = function(self, cards)
    if #cards == 1 then
      return Fk:getCardById(cards[1])
    end
  end,
}
Fk:addSkill(realcard_viewas)
Fk:loadTranslationTable{
  ["realcard_viewas"] = "使用",
  ["#askForUseRealCard"] = "%arg：请使用一张牌",
}

--- 询问玩家使用一张牌（支持使用视为技）
---
--- 额外的，你不能使用自己的装备牌
---@param room Room @ 房间
---@param player ServerPlayer @ 要询问的玩家
---@param cards? integer[] @ 可以使用的卡牌，默认包括手牌和“如手牌”
---@param pattern? string @ 选卡规则，与可用卡牌取交集
---@param skillName? string @ 技能名
---@param prompt? string @ 询问提示信息。默认为：请使用一张牌
---@param extra_data? table @ 额外信息，因技能而异了
---@param skipUse? boolean @ 是否跳过使用。默认不跳过
---@return CardUseStruct|nil @ 返回卡牌使用框架
Utility.askForPlayCard = function(room, player, cards, pattern, skillName, prompt, extra_data, skipUse)
  cards = cards or player:getHandlyIds(true)
  pattern = pattern or "."
  skillName = skillName or "#askForPlayCard"
  prompt = prompt or ("##askForPlayCard:::"..skillName)
  local useables = {} -- 可用牌名
  if extra_data then
    if extra_data.bypass_distances then
      room:setPlayerMark(player, MarkEnum.BypassDistancesLimit .. "-tmp", 1) -- FIXME: 缺少直接传入无限制的手段
    end
    if extra_data.bypass_times == nil or extra_data.bypass_times then
      room:setPlayerMark(player, MarkEnum.BypassTimesLimit .. "-tmp", 1) -- FIXME: 缺少直接传入无限制的手段
    end
  end
  for _, id in ipairs(Fk:getAllCardIds()) do
    local card = Fk:getCardById(id)
    if not player:prohibitUse(card) and player:canUse(card) then
      table.insertIfNeed(useables, card.name)
    end
  end
  room:setPlayerMark(player, MarkEnum.BypassDistancesLimit .. "-tmp", 0) -- FIXME: 缺少直接传入无限制的手段
  room:setPlayerMark(player, MarkEnum.BypassTimesLimit .. "-tmp", 0) -- FIXME: 缺少直接传入无限制的手段
  local cardIds = player:getCardIds("e")
  for _, cid in ipairs(cards) do
    local card = Fk:getCardById(cid)
    if not (Exppattern:Parse(pattern):match(card) and player:canUse(card) and not player:prohibitUse(card)) then
      table.insert(cardIds, cid)
    end
  end
  local strid = table.concat(cardIds, ",")
  local useable_pattern = ".|.|.|.|" .. table.concat(useables, ",") .. "|.|" .. (strid == "" and "." or "^(" .. strid .. ")")
  extra_data = extra_data or {}
  local use = room:askForUseCard(player, skillName, useable_pattern, prompt, true, extra_data)
  if not use then return end
  if not skipUse then
    room:useCard(use)
  end
  return use
end
Fk:loadTranslationTable{
  ["#askForPlayCard"] = "使用牌",
  ["##askForPlayCard"] = "%arg：请使用一张牌",
}

--- 判断一名角色是否为男性
---@param player Player @ 玩家
---@param realGender? boolean @ 是否获取真实性别，无视双性人。默认否
---@return boolean
Utility.isMale = function(player, realGender)
  return player.gender == General.Male or (not realGender and player.gender == General.Bigender)
end


--- 判断一名角色是否为女性
---@param player Player @ 玩家
---@param realGender? boolean @ 是否获取真实性别，无视双性人。默认否
---@return boolean
Utility.isFemale = function(player, realGender)
  return player.gender == General.Female or (not realGender and player.gender == General.Bigender)
end


--- 获得队友（注意：在客户端不能对暗身份角色生效）（或许对ai有用？）
---@param room Room @ 房间
---@param player ServerPlayer @ 自己
---@param include_self? boolean @ 是否包括自己。默认是
---@param include_dead? boolean @ 是否包括死亡角色。默认否
---@return ServerPlayer[] @ 玩家列表
Utility.GetFriends = function(room, player, include_self, include_dead)
  include_self = include_self or true
  local players = include_dead and room.players or room.alive_players
  local friends = {player}
  if table.contains({"aaa_role_mode", "vanished_dragon", "zombie_mode"}, room.settings.gameMode) then
    if player.role == "lord" or player.role == "loyalist" then
      friends = table.filter(players, function(p) return p.role == "lord" or p.role == "loyalist" end)
    else
      friends = table.filter(players, function(p) return p.role == player.role end)
    end
  elseif table.contains({"m_1v2_mode", "brawl_mode", "m_2v2_mode"}, room.settings.gameMode) then
    friends = table.filter(players, function(p) return p.role == player.role end)
  elseif table.contains({"nos_heg_mode", "new_heg_mode"}, room.settings.gameMode) then
    if player.role == "wild" or player.kingdom == "unknown" then
      friends = {player}
    else
      friends = table.filter(players, function(p) return p.kingdom == player.kingdom end)
    end
  else  --有需要的自行添加
    friends = {player}
  end
  if not include_self then
    table.removeOne(friends, player)
  end
  return friends
end

--- 获得敌人（注意：在客户端不能对暗身份角色生效）（或许对ai有用？）
---@param room Room @ 房间
---@param player ServerPlayer @ 自己
---@param include_dead? boolean @ 是否包括死亡角色。默认否
---@return ServerPlayer[] @ 玩家列表
Utility.GetEnemies = function(room, player, include_dead)
  local players = include_dead and room.players or room.alive_players
  local enemies = {}
  if table.contains({"aaa_role_mode", "vanished_dragon", "zombie_mode"}, room.settings.gameMode) then
    if player.role == "lord" or player.role == "loyalist" then
      enemies = table.filter(players, function(p) return p.role ~= "lord" and p.role ~= "loyalist" end)
    else
      enemies = table.filter(players, function(p) return p.role ~= player.role end)
    end
  elseif table.contains({"m_1v2_mode", "brawl_mode", "m_2v2_mode"}, room.settings.gameMode) then
    enemies = table.filter(players, function(p) return p.role ~= player.role end)
  elseif table.contains({"m_1v1_mode"}, room.settings.gameMode) then
    enemies = {player:getNextAlive(true)}
  elseif table.contains({"nos_heg_mode", "new_heg_mode"}, room.settings.gameMode) then
    if player.role == "wild" then
      enemies = room:getOtherPlayers(player, nil, include_dead)
    elseif player.kingdom == "unknown" then
      enemies = {}
    else
      enemies = table.filter(players, function(p) return p.role == "wild" or p.kingdom ~= player.kingdom end)
    end
  else  --有需要的自行添加
    enemies = {}
  end
  return enemies
end




-- 卡牌标记 进入弃牌堆销毁 例OL蒲元
MarkEnum.DestructIntoDiscard = "__destr_discard"

-- 卡牌标记 离开自己的装备区销毁 例新服刘晔
MarkEnum.DestructOutMyEquip = "__destr_my_equip"

-- 卡牌标记 进入非装备区销毁(可在装备区/处理区移动) 例OL冯方女
MarkEnum.DestructOutEquip = "__destr_equip"

local CardDestructSkill = fk.CreateTriggerSkill{
  name = "#card_destruct_skill",
  global = true,
  mute = true,
  refresh_events = {fk.BeforeCardsMove},
  can_refresh = Util.TrueFunc,
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
          table.insert(mirror_moves, mirror_move)
        end
      end
    end
    if #ids > 0 then
      room:sendLog{ type = "#destructDerivedCards", card = ids, }
      table.insertTable(data, mirror_moves)
    end
  end,
}
Fk:addSkill(CardDestructSkill)
Fk:loadTranslationTable{
  ["#card_destruct_skill"] = "卡牌销毁",
  ["#destructDerivedCards"] = "%card 被销毁了",
}

--花色互转（支持int(Card.Heart)，string("heart")，icon("♥")，symbol(translate后的红色"♥")）
---@param value any @ 花色
---@param input_type string @ 输入类型("int|str|icon|sym")
---@param output_type string @ 输出类型("int|str|icon|sym")
Utility.ConvertSuit = function(value, input_type, output_type)
  local mapper = {
    ["int"] = {Card.Spade, Card.Heart, Card.Club, Card.Diamond, Card.NoSuit},
    ["str"] = {"spade", "heart", "club", "diamond", "nosuit"},
    ["icon"] = {"♠", "♥", "♣", "♦", ""},
    ["sym"] = {"log_spade", "log_heart", "log_club", "log_diamond", "log_nosuit"},
  }
  return mapper[output_type][table.indexOf(mapper[input_type], value)]
end

--从键值对表中随机取N个值（每种最多取一个）
---@param cardDic table @ 卡表
---@param num number @ 要取出的数量
---@return table
Utility.getRandomCards = function (cardDic, num)
  local cardMap = table.simpleClone(cardDic)
  local toObtain = {}
  while #toObtain < num and next(cardMap) ~= nil do
    local dicLength = 0
    for _, ids in pairs(cardMap) do
      dicLength = dicLength + #ids
    end

    local randomIdx = math.random(1, dicLength)
    dicLength = 0
    for key, ids in pairs(cardMap) do
      dicLength = dicLength + #ids
      if dicLength >= randomIdx then
        table.insert(toObtain, ids[dicLength - randomIdx + 1])
        cardMap[key] = nil
        break
      end
    end
  end
  return toObtain
end

-- 根据提供的卡表来印卡并保存到room.tag中，已有则直接读取
---@param room Room @ 房间
---@param cardDic table @ 卡表（卡名、花色、点数）
---@param name string @ 保存的tag名称
---@return table
Utility.prepareDeriveCards = function (room, cardDic, name)
  local cards = room:getTag(name)
  if type(cards) == "table" then
    return cards
  end
  cards = {}
  for _, value in ipairs(cardDic) do
    table.insert(cards, room:printCard(value[1], value[2], value[3]).id)
  end
  room:setTag(name, cards)
  return cards
end

-- 印一套基础牌堆中的卡（仅包含基本牌、锦囊牌，无花色点数）
---@param room Room @ 房间
---@return table
Utility.prepareUniversalCards = function (room)
  local cards = room:getTag("universal_cards")
  if type(cards) == "table" then
    return cards
  end
  local names = {}
  for _, id in ipairs(Fk:getAllCardIds()) do
    local card = Fk:getCardById(id)
    if (card.type == Card.TypeBasic or card.type == Card.TypeTrick) and not card.is_derived then
      table.insertIfNeed(names, card.trueName)
    end
  end
  return Utility.prepareDeriveCards(room, table.map(names, function (name)
    return {name, Card.NoSuit, 0}
  end), "universal_cards")
end



---增加标记数量的使用杀次数上限，可带后缀
MarkEnum.SlashResidue = "__slash_residue"
---使用杀无次数限制，可带后缀
MarkEnum.SlashBypassTimes = "__slash_by_times"
---使用杀无距离限制，可带后缀
MarkEnum.SlashBypassDistances = "__slash_by_dist"

local global_slash_targetmod = fk.CreateTargetModSkill{
  name = "global_slash_targetmod",
  global = true,
  residue_func = function(self, player, skill, scope)
    if skill.trueName == "slash_skill" and scope == Player.HistoryPhase then
      local num = 0
      for _, s in ipairs(MarkEnum.TempMarkSuffix) do
        num = num + player:getMark(MarkEnum.SlashResidue..s)
      end
      return num
    end
  end,
  bypass_times = function(self, player, skill, scope)
    if skill.trueName == "slash_skill" and scope == Player.HistoryPhase then
      return table.find(MarkEnum.TempMarkSuffix, function(s)
        return player:getMark(MarkEnum.SlashBypassTimes .. s) ~= 0
      end)
    end
  end,
  bypass_distances = function (self, player, skill)
    if skill.trueName == "slash_skill" then
      return table.find(MarkEnum.TempMarkSuffix, function(s)
        return player:getMark(MarkEnum.SlashBypassDistances .. s) ~= 0
      end)
    end
  end
}
Fk:addSkill(global_slash_targetmod)

--- 获取实际的伤害事件
Utility.getActualDamageEvents = function(room, n, func, scope, end_id)
  if not end_id then
    scope = scope or Player.HistoryTurn
  end

  n = n or 1
  func = func or Util.TrueFunc

  local logic = room.logic
  local eventType = GameEvent.Damage
  local ret = {}
  local endIdRecorded
  local tempEvents = {}

  local addTempEvents = function(reverse)
    if #tempEvents > 0 and #ret < n then
      table.sort(tempEvents, function(a, b)
        if reverse then
          return a.data[1].dealtRecorderId > b.data[1].dealtRecorderId
        else
          return a.data[1].dealtRecorderId < b.data[1].dealtRecorderId
        end
      end)

      for _, e in ipairs(tempEvents) do
        table.insert(ret, e)
        if #ret >= n then return true end
      end
    end

    endIdRecorded = nil
    tempEvents = {}

    return false
  end

  if scope then
    local event = logic:getCurrentEvent()
    local start_event ---@type GameEvent
    if scope == Player.HistoryGame then
      start_event = logic.all_game_events[1]
    elseif scope == Player.HistoryRound then
      start_event = event:findParent(GameEvent.Round, true)
    elseif scope == Player.HistoryTurn then
      start_event = event:findParent(GameEvent.Turn, true)
    elseif scope == Player.HistoryPhase then
      start_event = event:findParent(GameEvent.Phase, true)
    end

    local events = logic.event_recorder[eventType] or Util.DummyTable
    local from = start_event.id
    local to = start_event.end_id
    if math.abs(to) == 1 then to = #logic.all_game_events end

    for _, v in ipairs(events) do
      local damageStruct = v.data[1]
      if damageStruct.dealtRecorderId then
        if endIdRecorded and v.id > endIdRecorded then
          local result = addTempEvents()
          if result then
            return ret
          end
        end

        if v.id >= from and v.id <= to then
          if not endIdRecorded and v.end_id > -1 and v.end_id > v.id then
            endIdRecorded = v.end_id
          end

          if func(v) then
            if endIdRecorded then
              table.insert(tempEvents, v)
            else
              table.insert(ret, v)
            end
          end
        end
        if #ret >= n then break end
      end
    end

    addTempEvents()
  else
    local events = logic.event_recorder[eventType] or Util.DummyTable

    for i = #events, 1, -1 do
      local e = events[i]
      if e.id <= end_id then break end

      local damageStruct = e.data[1]
      if damageStruct.dealtRecorderId then
        if e.end_id == -1 or (endIdRecorded and endIdRecorded > e.end_id) then
          local result = addTempEvents(true)
          if result then
            return ret
          end

          if func(e) then
            table.insert(ret, e)
          end    
        else
          endIdRecorded = e.end_id
          if func(e) then
            table.insert(tempEvents, e)
          end
        end

        if #ret >= n then break end
      end
    end

    addTempEvents(true)
  end

  return ret
end

Utility.presentCard = function(player, target, card)
  local room = player.room
  if card.type ~= Card.TypeEquip then
    room:moveCardTo(card, Card.PlayerHand, target, fk.ReasonGive, "present", nil, true, player.id)
  else
    if target:hasEmptyEquipSlot(card.sub_type) then
      room:moveCardTo(card, Card.PlayerEquip, target, fk.ReasonGive, "present", nil, true, player.id)
    elseif #target:getEquipments(card.sub_type) > 0 then
      room:moveCards({
        ids = target:getEquipments(card.sub_type),
        from = target.id,
        toArea = Card.DiscardPile,
        moveReason = fk.ReasonJustMove,
        skillName = "present",
        proposer = player.id,
      },
      {
        ids = {card.id},
        from = player.id,
        to = target.id,
        toArea = Card.PlayerEquip,
        moveReason = fk.ReasonJustMove,
        skillName = "present",
        proposer = player.id,
      })
    elseif #target:getAvailableEquipSlots(card.sub_type) == 0 then
      room:moveCardTo(card, Card.DiscardPile, target, fk.ReasonJustMove, "present", nil, true, player.id)
    end
  end
end

-- FIXME: Youmukon稳定发挥，等本体修改
local exChooseSkill = fk.CreateActiveSkill{
  name = "u_ex_choose_skill",
  card_filter = function(self, to_select, selected)
    if #selected >= self.max_card_num then return false end

    if Fk:currentRoom():getCardArea(to_select) == Card.PlayerSpecial then
      if not string.find(self.pattern or "", self.expand_pile or "") then return false end
    end

    local checkpoint = true
    local card = Fk:getCardById(to_select)

    if not self.include_equip then
      checkpoint = checkpoint and (Fk:currentRoom():getCardArea(to_select) ~= Player.Equip)
    end

    if self.pattern and self.pattern ~= "" then
      checkpoint = checkpoint and (Exppattern:Parse(self.pattern):match(card))
    end
    return checkpoint
  end,
  target_filter = function(self, to_select, selected, cards)
    if self.pattern ~= "" and #cards < self.min_card_num then return end
    if #selected < self.max_target_num then
      return table.contains(self.targets, to_select)
    end
  end,
  min_target_num = function(self) return self.min_target_num end,
  max_target_num = function(self) return self.max_target_num end,
  min_card_num = function(self) return self.min_card_num end,
  max_card_num = function(self) return self.max_card_num end,
}
Fk:addSkill(exChooseSkill)

--- 询问玩家选择X张牌和Y名角色。
---
--- 返回两个值，第一个是选择的目标列表，第二个是选择的那张牌的id
---@param self Room
---@param player ServerPlayer @ 要询问的玩家
---@param minCardNum integer @ 选卡牌最小值
---@param maxCardNum integer @ 选卡牌最大值
---@param targets integer[] @ 选择目标的id范围
---@param minTargetNum integer @ 选目标最小值
---@param maxTargetNum integer @ 选目标最大值
---@param pattern? string @ 选牌规则
---@param prompt? string @ 提示信息
---@param cancelable? boolean @ 能否点取消
---@param no_indicate? boolean @ 是否不显示指示线
---@return integer[], integer[]
function Utility.askForChooseCardsAndPlayers(self, player, minCardNum, maxCardNum, targets, minTargetNum, maxTargetNum, pattern, prompt, skillName, cancelable, no_indicate)
  if minCardNum < 1 or minTargetNum < 1 then
    return {}, {}
  end
  cancelable = (cancelable == nil) and true or cancelable
  no_indicate = no_indicate or false
  pattern = pattern or "."

  local pcards = table.filter(player:getCardIds({ Player.Hand, Player.Equip }), function(id)
    local c = Fk:getCardById(id)
    return c:matchPattern(pattern)
  end)
  if #pcards < minCardNum and not cancelable then return {}, {} end

  local data = {
    targets = targets,
    max_target_num = maxTargetNum,
    min_target_num = minTargetNum,
    max_card_num = maxCardNum,
    min_card_num = minCardNum,
    pattern = pattern,
    skillName = skillName,
  }
  local _, ret = self:askForUseActiveSkill(player, "u_ex_choose_skill", prompt or "", cancelable, data, no_indicate)
  if ret then
    return ret.targets, ret.cards
  else
    if cancelable then
      return {}, {}
    else
      return table.random(targets, minTargetNum), table.random(pcards, minCardNum)
    end
  end
end


dofile 'packages/utility/mobile_util.lua'

return Utility
