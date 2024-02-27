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

--因执行牌的效果而对一名角色造成伤害，即通常描述的使用牌对目标角色造成伤害
---@param room Room
---@param by_user? bool @ 进一步判定使用者和来源是否一致（默认为true）
---@return bool
Utility.damageByCardEffect = function(room, by_user)
  by_user = by_user or true
  local d_event = room.logic:getCurrentEvent():findParent(GameEvent.Damage, true)
  if d_event == nil then return false end
  local damage = d_event.data[1]
  if damage.chain or damage.card == nil then return false end
  local c_event = d_event:findParent(GameEvent.CardEffect, false)
  if c_event == nil then return false end
  return damage.card == c_event.data[1].card and
  (not by_user or d_event.data[1].from.id == c_event.data[1].from)
end



-- 使用牌的合法性检测
---@param room Room
---@param player ServerPlayer @ 使用来源
---@param card Card @ 被使用的卡牌
---@param times_limited? boolean @ 是否有次数限制
---@return bool
Utility.canUseCard = function(room, player, card, times_limited)
  if player:prohibitUse(card) then return false end
  local can_use = card.skill:canUse(player, card, { bypass_times = not times_limited })
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
  local can_use = card.skill:canUse(from, card, { bypass_times = not times_limited, bypass_distances = not distance_limited })
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

-- 判断是否能将当前结算的目标转移给一名角色（其实也有一些扩展用途，但必须在指定/成为目标时才能使用）
-- 
-- 注意：若此牌需指定副目标（如【借刀杀人】），则沿用当前目标的副目标，在后续添加目标时要将这些副目标也加上
-- 
---@param target ServerPlayer @ 即将被转移目标的角色
---@param data AimStruct @ 使用事件的data
---@param distance_limited? boolean @ 是否受距离限制
---@return boolean
Utility.canTransferTarget = function(target, data, distance_limited)
  local room = target.room
  local Notify_from = room:getPlayerById(data.from)
  if Notify_from:isProhibited(target, data.card) or not data.card.skill:modTargetFilter(
    target.id, {}, data.from, data.card, distance_limited
  ) then return false end

  --target_filter check, for collateral,diversion...
  --FIXME：借刀需要补modTargetFilter，不给targetFilter传使用者真是离大谱，目前只能通过强制修改Self来实现
  local ho_spair_target = data.subTargets
  if type(ho_spair_target) == "table" then
    local passed_target = {target.id}
    Self = Notify_from
    for c_pid in ipairs(ho_spair_target) do
      if not data.card.skill:targetFilter(c_pid, passed_target, {}, data.card) then return false end
      table.insert(passed_target, c_pid)
    end
  end
  return true
end


-- 获得一名角色使用一张牌的默认目标。用于强制使用此牌时的默认值。
---@param player ServerPlayer @ 使用者
---@param card Card @ 使用的牌
---@param bypass_times? boolean @ 是否无次数限制。默认受限制
---@param bypass_distances? boolean @ 是否无距离限制。默认受限制
---@return table<integer>? @ 返回表，元素为目标角色的id。返回空则为没有合法目标
Utility.getDefaultTargets = function(player, card, bypass_times, bypass_distances)
  local room = player.room
  local canUse = card.skill:canUse(player, card, { bypass_times = bypass_times or false, bypass_distances = bypass_distances or false }) and not player:prohibitUse(card)
  if not canUse then return end
  local tos = {}
  for _, p in ipairs(room.alive_players) do
    if not player:isProhibited(p, card) then
      if card.skill:modTargetFilter(p.id, {}, player.id, card, not bypass_distances) then
        table.insert(tos, p.id)
      end
    end
  end
  if #tos == 0 then return end
  local min_target_num = card.skill:getMinTargetNum()
  if min_target_num == 0 then return {} end -- for AOE trick, ex_nihilo, peach...
  local real_tos
  if min_target_num == 2 then  -- for collateral, diversion...
    Self = player -- for targetFilter check
    for _, first_id in ipairs(tos) do
      local seconds = {}
      local first = room:getPlayerById(first_id)
      for _, second in ipairs(room:getOtherPlayers(first)) do
        if card.skill:targetFilter(second.id, {first_id}, {}, card) then
          table.insert(seconds, second.id)
        end
      end
      if #seconds > 0 then
        real_tos = {first_id, table.random(seconds)}
        break
      end
    end
  else
    real_tos = table.random(tos, min_target_num)
  end
  return real_tos
