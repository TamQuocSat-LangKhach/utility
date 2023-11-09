-- 这个文件用来堆一些常用的函数，视情况可以分成多个文件
-- 因为不是拓展包，所以不能用init.lua（否则会被当拓展包加载并报错）
-- 因为本体里面已经有util了所以命名为完整版utility

-- 要使用的话在拓展开头加一句local U = require "packages/utility/utility" 即可(注意别加.lua)

local Utility = {}

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

-- 一名角色A对角色B使用牌的合法性检测
---@param room Room
---@param from ServerPlayer @ 使用来源
---@param to ServerPlayer @ 目标角色
---@param card Card @ 被使用的卡牌
---@param distance_limited boolean|nil @ 是否有距离关系的限制
---@param times_limited boolean|nil @ 是否有次数限制
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
---@param bypass_distances boolean|nil @ 是否无距离关系的限制
---@return integer[] @ 返回满足条件的player的id列表
Utility.getUseExtraTargets = function(room, data, bypass_distances)
  if not (data.card.type == Card.TypeBasic or data.card:isCommonTrick()) then return {} end
  if data.card.skill:getMinTargetNum() > 1 then return {} end --stupid collateral
  local tos = {}
  local current_targets = TargetGroup:getRealTargets(data.tos)
  for _, p in ipairs(room.alive_players) do
    if not table.contains(current_targets, p.id) and not room:getPlayerById(data.from):isProhibited(p, data.card) then
      if data.card.skill:modTargetFilter(p.id, {}, data.from, data.card, not bypass_distances) then
        table.insert(tos, p.id)
      end
    end
  end
  return tos
end

-- 判断一名角色为一个使用事件的唯一目标（目标角色数为1，不包括死亡角色且不计算重复目标）
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
---@param player ServerPlayer @ 要被获取标记的那个玩家
---@param mark string @ 标记
---@return table
Utility.getMark = function(player, mark)
  return type(player:getMark(mark)) == "table" and player:getMark(mark) or {}
end


--- 判断一张牌能否移动至某角色的装备区
---@param target ServerPlayer @ 接受牌的角色
---@param cardId integer @ 移动的牌
---@param convert boolean|nil @ 是否可以替换装备（默认可以）
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


--- 将一张牌移动至某角色的装备区，若不合法则置入弃牌堆
---@param room Room @ 房间
---@param target ServerPlayer @ 接受牌的角色
---@param cardId integer @ 移动的牌
---@param skillName string|nil @ 技能名
---@param convert boolean|nil @ 是否可以替换装备（默认可以）
---@param proposer ServerPlayer|nil @ 操作者
Utility.moveCardIntoEquip = function (room, target, cardId, skillName, convert, proposer)
  convert = (convert == nil) and true or convert
  skillName = skillName or ""
  local card = Fk:getCardById(cardId)
  local fromId = room:getCardOwner(cardId) and room:getCardOwner(cardId).id or nil
  local proposerId = proposer and proposer.id or nil
  if Utility.canMoveCardIntoEquip(target, cardId, convert) then
    if target:hasEmptyEquipSlot(card.sub_type) then
      room:moveCards({ids = {cardId}, from = fromId, to = target.id, toArea = Card.PlayerEquip, moveReason = fk.ReasonPut,skillName = skillName,proposer = proposerId})
    else
      local existingEquip = target:getEquipments(card.sub_type)
      local throw = #existingEquip == 1 and existingEquip[1] or
      room:askForCardChosen(proposer or target, target, {card_data = { {"convertEquip",existingEquip} } }, "convertEquip")
      room:moveCards({ids = {throw}, from = target.id, toArea = Card.DiscardPile, moveReason = fk.ReasonPutIntoDiscardPile, skillName = skillName,proposer = proposerId},
      {ids = {cardId}, from = fromId, to = target.id, toArea = Card.PlayerEquip, moveReason = fk.ReasonPut,skillName = skillName,proposer = proposerId})
    end
  else
    room:moveCards({ids = {cardId}, from = fromId, toArea = Card.DiscardPile, moveReason = fk.ReasonPutIntoDiscardPile,skillName = skillName})
  end
end
Fk:loadTranslationTable{
  ["convertEquip"] = "替换装备",
}

--- 询问玩家交换两堆卡牌中的任意张。
---@param player ServerPlayer @ 要询问的玩家
---@param name1 string @ 第一行卡牌名称
---@param name2 string @ 第一行卡牌名称
---@param cards1 integer[] @ 第一行的卡牌
---@param cards2 integer[] @ 第二行的卡牌
---@param prompt string @ 操作提示（FXIME:暂时无效）
---@param n integer|null @ 至多可交换的卡牌数量（不填或负数则无限制）
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

return Utility
