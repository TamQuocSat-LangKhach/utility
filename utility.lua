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
---@param target Player @ 接受牌的角色
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

--- 询问玩家选择牌和选项
---@param player ServerPlayer @ 要询问的玩家
---@param cards integer[] @ 待选卡牌
---@param choices string[] @ 可选选项列表（在min和max范围内选择cards里的牌才会被点亮的选项）
---@param skillname string @ 烧条技能名
---@param prompt string @ 操作提示
---@param cancel_choices string[]|nil @ 可选选项列表（不选择牌时的选项）
---@param min integer|nil  @ 最小选牌数（默认为1）
---@param max integer|nil  @ 最大选牌数（默认为1）
---@param all_cards integer[]|nil  @ 会显示的所有卡牌
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
---@param prompt string|nil @ 操作提示
---@return string
Utility.askforViewCardsAndChoice = function(player, cards, choices, skillname, prompt)
  local _, result = Utility.askforChooseCardsAndChoice(player, cards, {}, skillname, prompt or "#AskForChoice", choices)
  return result
end

--- 让玩家观看一些卡牌（用来取代fillAG式观看）。
---@param player ServerPlayer @ 要询问的玩家
---@param cards integer[] @ 待选卡牌
---@param skillname string|nil @ 烧条技能名
---@param prompt string|nil @ 操作提示
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
---@param proposer integer|nil @ 操作者的id
---@param skillName string|nil @ 技能名
Utility.doDistribution = function (room, list, proposer, skillName)
  skillName = skillName or "distribution_skill"
  local moveInfos = {}
  for str, cards in pairs(list) do
    local to = tonumber(str)
    local toP = room:getPlayerById(to)
    local handcards = toP:getCardIds("h")
    cards = table.filter(cards, function (id) return not table.contains(handcards, id) end)
    if #cards > 0 then
      local from = room:getCardOwner(cards[1])
      table.insert(moveInfos, {
      ids = cards,
      from = from and from.id,
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


--- 询问将卡牌分配给任意角色。请确保这些牌的所有者一致
---@param player ServerPlayer @ 要询问的玩家
---@param cards integer[] @ 要分配的卡牌
---@param targets ServerPlayer[] @ 可以获得卡牌的角色
---@param skillName string|nil @ 技能名，影响焦点信息。默认为“分配”
---@param minNum integer|nil @ 最少交出的卡牌数，默认0
---@param maxNum integer|nil @ 最多交出的卡牌数，默认所有牌
---@param prompt string|nil @ 询问提示信息
---@param expand_pile string|nil @ 可选私人牌堆名称，如要分配你武将牌上的牌请填写
---@param skipMove boolean|nil @ 是否跳过移动。默认不跳过
---@return table<integer[]> @ 返回一个表，键为字符串化的角色id，值为分配给其的牌
Utility.askForDistribution = function(player, cards, targets, skillName, minNum, maxNum, prompt, expand_pile, skipMove)
  local room = player.room
  local _cards = table.simpleClone(cards)
  targets = table.map(targets, Util.IdMapper)
  skillName = skillName or "distribution_skill"
  prompt = prompt or "#askForDistribution"
  minNum = minNum or 0
  maxNum = maxNum or #cards
  local getString = function(n) return string.format("%.0f", n) end
  local list = {}
  for _, p in ipairs(targets) do
    list[getString(p)] = {}
  end
  local data = { expand_pile = expand_pile }
  room:setPlayerMark(player, "distribution_targets", targets)
  
  while maxNum > 0 do
    room:setPlayerMark(player, "distribution_cards", _cards)
    room:setPlayerMark(player, "distribution_maxnum", maxNum)
    local success, dat = room:askForUseActiveSkill(player, "distribution_skill", "#distribution_skill:::"..minNum..":"..maxNum, minNum == 0, data, false)
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
    else
      break
    end
  end

  for _, id in ipairs(cards) do
    room:setCardMark(Fk:getCardById(id), "@distribution_to", 0)
  end
  if minNum > 0 then
    local p = table.random(targets)
    local c = table.random(_cards, minNum)
    table.insertTable(list[getString(p)], c)
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
---@param selected_subcards integer[]|nil @ 虚拟牌的子牌，默认空
---@param skillName string|nil @ 技能名
---@param prompt string|nil @ 询问提示信息。默认为：请视为使用xx
---@param cancelable boolean|nil @ 是否可以取消，默认可以。请勿给多目标锦囊,借刀,无中设置不可取消
---@param bypass_distances boolean|nil @ 是否无距离限制。默认有
---@param extraUse boolean|nil @ 是否不计入次数。默认不计入
---@param extra_data table|nil @ 额外信息，因技能而异了
---@param skipUse boolean|nil @ 是否跳过使用。默认不跳过
---@return CardUseStruct|nil @ 返回卡牌使用框架
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
  if bypass_distances then room:setPlayerMark(player, MarkEnum.BypassDistancesLimit .. "-tmp", 1) end
  local success, dat = room:askForUseViewAsSkill(player, "virtual_viewas", prompt, cancelable, extra_data)
  if bypass_distances then room:setPlayerMark(player, MarkEnum.BypassDistancesLimit .. "-tmp", 0) end
  local tos = {}
  if success and dat then
    tos = dat.targets
  elseif not cancelable then
    tos = table.random(targets, 1)
  end
  if #tos > 0 then
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
  return nil
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

return Utility