end












-- 获取目标对应的角色（不包括死亡角色且不计算重复目标）
---@param room Room
---@param data CardUseStruct @ 使用事件的data
---@param event Event @ 使用事件的时机（需判断使用TargetGroup还是AimGroup，by smart Ho-spair）
---@return integer[] @ 返回目标角色player的id列表
Utility.getActualUseTargets = function(room, data, event)
  if data.tos == nil then return {} end
  local targets = {}
  local tos = {}
  if table.contains({ fk.TargetSpecifying, fk.TargetConfirming, fk.TargetSpecified, fk.TargetConfirmed }, event) then
    tos = AimGroup:getAllTargets(data.tos)
  else
    tos = TargetGroup:getRealTargets(data.tos)
  end
  for _, p in ipairs(room.alive_players) do
    if table.contains(tos, p.id) then
      table.insertIfNeed(targets, p.id)
    end
  end
  return targets
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
---@param room Room
---@param card Card @ 待判别的卡牌
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

-- 获取角色对应私人Mark的实际值并初始化为table
---@param player Player @ 要被获取标记的那个玩家
---@param name string @ 标记名称（不带前缀）
---@return table
Utility.getPrivateMark = function(player, name)
  return type(player:getMark("@[private]" .. name)) == "table" and player:getMark("@[private]" .. name).value or {}
end

-- 设置角色对应私人Mark
---@param player ServerPlayer @ 要被获取标记的那个玩家
---@param name string @ 标记名称（不带前缀）
---@param value table @ 标记实际值
---@param players? integer[] @ 公开标记的角色，若为nil则为仅对自己可见
Utility.setPrivateMark = function(player, name, value, players)
  local mark = player:getMark("@[private]" .. name)
  if type(mark) ~= "table" then mark = {} end
  if mark.players == nil then
    mark.players = players
  end
  mark.value = value
  player.room:setPlayerMark(player, "@[private]" .. name, mark)
end

--让一名角色的仅对自己可见的mark对所有角色都可见
---@param player ServerPlayer @ 要公开标记的角色
---@param name? string @ 要公开的标记名（不含前缀）
Utility.showPrivateMark = function(player, name)
  local room = player.room
  local mark = player:getMark("@[private]" .. name)
  if type(mark) == "table" then
    mark.players = table.map(room.players, Util.IdMapper)
    room:setPlayerMark(player, "@[private]" .. name, mark)
  end
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


--- 将一些卡牌同时分配给一些角色。
---@param room Room @ 房间
---@param list table<integer[]> @ 分配牌和角色的数据表，键为取整后字符串化的角色id，值为分配给其的牌
---@param proposer? integer @ 操作者的id。默认为空
---@param skillName? string @ 技能名。默认为“分配”
---@return table<integer[]> @ 返回成功分配的卡牌
Utility.doDistribution = function (room, list, proposer, skillName)
  skillName = skillName or "distribution_skill"
  local moveInfos = {}
  local move_ids = {}
  for str, cards in pairs(list) do
    local to = tonumber(str)
    local toP = room:getPlayerById(to)
    local handcards = toP:getCardIds("h")
    cards = table.filter(cards, function (id) return not table.contains(handcards, id) end)
    if #cards > 0 then
      table.insertTable(move_ids, cards)
      local moveMap = {}
      local noFrom = {}
      for _, id in ipairs(cards) do
        local from = room.owner_map[id]
        if from then
          moveMap[from] = moveMap[from] or {}
          table.insert(moveMap[from], id)
        else
          table.insert(noFrom, id)
        end
      end
      for from, _cards in pairs(moveMap) do
        table.insert(moveInfos, {
          ids = _cards,
          moveInfo = table.map(_cards, function(id)
            return {cardId = id, fromArea = room:getCardArea(id), fromSpecialName = room:getPlayerById(from):getPileNameOfId(id)}
          end),
          from = from,
          to = to,
          toArea = Card.PlayerHand,
          moveReason = fk.ReasonGive,
          proposer = proposer,
          skillName = skillName,
        })
      end
      if #noFrom > 0 then
        table.insert(moveInfos, {
          ids = noFrom,
          to = to,
          toArea = Card.PlayerHand,
          moveReason = fk.ReasonGive,
          proposer = proposer,
          skillName = skillName,
        })
      end
    end
  end
  if #moveInfos > 0 then
    room:moveCards(table.unpack(moveInfos))
  end
  return move_ids
end


--- 询问将卡牌分配给任意角色。
---@param player ServerPlayer @ 要询问的玩家
---@param cards? integer[] @ 要分配的卡牌。默认拥有的所有牌
---@param targets? ServerPlayer[] @ 可以获得卡牌的角色。默认所有存活角色
---@param skillName? string @ 技能名，影响焦点信息。默认为“分配”
---@param minNum? integer @ 最少交出的卡牌数，默认0
---@param maxNum? integer @ 最多交出的卡牌数，默认所有牌
---@param prompt? string @ 询问提示信息
---@param expand_pile? string|integer[] @ 可选私人牌堆名称，如要分配你武将牌上的牌请填写
---@param skipMove? boolean @ 是否跳过移动。默认不跳过
---@param single_max? integer|table @ 限制每人能获得的最大牌数。输入整数或(以角色id为键以整数为值)的表
---@return table<integer[]> @ 返回一个表，键为取整后字符串化的角色id，值为分配给其的牌
Utility.askForDistribution = function(player, cards, targets, skillName, minNum, maxNum, prompt, expand_pile, skipMove, single_max)
  local room = player.room
  targets = targets or room.alive_players
  cards = cards or player:getCardIds("he")
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
  local data = { expand_pile = expand_pile , skillName = skillName }
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



--- 询问玩家使用一张虚拟卡，或从几种牌名中选择一种视为使用
---@param room Room @ 房间
---@param player ServerPlayer @ 要询问的玩家
---@param name string|string[] @ 使用虚拟卡名
---@param subcards? integer[] @ 虚拟牌的子牌，默认空
---@param skillName? string @ 技能名
---@param prompt? string @ 询问提示信息。默认为：请视为使用xx
---@param cancelable? boolean @ 是否可以取消，默认可以。
---@param bypass_times? boolean @ 是否无次数限制。默认无次数限制
---@param bypass_distances? boolean @ 是否无距离限制。默认有距离限制
---@param extraUse? boolean @ 是否不计入次数。默认不计入次数
---@param extra_data? UseExtraData|table @ 额外信息，因技能而异了
---@param skipUse? boolean @ 是否跳过使用。默认不跳过
---@return CardUseStruct? @ 返回卡牌使用框架。若取消使用则返回空
Utility.askForUseVirtualCard = function(room, player, name, subcards, skillName, prompt, cancelable, bypass_times, bypass_distances, extraUse, extra_data, skipUse)
  if player.dead then return end
  subcards = subcards or {}
  extraUse = (extraUse == nil) and true or extraUse
  skillName = skillName or "virtual_viewas"
  local all_names = type(name) == "table" and name or {name}
  if (cancelable == nil) then cancelable = true end
  if (bypass_times == nil) then bypass_times = true end
  extra_data = extra_data or {}
  extra_data.selected_subcards = subcards
  extra_data.skillName = skillName
  extra_data.virtualuse_allnames = all_names
  extra_data.bypass_times = bypass_times
  extra_data.bypass_distances = bypass_distances
  local names = table.filter(all_names, function (n)
    local card = Fk:cloneCard(n)
    card:addSubcards(subcards)
    card.skillName = skillName
    return card.skill:canUse(player, card, extra_data) and not player:prohibitUse(card)
    and table.find(room.alive_players, function (p)
      return not player:isProhibited(p, card) and card.skill:modTargetFilter(p.id, {}, player.id, card, not bypass_distances)
    end)
  end)
  extra_data.virtualuse_names = names
  local dat
  if #names > 0 then
    if not prompt then
      if #all_names == 1 then
        prompt = ("#askForUseVirtualCard:::"..skillName..":"..all_names[1])
      else
        prompt = ("#askForUseVirtualCards:::"..skillName..":"..#names)
      end
    end
    _, dat = room:askForUseViewAsSkill(player, "virtual_viewas", prompt, cancelable, extra_data)
  end
  if #names == 0 then return end
  local card, tos
  if dat then
    tos = dat.targets
    card = Fk:cloneCard(dat.interaction or all_names[1])
    card:addSubcards(subcards)
    card.skillName = skillName
  else
    if cancelable then return end
    for _, n in ipairs(names) do
      card = Fk:cloneCard(n)
      card:addSubcards(subcards)
      card.skillName = skillName
      local temp = Utility.getDefaultTargets(player, card, bypass_times, bypass_distances)
      if temp then
        tos = temp
        break
      end
    end
  end
  if not tos then return end
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
  interaction = function(self)
    if #self.virtualuse_allnames == 1 then return end
    return UI.ComboBox {choices = self.virtualuse_names, all_choices = self.virtualuse_allnames }
  end,
  view_as = function(self)
    local name = (#self.virtualuse_allnames == 1) and self.virtualuse_allnames[1] or self.interaction.data
    if not name then return nil end
    local card = Fk:cloneCard(name)
    if self.skillName then card.skillName = self.skillName end
    card:addSubcards(self.selected_subcards)
    return card
  end,
}
Fk:addSkill(virtual_viewas)
Fk:loadTranslationTable{
  ["virtual_viewas"] = "视为使用",
  ["#askForUseVirtualCard"] = "%arg：请视为使用 %arg2",
  ["#askForUseVirtualCards"] = "%arg：请视为使用一张牌（可选 %arg2 种）",
}



--- 判断当前使用/打出事件是否是在使用手牌
---@param player ServerPlayer @ 要判断的使用者
---@param data CardUseStruct @ 当前事件的data
---@return boolean
Utility.IsUsingHandcard = function(player, data)
  local cards = data.card:isVirtual() and data.card.subcards or {data.card.id}
  if #cards == 0 then return false end
  local yes = true
  local use = player.room.logic:getCurrentEvent()
  use:searchEvents(GameEvent.MoveCards, 1, function(e)
    if e.parent and e.parent.id == use.id then
      local subcheck = table.simpleClone(cards)
      for _, move in ipairs(e.data) do
        if (move.moveReason == fk.ReasonUse or move.moveReason == fk.ReasonResonpse) then
          for _, info in ipairs(move.moveInfo) do
            if table.removeOne(subcheck, info.cardId) and info.fromArea ~= Card.PlayerHand then
              yes = false
              return true
            end
          end
        end
      end
      if #subcheck == 0 then
        return true
      end
    end
  end)
  return yes
end


--- 询问玩家使用一张手牌中的实体卡。此函数默认无次数限制
---@param room Room @ 房间
---@param player ServerPlayer @ 要询问的玩家
---@param cards? integer[] @ 可以使用的卡牌，默认为所有手牌
---@param pattern? string @ 选卡规则，与可选卡牌取交集
---@param skillName? string @ 技能名
---@param prompt? string @ 询问提示信息。默认为：请使用一张牌
---@param extra_data? UseExtraData|table @ 额外信息，因技能而异了
---@param skipUse? boolean @ 是否跳过使用。默认不跳过
---@param cancelable? boolean @ 是否可以取消。默认可以取消
---@return CardUseStruct? @ 返回卡牌使用框架。取消使用则返回空
Utility.askForUseRealCard = function(room, player, cards, pattern, skillName, prompt, extra_data, skipUse, cancelable)
  cards = cards or player:getCardIds("h")
  pattern = pattern or "."
  skillName = skillName or "realcard_viewas"
  prompt = prompt or ("#askForUseRealCard:::"..skillName)
  if (cancelable == nil) then cancelable = true end
  local cardIds = {}
  extra_data = extra_data or {}
  extra_data.bypass_distances = extra_data.bypass_distances or false
  if extra_data.bypass_times == nil then extra_data.bypass_times = true end
  if extra_data.extraUse == nil then extra_data.extraUse = true end
  extra_data.expand_pile = extra_data.expand_pile or ""
  for _, cid in ipairs(cards) do
    local card = Fk:getCardById(cid)
    if Exppattern:Parse(pattern):match(card) then
      if card.skill:canUse(player, card, extra_data) and not player:prohibitUse(card) then
        table.insert(cardIds, cid)
      end
    end
  end
  extra_data.optional_cards = cardIds
  extra_data.skillName = skillName
  local dat
  if #cardIds > 0 then
    _, dat = room:askForUseViewAsSkill(player, "realcard_viewas", prompt, cancelable, extra_data)
  end
  if (not cancelable) and (not dat) then
    for _, cid in ipairs(cardIds) do
      local card = Fk:getCardById(cid)
      local temp = Utility.getDefaultTargets(player, card, true, false)
      if temp then
        dat = {targets = temp, cards = {cid}}
        break
      end
    end
  end
  if not dat then return end
  local use = {
    from = player.id,
    tos = table.map(dat.targets, function(p) return {p} end),
    card = Fk:getCardById(dat.cards[1]),
    extraUse = extra_data.extraUse,
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
  for _, id in ipairs(Fk:getAllCardIds()) do
    local card = Fk:getCardById(id)
    if not player:prohibitUse(card) and card.skill:canUse(player, card, extra_data) then
      table.insertIfNeed(useables, card.name)
    end
  end
  local cardIds = player:getCardIds("e")
  for _, cid in ipairs(cards) do
    local card = Fk:getCardById(cid)
    if not (Exppattern:Parse(pattern):match(card) and card.skill:canUse(player, card, extra_data) and not player:prohibitUse(card)) then
      table.insert(cardIds, cid)
    end
  end
  local strid = table.concat(cardIds, ",")
  local useable_pattern = table.concat(useables, ",") .. "|.|.|.|.|.|" .. (strid == "" and "." or "^(" .. strid .. ")")
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
  if include_self == nil then
    include_self = true
  end
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
  can_refresh = function (self, event, target, player, data)
    return player == player.room.players[1]
  end,
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

    if not start_event then return {} end

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
---@return integer[]
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
---@return integer[]
Utility.prepareUniversalCards = function (room)
  local cards = room:getTag("universal_cards")
  if type(cards) == "table" then
    return cards
  end
  local names = {}
  for _, id in ipairs(Fk:getAllCardIds()) do
    local card = Fk:getCardById(id)
    if (card.type == Card.TypeBasic or card.type == Card.TypeTrick) and not card.is_derived then
      table.insertIfNeed(names, card.name)
    end
  end
  return Utility.prepareDeriveCards(room, table.map(names, function (name)
    return {name, Card.NoSuit, 0}
  end), "universal_cards")
end

-- 获取基础卡牌的复印卡
---@param guhuo_type string @ 神杀智慧，用"btd"三个字母的组合表示卡牌的类别， b 基本牌, t - 普通锦囊牌, d - 延时锦囊牌
---@param true_name? boolean @ 是否使用真实卡名（即不区分【杀】、【无懈可击】等的具体种类）
---@return integer[]
Utility.getUniversalCards = function(room, guhuo_type, true_name)
  local all_names, cards = {}, {}
  for _, id in ipairs(Utility.prepareUniversalCards(room)) do
    local card = Fk:getCardById(id)
    if not card.is_derived and ((card.type == Card.TypeBasic and string.find(guhuo_type, "b")) or
    (card.type == Card.TypeTrick and string.find(guhuo_type, card.sub_type == Card.SubtypeDelayedTrick and "d" or "t"))) then
      if not (true_name and table.contains(all_names, card.trueName)) then
        table.insert(all_names, card.trueName)
        table.insert(cards, id)
      end
    end
  end
  return cards
end

-- 泛转化技能的牌名筛选，仅用于interaction里对泛转化牌名的合法性检测（按无对应实体牌的牌来校验）
--
-- 注：如果需要无距离和次数限制则需要外挂TargetModSkill（来点功能型card mark？）
--
---@param player Player @ 使用者Self
---@param skill_name string @ 泛转化技的技能名
---@param card_names string[] @ 待判定的牌名列表
---@param subcards? string[] @ 子卡（某些技能可以提前确定子卡，如奇策、妙弦）
---@return string[] @ 返回牌名列表
Utility.getViewAsCardNames = function(player, skill_name, card_names, subcards)
  if Fk.currentResponsePattern == nil then
    return table.filter(card_names, function (name)
      local card = Fk:cloneCard(name)
      card.skillName = skill_name
      if subcards then
        card:addSubcards(subcards)
      end
      return player:canUse(card) and not player:prohibitUse(card)
    end)
  else
    return table.filter(card_names, function (name)
      local card = Fk:cloneCard(name)
      card.skillName = skill_name
      if subcards then
        card:addSubcards(subcards)
      end
      return Exppattern:Parse(Fk.currentResponsePattern):match(card)
    end)
  end
end

-- 获取加入游戏的卡的牌名（暂不考虑装备牌），常用于泛转化技能的interaction
---@param guhuo_type string @ 神杀智慧，用"btd"三个字母的组合表示卡牌的类别， b 基本牌, t - 普通锦囊牌, d - 延时锦囊牌
---@param true_name? boolean @ 是否使用真实卡名（即不区分【杀】、【无懈可击】等的具体种类）
---@return string[] @ 返回牌名列表
Utility.getAllCardNames = function(guhuo_type, true_name)
  local all_names = {}
  for _, id in ipairs(Fk:getAllCardIds()) do
    local card = Fk:getCardById(id)
    if not card.is_derived and ((card.type == Card.TypeBasic and string.find(guhuo_type, "b")) or 
    (card.type == Card.TypeTrick and string.find(guhuo_type, card.sub_type == Card.SubtypeDelayedTrick and "d" or "t"))) then
      table.insertIfNeed(all_names, true_name and card.trueName or card.name)
    end
  end
  return all_names
end

--清除一名角色手牌中的某种标记
---@param player ServerPlayer @ 要清理标记的角色
---@param name string @ 要清理的标记名
Utility.clearHandMark = function(player, name)
  local room = player.room
  local card = nil
  for _, id in ipairs(player:getCardIds(Player.Hand)) do
    card = Fk:getCardById(id)
    if card:getMark(name) > 0 then
      room:setCardMark(card, name, 0)
    end
  end
end

--- 执行额外回合（修复getCurrentExtraTurnReason bug）
---@param player ServerPlayer
---@param delay? boolean
---@param skillName string
Utility.gainAnExtraTurn = function(player, delay, skillName)
  local room = player.room
  delay = (delay == nil) and true or delay
  if delay then
    local logic = room.logic
    local turn = logic:getCurrentEvent():findParent(GameEvent.Turn, true)
    if turn then
      turn:prependExitFunc(function() Utility.gainAnExtraTurn(player, false, skillName) end)
      return
    end
  end

  room:sendLog{
    type = "#GainAnExtraTurn",
    from = player.id
  }

  local current = room.current
  room.current = player

  player.tag["_extra_turn_count"] = player.tag["_extra_turn_count"] or {}
  local ex_tag = player.tag["_extra_turn_count"]
  table.insert(ex_tag, skillName)

  GameEvent(GameEvent.Turn, player):exec()

  table.remove(ex_tag)

  room.current = current
end

Utility.Discussion = function(data)
  --local discussionData = table.unpack(self.data)
  local discussionData = data
  --local room = self.room
  local room = data.from.room ---@type Room
  local logic = room.logic
  local from = discussionData.from
  --logic:trigger(fk.StartDiscussion, discussionData.from, discussionData)

  if discussionData.reason ~= "" then
    room:sendLog{
      type = "#StartDiscussionReason",
      from = from.id,
      arg = discussionData.reason,
    }
  end
  discussionData.color = "noresult"

  local extraData = {
    num = 1,
    min_num = 1,
    include_equip = false,
    pattern = ".",
    reason = discussionData.reason,
  }
  local prompt = "#askForDiscussion"
  local data = { "choose_cards_skill", prompt, true, extraData }

  local targets = {}
  for _, to in ipairs(discussionData.tos) do
    if not (discussionData.results[to.id] and discussionData.results[to.id].toCard) then
      table.insert(targets, to)
      to.request_data = json.encode(data)
    end
  end

  room:notifyMoveFocus(targets, "AskForDiscussion")
  room:doBroadcastRequest("AskForUseActiveSkill", targets)

  for _, p in ipairs(targets) do
    local discussionCard
    if p.reply_ready then
      local replyCard = json.decode(p.client_reply).card
      discussionCard = Fk:getCardById(json.decode(replyCard).subcards[1])
    else
      discussionCard = Fk:getCardById(p:getCardIds(Player.Hand)[1])
    end

    discussionData.results[p.id] = discussionData.results[p.id] or {}
    discussionData.results[p.id].toCard = discussionCard
    discussionData.results[p.id].opinion = discussionCard.color

    p:showCards({discussionCard})
  end
  logic:trigger("fk.DiscussionCardsDisplayed", nil, discussionData)

  local red, black = 0, 0
  for toId, result in pairs(discussionData.results) do
    local to = room:getPlayerById(toId)
    if result.opinion == Card.Red then
      red = red + 1
    elseif result.opinion == Card.Black then
      black = black + 1
    end

    -- local singleDiscussionData = {
    --   from = from,
    --   to = to,
    --   toCard = result.toCard,
    --   color = result.toCard:getColorString(),
    --   reason = discussionData.reason,
    -- }

    --logic:trigger(fk.DiscussionResultConfirmed, nil, singleDiscussionData)
  end

  local discussionResult = "noresult"
  if red > black then
    discussionResult = "red"
  elseif red < black then
      discussionResult = "black"
  end
  discussionData.color = discussionResult

  room:sendLog{
    type = "#ShowDiscussionResult",
    from = from.id,
    arg = discussionResult
  }
  local ret = from.deputyGeneral and Fk:translate(from.general) .. '/' .. Fk:translate(from.deputyGeneral) or Fk:translate(from.general)
  room:doBroadcastNotify("ShowToast", ret .. " " .. Fk:translate("#DiscussionResult") .. " " .. Fk:translate(discussionResult))

  logic:trigger("fk.DiscussionResultConfirmed", from, discussionData)

  if logic:trigger("fk.DiscussionFinished", from, discussionData) then
    logic:breakEvent()
  end
  return discussionData  --FIXME
end
Fk:loadTranslationTable{
  ["#StartDiscussionReason"] = "%from 由于 %arg 而发起议事",
  ["#askForDiscussion"] = "请展示一张手牌进行议事",
  ["AskForDiscussion"] = "议事",
  ["#ShowDiscussionResult"] = "%from 的议事结果为 %arg",
  ["noresult"] = "无结果",
  ["#DiscussionResult"] = "的议事结果为",
}

Utility.JointPindianEvent = "GameEvent.JointPindian"

Fk:addGameEvent(Utility.JointPindianEvent, nil, function (self)
  local pindianData = table.unpack(self.data) ---@class PindianStruct
  local room = self.room
  local logic = room.logic
  logic:trigger(fk.StartPindian, pindianData.from, pindianData)

  if pindianData.reason ~= "" then
    room:sendLog{
      type = "#StartPindianReason",
      from = pindianData.from.id,
      arg = pindianData.reason,
    }
  end

  local extraData = {
    num = 1,
    min_num = 1,
    include_equip = false,
    pattern = ".",
    reason = pindianData.reason,
  }
  local prompt = "#askForPindian:::" .. pindianData.reason
  local data = { "choose_cards_skill", prompt, false, extraData }

  local targets = {}
  local moveInfos = {}
  if not pindianData.fromCard then
    table.insert(targets, pindianData.from)
    pindianData.from.request_data = json.encode(data)
  else
    local _pindianCard = pindianData.fromCard
    local pindianCard = _pindianCard:clone(_pindianCard.suit, _pindianCard.number)
    pindianCard:addSubcard(_pindianCard.id)

    pindianData.fromCard = pindianCard

    table.insert(moveInfos, {
      ids = { _pindianCard.id },
      from = pindianData.from.id,
      fromArea = room:getCardArea(_pindianCard.id),
      toArea = Card.Processing,
      moveReason = fk.ReasonPut,
      skillName = pindianData.reason,
      moveVisible = true,
    })
  end
  for _, to in ipairs(pindianData.tos) do
    if pindianData.results[to.id] and pindianData.results[to.id].toCard then
      local _pindianCard = pindianData.results[to.id].toCard
      local pindianCard = _pindianCard:clone(_pindianCard.suit, _pindianCard.number)
      pindianCard:addSubcard(_pindianCard.id)

      pindianData.results[to.id].toCard = pindianCard

      table.insert(moveInfos, {
        ids = { _pindianCard.id },
        from = to.id,
        fromArea = room:getCardArea(_pindianCard.id),
        toArea = Card.Processing,
        moveReason = fk.ReasonPut,
        skillName = pindianData.reason,
        moveVisible = true,
      })
    else
      table.insert(targets, to)
      to.request_data = json.encode(data)
    end
  end

  room:notifyMoveFocus(targets, "AskForPindian")
  room:doBroadcastRequest("AskForUseActiveSkill", targets)

  for _, p in ipairs(targets) do
    local _pindianCard
    if p.reply_ready then
      local replyCard = json.decode(p.client_reply).card
      _pindianCard = Fk:getCardById(json.decode(replyCard).subcards[1])
    else
      _pindianCard = Fk:getCardById(p:getCardIds(Player.Hand)[1])
    end

    local pindianCard = _pindianCard:clone(_pindianCard.suit, _pindianCard.number)
    pindianCard:addSubcard(_pindianCard.id)

    if p == pindianData.from then
      pindianData.fromCard = pindianCard
    else
      pindianData.results[p.id] = pindianData.results[p.id] or {}
      pindianData.results[p.id].toCard = pindianCard
    end

    table.insert(moveInfos, {
      ids = { _pindianCard.id },
      from = p.id,
      toArea = Card.Processing,
      moveReason = fk.ReasonPut,
      skillName = pindianData.reason,
      moveVisible = true,
    })

    room:sendLog{
      type = "#ShowPindianCard",
      from = p.id,
      card = { _pindianCard.id },
    }
  end

  room:moveCards(table.unpack(moveInfos))

  logic:trigger(fk.PindianCardsDisplayed, nil, pindianData)

  table.removeOne(targets, pindianData.from)
  local pdNum = {}
  pdNum[pindianData.from.id] = pindianData.fromCard.number
  for _, p in ipairs(targets) do
    pdNum[p.id] = pindianData.results[p.id].toCard.number
  end
  local winner, num
  for k, v in pairs(pdNum) do
    if not num or num < v then
      num = v
      winner = k
    elseif num == v then
      winner = nil
    end
  end
  if winner then
    winner = room:getPlayerById(winner) ---@type ServerPlayer
    pindianData.winner = winner
  end
  room:sendLog{
    type = "#ShowPindianResult",
    from = pindianData.from.id,
    to = table.map(targets, Util.IdMapper),
    arg = winner == pindianData.from and "pindianwin" or "pindiannotwin"
  }
  if winner then
    local ret = "<b>" .. (winner.deputyGeneral and Fk:translate(winner.general) .. '/' .. Fk:translate(winner.deputyGeneral) or Fk:translate(winner.general)) .. "</b>"
    room:doBroadcastNotify("ShowToast", ret .. " " .. Fk:translate("#WinsInJointPindian"))
  end
  for toId, result in pairs(pindianData.results) do
    local to = room:getPlayerById(toId)
    result.winner = winner
    local singlePindianData = {
      from = pindianData.from,
      to = to,
      fromCard = pindianData.fromCard,
      toCard = result.toCard,
      winner = winner,
      reason = pindianData.reason,
    }
    logic:trigger(fk.PindianResultConfirmed, nil, singlePindianData)
  end

  if logic:trigger(fk.PindianFinished, pindianData.from, pindianData) then
    logic:breakEvent()
  end
end, function (self)
  local pindianData = table.unpack(self.data)
  local room = self.room

  local toProcessingArea = {}
  local leftFromCardIds = room:getSubcardsByRule(pindianData.fromCard, { Card.Processing })
  if #leftFromCardIds > 0 then
    table.insertTable(toProcessingArea, leftFromCardIds)
  end

  for _, result in pairs(pindianData.results) do
    local leftToCardIds = room:getSubcardsByRule(result.toCard, { Card.Processing })
    if #leftToCardIds > 0 then
      table.insertTable(toProcessingArea, leftToCardIds)
    end
  end

  if #toProcessingArea > 0 then
    room:moveCards({
      ids = toProcessingArea,
      toArea = Card.DiscardPile,
      moveReason = fk.ReasonPutIntoDiscardPile,
    })
  end
  if not self.interrupted then return end
end)

Fk:loadTranslationTable{
  ["#WinsInJointPindian"] = "在共同拼点中 <b>赢</b>",
}

--- 进行共同拼点。
---@param player ServerPlayer
---@param tos ServerPlayer[]
---@param skillName string
---@param initialCard? Card
---@return PindianStruct
Utility.jointPindian = function(player, tos, skillName, initialCard)
  local pindianData = { from = player, tos = tos, reason = skillName, fromCard = initialCard, results = {}, winner = nil }
  local event = GameEvent:new(Utility.JointPindianEvent, pindianData)
  local _, ret = event:exec()
  return pindianData
end

dofile 'packages/utility/mobile_util.lua'
dofile 'packages/utility/qml_mark.lua'

return Utility
