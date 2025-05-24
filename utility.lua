-- 这个文件用来堆一些常用的函数，视情况可以分成多个文件
-- 因为不是拓展包，所以不能用init.lua（否则会被当拓展包加载并报错）
-- 因为本体里面已经有util了所以命名为完整版utility

-- 要使用的话在拓展开头加一句 local U = require "packages/utility/utility" 即可(注意别加.lua)

---@class Utility
local Utility = require 'packages/utility/_base'

-- 用来判定一些卡牌在此次移动事件发生之后没有再被移动过（注意：由于洗牌的存在，若判定处在弃牌堆的卡牌需要手动判区域）
--
-- 根据规则集，如果需要在卡牌移动后对参与此事件的卡牌进行操作，是需要过一遍这个检测的(=ﾟωﾟ)ﾉ
---@param room Room
---@param cards integer[] @ 待判定的卡牌
---@param end_id? integer @ 查询历史范围：从最后的事件开始逆序查找直到id为end_id的事件（不含），缺省值为当前移动事件的id
---@return integer[] @ 返回满足条件的卡牌的id列表
Utility.moveCardsHoldingAreaCheck = function(room, cards, end_id)
  fk.qWarning("Utility.moveCardsHoldingAreaCheck is deprecated! Use Room.logic:moveCardsHoldingAreaCheck instead")
  if #cards == 0 then return {} end
  if end_id == nil then
    local move_event = room.logic:getCurrentEvent():findParent(GameEvent.MoveCards, true)
    if move_event == nil then return {} end
    end_id = move_event.id
  end
  local ret = table.simpleClone(cards)
  room.logic:getEventsByRule(GameEvent.MoveCards, 1, function (e)
    for _, move in ipairs(e.data) do
      for _, info in ipairs(move.moveInfo) do
        table.removeOne(ret, info.cardId)
      end
    end
    return (#ret == 0)
  end, end_id)
  return ret
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
  fk.qWarning("Utility.canTransferTarget is deprecated!")
  local room = target.room
  local from = room:getPlayerById(data.from)
  if from:isProhibited(target, data.card) or
  not data.card.skill:modTargetFilter(target.id, {}, from, data.card, distance_limited) then return false end

  --target_filter check, for collateral,diversion...
  local ho_spair_target = data.subTargets
  if type(ho_spair_target) == "table" then
    local passed_target = {target.id}
    for _, c_pid in ipairs(ho_spair_target) do
      if not data.card.skill:modTargetFilter(c_pid, passed_target, from, data.card, distance_limited) then return false end
      table.insert(passed_target, c_pid)
    end
  end
  return true
end

-- 判断一张牌是否为非转化的卡牌（不为转化使用且对应实体牌数为1且两者牌名相同）
---@param card Card @ 待判别的卡牌
---@return boolean
Utility.isPureCard = function(card)
  return not card:isVirtual() and card.name == Fk:getCardById(card.id, true).name
end

-- 根据模式修改角色的属性
---@param player ServerPlayer @ 要换将的玩家
---@param mode string @ 模式名
---@return table @ 返回表，键为调整的角色属性，值为调整后的属性
Utility.changePlayerPropertyByMode = function(player, mode)
  local room = player.room
  if not Fk.game_modes[mode] then return {} end
  local func = Fk.game_modes[mode].getAdjustedProperty
  if type(func) == "function" then
    return func(player)
  else
    local list = {}
    if player.role == "lord" and player.role_shown and #room.players > 4 then
      list.hp = player.hp + 1
      list.maxHp = player.maxHp + 1
    end
    return list
  end
end

---@param player ServerPlayer @ 要换将的玩家
---@param new_general string @ 要变更的武将，若不存在则变身为孙策，孙策不存在变身为士兵
---@param maxHpChange? boolean @ 是否改变体力上限，默认改变
Utility.changeHero = function(player, new_general, maxHpChange)
  local room = player.room
  maxHpChange = (maxHpChange == nil) and true or maxHpChange

  local skills = {}
  for _, s in ipairs(player.player_skills) do
    if s:isPlayerSkill(player) then
      table.insertIfNeed(skills, s.name)
    end
  end
  if room.settings.gameMode == "m_1v2_mode" and player.role == "lord" then
    table.removeOne(skills, "m_feiyang")
    table.removeOne(skills, "m_bahu")
  end
  if #skills > 0 then
    room:handleAddLoseSkills(player, "-"..table.concat(skills, "|-"), nil, true, false)
  end
  local generals = {player.general}
  if player.deputyGeneral ~= "" then
    table.insert(generals, player.deputyGeneral)
  end
  room:returnToGeneralPile(generals)
  room:findGeneral(new_general)
  room:changeHero(player, new_general, false, false, true, false)
  room:changeHero(player, "", false, true, true, false)

  if player.dead or not maxHpChange then return false end
  local x = player:getGeneralMaxHp()
  if player.role == "lord" and player.role_shown and (#room.players > 4 or room.settings.gameMode == "m_1v2_mode") then
    x = x + 1
  end
  if player.maxHp ~= x then
    room:changeMaxHp(player, x - player.maxHp)
  end
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

-- 获取角色对应先辅Mark的实际值
---@param player Player @ 要被获取标记的那个玩家
---@param name string @ 标记名称（不带前缀）
---@return any
Utility.getXianfuMark = function(player, name)
  return type(player:getMark("@[xianfu]" .. name)) == "table" and player:getMark("@[xianfu]" .. name).value or 0
end

-- 设置角色对应私人Mark
---@param player ServerPlayer @ 要被获取标记的那个玩家
---@param name string @ 标记名称（不带前缀）
---@param value any @ 标记实际值
---@param visible? boolean? @ 是否公开标记
Utility.setXianfuMark = function(player, name, value, visible)
  local mark = player:getMark("@[xianfu]" .. name)
  if value == nil or value == 0 then
    player.room:setPlayerMark(player, "@[xianfu]" .. name, 0)
  else
    if type(mark) ~= "table" then mark = {} end
    mark.visible = visible
    mark.value = value
    player.room:setPlayerMark(player, "@[xianfu]" .. name, mark)
  end
end

--让一名角色的先辅mark对所有角色都可见
---@param player ServerPlayer @ 要公开标记的角色
---@param name? string @ 要公开的标记名（不含前缀）
Utility.showXianfuMark = function(player, name)
  local room = player.room
  local mark = player:getMark("@[xianfu]" .. name)
  if type(mark) == "table" then
    mark.visible = true
    room:setPlayerMark(player, "@[xianfu]" .. name, mark)
  end
end

--- 询问玩家交换两堆卡牌中的任意张（操作逻辑为点选等量需要交换的卡牌）。
---@param player ServerPlayer @ 要询问的玩家
---@param name1 string @ 第一行卡牌名称
---@param name2 string @ 第一行卡牌名称
---@param cards1 integer[] @ 第一行的卡牌
---@param cards2 integer[] @ 第二行的卡牌
---@param prompt string @ 操作提示
---@param n? integer @ 至多可交换的卡牌数量（不填则无限制）
---@param cancelable? boolean @ 是否可取消，默认可以
---@return integer[]
Utility.askForExchange = function(player, name1, name2, cards1, cards2, prompt, n, cancelable)
  fk.qWarning("Utility.askForExchange is deprecated! Use Room:askToArrangeCards instead")
  return player.room:askForPoxi(player, "qml_exchange", {
    { name1, cards1 },
    { name2, cards2 },
  }, {prompt, n or 9999, cancelable == false}, (cancelable == nil) and true or cancelable)
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
    if data == nil or #selected == 0 then return false end
    local cards = data[1][2]
    return #table.filter(selected, function (id)
      return table.contains(cards, id)
    end) *2 == #selected
  end,
  prompt = function (data, extra_data)
    return extra_data and extra_data[1] or "#AskForQMLExchange"
  end,
  default_choice = function (data, extra_data)
    if data == nil or extra_data == nil or not extra_data[3] then return {} end
    local ret = {}
    local max = extra_data[2]
    for _, dat in ipairs(data) do
      table.insertTable(ret, table.slice(dat[2], 1, max + 1))
    end
    return ret
  end,
}

Fk:loadTranslationTable{
  ["qml_exchange"] = "换牌",
  ["#AskForQMLExchange"] = "选择要交换的卡牌",
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
  local cardsToWatch = table.filter(all_cards or cards, function (id)
    return player.room:getCardArea(id) == Player.Hand and player.room:getCardOwner(id) ~= player
  end)
  if #cardsToWatch > 0 then
    local log = {
      type = "#WatchCard",
      from = player.id,
      card = cardsToWatch,
    }
    player:doNotify("GameLog", json.encode(log))
  end
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


--- 类似于askForCardsChosen，适用于“选择每个区域各一张牌”
---@param chooser ServerPlayer @ 要被询问的人
---@param target ServerPlayer @ 被选牌的人
---@param flag any @ 用"hej"三个字母的组合表示能选择哪些区域, h - 手牌区, e - 装备区, j - 判定区
---@param skill_name? string @ 技能名（暂时没用的参数，poxi没提供接口）
---@param prompt? string @ 提示信息（暂时没用的参数，poxi没提供接口）
---@param disable_ids? integer[] @ 不允许选的牌
---@param cancelable? boolean @ 是否可以点取消，默认是
---@return integer[] @ 选择的id
Utility.askforCardsChosenFromAreas = function(chooser, target, flag, skill_name, prompt, disable_ids, cancelable)
  cancelable = (cancelable == nil) and true or cancelable
  disable_ids = disable_ids or {}
  local card_data = {}
  if type(flag) ~= "string" then
    flag = "hej"
  end
  local data = {
    to = target.id,
    skillName = skill_name,
    prompt = prompt,
  }
  local visible_data = {}
  if string.find(flag, "h") then
    local cards = table.filter(target:getCardIds("h"), function (id)
      return not table.contains(disable_ids, id)
    end)
    if #cards > 0 then
      table.insert(card_data, {"$Hand", cards})
      for _, id in ipairs(cards) do
        if not chooser:cardVisible(id) then
          visible_data[tostring(id)] = false
        end
      end
      if next(visible_data) == nil then visible_data = nil end
      data.visible_data = visible_data
    end
  end
  if string.find(flag, "e") then
    local cards = table.filter(target:getCardIds("e"), function (id)
      return not table.contains(disable_ids, id)
    end)
    if #cards > 0 then
      table.insert(card_data, {"$Equip", cards})
    end
  end
  if string.find(flag, "j") then
    --- TODO: 蓄谋可见性判断
    local cards = table.filter(target:getCardIds("j"), function (id)
      return not table.contains(disable_ids, id)
    end)
    if #cards > 0 then
      table.insert(card_data, {"$Judge", cards})
    end
  end
  if #card_data == 0 then return {} end
  local ret = chooser.room:askForPoxi(chooser, "askforCardsChosenFromAreas", card_data, data, cancelable)
  return ret
end

Fk:addPoxiMethod{
  name = "askforCardsChosenFromAreas",
  prompt = function (data, extra_data)
    if extra_data then
      if extra_data.prompt then return extra_data.prompt end
      if extra_data.skillName and extra_data.to then
        return "#askforCardsChosenFromAreas::"..extra_data.to..":"..extra_data.skillName
      end
    end
    return "askforCardsChosenFromAreas"
  end,
  card_filter = function (to_select, selected, data, extra_data)
    if data and #selected < #data then
      for _, id in ipairs(selected) do
        for _, v in ipairs(data) do
          if table.contains(v[2], id) and table.contains(v[2], to_select) then
            return false
          end
        end
      end
      return true
    end
  end,
  feasible = function(selected, data)
    return data and #data == #selected
  end,
  default_choice = function(data)
    if not data then return {} end
    local cids = table.map(data, function(v) return v[2][1] end)
    return cids
  end,
}

Fk:loadTranslationTable{
  ["askforCardsChosenFromAreas"] = "选牌",
  ["#askforCardsChosenFromAreas"] = "%arg：选择 %dest 每个区域各一张牌",
}

--- 让玩家观看一些卡牌（用来取代fillAG式观看）。
---@param player ServerPlayer | ServerPlayer[] @ 要询问的玩家
---@param cards integer[] @ 待选卡牌
---@param skillname? string @ 烧条技能名
---@param prompt? string @ 操作提示
Utility.viewCards = function(player, cards, skillname, prompt)
  if player.class then
    Utility.askforChooseCardsAndChoice(player, cards, {}, skillname or "utility_viewcards", prompt or "$ViewCards", {"OK"})
  else
    for _, p in ipairs(player) do
      p.request_data = json.encode({
        path = "packages/utility/qml/ChooseCardsAndChoiceBox.qml",
        data = {
          cards,
          {},
          prompt or "$ViewCards",
          { "OK" },
          1,
          1,
          {}
        },
      })
    end

    local room = player[1].room
    room:notifyMoveFocus(player, skillname or "utility_viewcards")
    room:doBroadcastRequest("CustomDialog", player)
  end
end

Fk:loadTranslationTable{
  ["utility_viewcards"] = "观看卡牌",
  ["$ViewCards"] = "请观看卡牌",
  ["$ViewCardsFrom"] = "请观看 %src 的卡牌",
  ["#WatchCard"] = "%from 观看了牌 %card",
}

--- 判断一名角色是否为同族成员——OL宗族技专用
---@param player Player @ 自己
---@param target Player @ 待判断的角色
---@return any @ 如果有确定的家族，返回家族字符串表[]；对于自己必定返回true。否则返回false
Utility.FamilyMember = function (player, target)
  if target == player then
    return true
  end
  local family = {}
  local familyMap = {
    ["yingchuan_xun"] = {"xunshu", "xunchen", "xuncai", "xuncan", "xunyu", "xunyou"},
    ["chenliu_wu"] = {"wuxian", "wuyi", "wuban", "wukuang", "wuqiao"},
    ["yingchuan_han"] = {"hanshao", "hanrong"},
    ["taiyuan_wang"] = {"wangyun", "wangling", "wangchang", "wanghun", "wanglun", "wangguang", "wangmingshan", "wangshen"},
    ["yingchuan_zhong"] = {"zhongyao", "zhongyu", "zhonghui", "zhongyan"},
    ["hongnong_yang"] = {"yangci", "yangbiao", "yangxiu", "yangzhongh", "yangjun", "yangyan", "yangzhi"},
    ["wujun_lu"] = {"luji", "luxun", "lukang", "luyusheng", "lukai", "lujing"},
  }
  for f, members in pairs(familyMap) do
    if table.contains(members, Fk.generals[player.general].trueName) then
      table.insertIfNeed(family, f)
    end
    if table.contains(table.map(members, function (name)
      return "god"..name
    end), Fk.generals[player.general].trueName) then
      table.insertIfNeed(family, f)
    end
    if player.deputyGeneral ~= "" then
      if table.contains(members, Fk.generals[player.deputyGeneral].trueName) then
        table.insertIfNeed(family, f)
      end
      if table.contains(table.map(members, function (name)
        return "god"..name
      end), Fk.generals[player.deputyGeneral].trueName) then
        table.insertIfNeed(family, f)
      end
    end
  end
  if #family == 0 then return false end
  local ret = {}
  for _, f in ipairs(family) do
    local members = familyMap[f]
    if table.contains(members, Fk.generals[target.general].trueName) then
      table.insertIfNeed(ret, f)
    end
    if target.deputyGeneral ~= "" and table.contains(members, Fk.generals[target.deputyGeneral].trueName) then
      table.insertIfNeed(ret, f)
    end
  end
  if #ret == 0 then return false end
  return ret
end

--- 改变一名角色的转换技状态，自动转换插画阴阳形态
---@param player ServerPlayer @ 自己
---@param skill_name string @ 转换技技能名
---@param switch_state integer? @ 要切换到的状态，不填则默认与当前状态不同
---@param prefix string[]? @ 要检测的武将前缀{阳形态前缀, 阴形态前缀}，不填则默认检测 {"tymou__", "tymou2__"}
---@return any @ 
Utility.SetSwitchSkillState = function (player, skill_name, switch_state, prefix)
  assert(prefix == nil or #prefix == 2, "prefix error")
  if switch_state == nil then
    switch_state = player:getSwitchSkillState(skill_name, true)
  end
  if player:getSwitchSkillState(skill_name, true) == switch_state then
    player.room:setPlayerMark(player, MarkEnum.SwithSkillPreName .. skill_name, switch_state)
    player:setSkillUseHistory(skill_name, 0, Player.HistoryGame)
  end

  prefix = prefix or {"tymou__", "tymou2__"}
  local generalName = nil
  for _, str in ipairs(prefix) do
    if player.general:startsWith(str) and
      table.contains(Fk.generals[player.general]:getSkillNameList(), skill_name) then
      generalName = player.general
    end
    if generalName == nil then
      if player.deputyGeneral ~= "" then
        if player.deputyGeneral:startsWith(str) and
          table.contains(Fk.generals[player.deputyGeneral]:getSkillNameList(), skill_name) then
          generalName = player.deputyGeneral
        end
      end
    end
  end
  if generalName == nil then return end
  local name = Fk.generals[generalName].trueName
  if switch_state == fk.SwitchYang then
    name = prefix[1] .. name
  else
    name = prefix[2] .. name
  end
  if generalName == player.deputyGeneral then
    player.deputyGeneral = name
    player.room:broadcastProperty(player, "deputyGeneral")
  else
    player.general = name
    player.room:broadcastProperty(player, "general")
  end
end

-- 卡牌标记 进入弃牌堆销毁 例OL蒲元
MarkEnum.DestructIntoDiscard = "__destr_discard"

-- 卡牌标记 离开自己的装备区销毁 例新服刘晔
MarkEnum.DestructOutMyEquip = "__destr_my_equip"

-- 卡牌标记 进入非装备区销毁(可在装备区/处理区移动) 例OL冯方女
MarkEnum.DestructOutEquip = "__destr_equip"

--花色互转（支持int(Card.Heart)，string("heart")，icon("♥")，symbol(translate后的红色"♥")）
---@param value any @ 花色
---@param input_type "int"|"str"|"icon"|"sym"
---@param output_type "int"|"str"|"icon"|"sym"
Utility.ConvertSuit = function(value, input_type, output_type)
  local mapper = {
    ["int"] = {Card.Spade, Card.Heart, Card.Club, Card.Diamond, Card.NoSuit},
    ["str"] = {"spade", "heart", "club", "diamond", "nosuit"},
    ["icon"] = {"♠", "♥", "♣", "♦", ""},
    ["sym"] = {"log_spade", "log_heart", "log_club", "log_diamond", "log_nosuit"},
  }
  return mapper[output_type][table.indexOf(mapper[input_type], value)]
end

--将数字转换为汉字，或将汉字转换为数字
---@param value number | string @ 数字或汉字
---@param to_num boolean? @ 是否转换为数字
---@return number | string @ 结果
Utility.ConvertNumber = function(value, to_num)
  local ret = "" ---@type number | string
  local candidate = {"零", "一", "二", "三", "四", "五", "六", "七", "八", "九"}
  local space = {"十", "百", "千"}

  if to_num then
    if tonumber(value) then return tonumber(value) end
    -- 耦一个两
    if value == "两" then return 2 end
    if value:find("万") or value:find("亿") then
      printf("你确定需要<%s>那么大的数字？", value)
      return value
    end
    local leng = value:len()
    for i = leng, 1, -1 do
      local _start = (i - 1) * 3 + 1
      local _end = (i) * 3
      local num = value:sub(_start, _end)
      if table.contains(candidate, num) then
        ret = tostring(table.indexOf(candidate, num) - 1) .. ret
      elseif table.contains(space, num) then
        local pos = table.indexOf(space, num) + 1
        local suc = pos - ret:len() - 1
        if suc > 0 then
          for j = 1, suc, 1 do
            ret = "0" .. ret
          end
        end
        if i == 1 then
          ret = "1" .. ret
        end
      elseif i == 1 then
        local ext = value:sub(1, 6)
        if ext == "两" then ret = 2 end
        if table.contains({"两百", "两千"}, ext) then
          ret = "2" .. ret
        end
      end
    end
    ret = tonumber(ret)
  else
    if not tonumber(value) then return value end
    local str = tostring(value)
    if value > 9999 then
      printf("你确定需要<%s>那么大的数字？", str)
      return value
    end
    local leng = str:len()
    for i = leng, 1, -1 do
      local pos = leng - i
      local num = candidate[tonumber(str:sub(i, i)) + 1]
      if pos > 0 then
        num = num .. space[pos - 1 % 3 + 1]
      end
      ret = num .. ret
    end
    if leng > 1 then
      ret = string.gsub(ret, "^一十", "")
    end
    for _, spc in ipairs(space) do
      ret = string.gsub(ret, "零" .. spc, "零")
    end
    ret = string.gsub(ret, "零零+", "零")
  end
  return ret
end

-- 阶段互译 int和str类型互换
---@param phase string|integer|table
Utility.ConvertPhse = function(phase)
  if type(phase) == "table" then
    return table.map(phase, function (p)
      return Utility.ConvertPhse(p)
    end)
  end
  local phase_table = {
    [1] = "phase_roundstart",
    [2] = "phase_start",
    [3] = "phase_judge",
    [4] = "phase_draw",
    [5] = "phase_play",
    [6] = "phase_discard",
    [7] = "phase_finish",
    [8] = "phase_notactive",
    [9] = "phase_phasenone",
  }
  return type(phase) == "string" and table.indexOf(phase_table, phase) or phase_table[phase]
end

---增加标记数量的使用杀次数上限，可带后缀
MarkEnum.SlashResidue = "__slash_residue"
---使用杀无次数限制，可带后缀
MarkEnum.SlashBypassTimes = "__slash_by_times"
---使用杀无距离限制，可带后缀
MarkEnum.SlashBypassDistances = "__slash_by_dist"


--- PresentCardData 赠予数据
---@class PresentCardDataSpec
---@field public from ServerPlayer @ 发起赠予的玩家
---@field public to ServerPlayer @ 接受赠予的玩家
---@field public card Card @ 赠予的牌
---@field public skill_name? string @ 技能名

---@class Utility.PresentCardData: PresentCardDataSpec, TriggerData
Utility.PresentCardData = TriggerData:subclass("PresentCardData")

--- TriggerEvent
---@class Utility.PresentCardTriggerEvent: TriggerEvent
---@field public data Utility.PresentCardData
Utility.PresentCardTriggerEvent = TriggerEvent:subclass("PresentCardEvent")

--- 赠予前，用于增加赠予失败参数
---@class Utility.BeforePresentCard: Utility.PresentCardTriggerEvent
Utility.BeforePresentCard = Utility.PresentCardTriggerEvent:subclass("Utility.BeforePresentCard")
--- 赠予失败时
---@class Utility.PresentCardFail: Utility.PresentCardTriggerEvent
Utility.PresentCardFail = Utility.PresentCardTriggerEvent:subclass("Utility.PresentCardFail")
--- 赠予后
---@class Utility.BeforePresentCard: Utility.PresentCardTriggerEvent
Utility.AfterPresentCard = Utility.PresentCardTriggerEvent:subclass("Utility.AfterPresentCard")

---@alias PresentCardTrigFunc fun(self: TriggerSkill, event: Utility.PresentCardTriggerEvent,
---  target: ServerPlayer, player: ServerPlayer, data: Utility.PresentCardData):any

---@class SkillSkeleton
---@field public addEffect fun(self: SkillSkeleton, key: Utility.PresentCardTriggerEvent,
---  data: TrigSkelSpec<PresentCardTrigFunc>, attr: TrigSkelAttribute?): SkillSkeleton

--- 赠予
---@param player ServerPlayer @ 交出牌的玩家
---@param target ServerPlayer @ 获得牌的玩家
---@param card integer|Card @ 赠予的牌，一次只能赠予一张
---@param skill_name? string @ 技能名
---@return boolean
Utility.presentCard = function(player, target, card, skill_name)
  local room = player.room
  assert(#Card:getIdList(card) == 1)
  if type(card) == "number" then
    card = Fk:getCardById(card)
  end
  local data = {
    from = player,
    to = target,
    card = card,
    skill_name = skill_name,
  }
  room.logic:trigger(Utility.BeforePresentCard, player, data)
  if data.fail then
    room.logic:trigger(Utility.PresentCardFail, player, data)
    if table.contains(player:getCardIds("h"), card.id) then
      room:moveCardTo(card, Card.DiscardPile, player, fk.ReasonPutIntoDiscardPile, "present", nil, true, player)
    end
    return false
  end
  if card.type ~= Card.TypeEquip then
    data.fail = false
    room:moveCardTo(card, Card.PlayerHand, target, fk.ReasonGive, "present", nil, true, player)
  else
    local ret = room:moveCardIntoEquip(target, card.id, "present", true, player)
    if #ret == 0 then
      data.fail = true
      room.logic:trigger(Utility.PresentCardFail, player, data)
      return false
    else
      data.fail = false
    end
  end
  room.logic:trigger(Utility.AfterPresentCard, player, data)
  return true
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

--清除一名角色手牌中的某种标记
---@param player ServerPlayer @ 要清理标记的角色
---@param name string @ 要清理的标记名
Utility.clearHandMark = function(player, name)
  local room = player.room
  local card = nil
  for _, id in ipairs(player:getCardIds("h")) do
    card = Fk:getCardById(id)
    if card:getMark(name) > 0 then
      room:setCardMark(card, name, 0)
    end
  end
end

--- DiscussionData 议事的数据
---@class DiscussionDataSpec
---@field public from ServerPlayer @ 发起议事的角色
---@field public tos ServerPlayer[] @ 参与议事的角色
---@field public results table<ServerPlayer, DiscussionResult> @ 结果
---@field public color string @ 议事结果
---@field public reason string @ 议事原因

--- DiscussionResult 议事的结果数据
---@class DiscussionResult
---@field public toCards integer[] @ 议事展示的牌
---@field public opinion string @ 议事意见
---@field public opinions string[] @ 议事意见汇总

---@class Utility.DiscussionData: DiscussionDataSpec, TriggerData
Utility.DiscussionData = TriggerData:subclass("DiscussionData")

--- 议事 TriggerEvent
---@class Utility.DiscussionTE: TriggerEvent
---@field public data Utility.DiscussionData
Utility.DiscussionTE = TriggerEvent:subclass("DiscussionEvent")

--- 议事开始
---@class Utility.StartDiscussion: Utility.DiscussionTE
Utility.StartDiscussion = Utility.DiscussionTE:subclass("Utility.StartDiscussion")
--- 议事牌展示后
---@class Utility.DiscussionCardsDisplayed: Utility.DiscussionTE
Utility.DiscussionCardsDisplayed = Utility.DiscussionTE:subclass("Utility.DiscussionCardsDisplayed")
--- 议事结果确定时
---@class Utility.DiscussionResultConfirming: Utility.DiscussionTE
Utility.DiscussionResultConfirming = Utility.DiscussionTE:subclass("Utility.DiscussionResultConfirming")
--- 议事结果确定后
---@class Utility.DiscussionResultConfirmed: Utility.DiscussionTE
Utility.DiscussionResultConfirmed = Utility.DiscussionTE:subclass("Utility.DiscussionResultConfirmed")
--- 议事结束后
---@class Utility.DiscussionFinished: Utility.DiscussionTE
Utility.DiscussionFinished = Utility.DiscussionTE:subclass("Utility.DiscussionFinished")

---@alias DiscussionTrigFunc fun(self: TriggerSkill, event: Utility.DiscussionTE,
---  target: ServerPlayer, player: ServerPlayer, data: Utility.DiscussionData):any

---@class SkillSkeleton
---@field public addEffect fun(self: SkillSkeleton, key: Utility.DiscussionTE,
---  data: TrigSkelSpec<DiscussionTrigFunc>, attr: TrigSkelAttribute?): SkillSkeleton

--- 议事 GameEvent
Utility.DiscussionEvent = "Discussion"

Fk:addGameEvent(Utility.DiscussionEvent, nil, function (self)
  local discussionData = self.data ---@class DiscussionDataSpec
  local room = self.room ---@type Room
  local logic = room.logic
  local from = discussionData.from

  if discussionData.reason ~= "" then
    room:sendLog{
      type = "#StartDiscussionReason",
      from = from.id,
      arg = discussionData.reason,
    }
  end
  discussionData.color = "noresult"
  discussionData.results = {} ---@type table<ServerPlayer, DiscussionResult>

  logic:trigger(Utility.StartDiscussion, from, discussionData)


  local targets = {} ---@type ServerPlayer[]
  for _, to in ipairs(discussionData.tos) do
    if not (discussionData.results[to] and discussionData.results[to].opinion) then
      table.insert(targets, to)
    end
  end
  if #targets > 0 then
    local req = Request:new(targets, "AskForUseActiveSkill")
    req.focus_text = discussionData.reason
    local extraData = {
      num = 1,
      min_num = 1,
      include_equip = false,
      pattern = ".",
      reason = discussionData.reason,
    }
    local data = { "choose_cards_skill", "#askForDiscussion", false, extraData }
    for _, p in ipairs(targets) do
      req:setData(p, data)
      req:setDefaultReply(p, table.random(p:getCardIds("h"), 1))
    end
    req:ask()
    for _, p in ipairs(targets) do
      discussionData.results[p] = discussionData.results[p] or {}
      local result = req:getResult(p)
      if result ~= "" then
        local id
        if result.card then
          id = result.card.subcards[1]
        else
          id = result[1]
        end
        discussionData.results[p].toCards = {id}
        discussionData.results[p].opinion = Fk:getCardById(id):getColorString()
      end
    end
  end

  for _, p in ipairs(discussionData.tos) do
    discussionData.results[p] = discussionData.results[p] or {}

    if discussionData.results[p].toCards then
      p:showCards(discussionData.results[p].toCards)
    end

    if discussionData.results[p].opinion then
      room:sendLog{
        type = "#SendDiscussionOpinion",
        from = p.id,
        arg = discussionData.results[p].opinion,
        toast = true,
      }
    end
  end
  logic:trigger(Utility.DiscussionCardsDisplayed, nil, discussionData)

  discussionData.opinions = {}
  for to, result in pairs(discussionData.results) do
    if result.toCards then
      for _, id in ipairs(result.toCards) do
        local color = Fk:getCardById(id):getColorString()
        discussionData.opinions[color] = (discussionData.opinions[color] or 0) + 1
      end
    else
      discussionData.opinions[result.opinion] = (discussionData.opinions[result.opinion] or 0) + 1
    end
  end
  logic:trigger(Utility.DiscussionResultConfirming, from, discussionData)

  local max, result = 0, {}
  for color, count in pairs(discussionData.opinions) do
    if color ~= "nocolor" and color ~= "noresult" and count > max then
      max = count
    end
  end
  for color, count in pairs(discussionData.opinions) do
    if color ~= "nocolor" and color ~= "noresult" and count == max then
      table.insert(result, color)
    end
  end
  if #result == 1 then
    discussionData.color = result[1]
  end

  room:sendLog{
    type = "#ShowDiscussionResult",
    from = from.id,
    arg = discussionData.color,
    toast = true,
  }

  logic:trigger(Utility.DiscussionResultConfirmed, from, discussionData)

  if logic:trigger(Utility.DiscussionFinished, from, discussionData) then
    logic:breakEvent()
  end
  if not self.interrupted then return end
end)
Fk:loadTranslationTable{
  ["#StartDiscussionReason"] = "%from 由于 %arg 而发起议事",
  ["#askForDiscussion"] = "请展示一张手牌进行议事",
  ["AskForDiscussion"] = "议事",
  ["#SendDiscussionOpinion"] = "%from 的意见为 %arg",
  ["noresult"] = "无结果",
  ["#ShowDiscussionResult"] = "%from 的议事结果为 %arg",
}

--- 进行议事
---@param player ServerPlayer @ 发起议事的角色
---@param tos ServerPlayer[] @ 参与议事的角色
---@param reason string? @ 议事技能名
---@param extra_data any? @ extra_data
---@return Utility.DiscussionData
Utility.Discussion = function(player, tos, reason, extra_data)
  local discussionData = Utility.DiscussionData:new{
    from = player,
    tos = tos,
    reason = reason or "AskForDiscussion",
    extra_data = extra_data or {},
  }
  local event = GameEvent[Utility.DiscussionEvent]:create(discussionData)
  -- local event = GameEvent:new(Utility.DiscussionEvent, discussionData)
  local _, ret = event:exec()
  return discussionData
end

--- JointPindianData 共同拼点的数据
---@class JointPindianDataSpec
---@field public from ServerPlayer @ 拼点发起者
---@field public tos ServerPlayer[] @ 拼点目标
---@field public fromCard? Card @ 拼点发起者的初始拼点牌
---@field public results table<ServerPlayer, PindianResult> @ 结果
---@field public winner? ServerPlayer @ 拼点胜利者，可能不存在
---@field public reason string @ 拼点原因，一般为技能名
---@field public subType? string @ 共同拼点子类，如“逐鹿”

---@class Utility.JointPindianData: JointPindianDataSpec, PindianData
Utility.JointPindianData = PindianData:subclass("JointPindianData")

--- 共同拼点 GameEvent
Utility.JointPindianEvent = "JointPindian"

Fk:addGameEvent(Utility.JointPindianEvent, nil, function (self)
  local pindianData = self.data ---@type JointPindianDataSpec
  local room = self.room ---@type Room
  local logic = room.logic
  local from = pindianData.from
  local results = pindianData.results
  for _, to in pairs(pindianData.tos) do
    results[to] = results[to] or {}
  end

  logic:trigger(fk.StartPindian, from, pindianData)

  if pindianData.reason ~= "" then
    room:sendLog{
      type = "#StartPindianReason",
      from = from.id,
      arg = pindianData.reason,
    }
  end

  -- 将拼点牌变为虚拟牌
  local virtualize = function (card)
    local _card = card:clone(card.suit, card.number)
    if card:getEffectiveId() then
      _card.subcards = { card:getEffectiveId() }
    end
    card = _card
  end

  ---@type ServerPlayer[]
  local targets = {}
  local moveInfos = {}
  if pindianData.fromCard then
    virtualize(pindianData.fromCard)
    local cid = pindianData.fromCard:getEffectiveId()
    if cid and room:getCardArea(cid) ~= Card.Processing then
      table.insert(moveInfos, {
        ids = { cid },
        from = room.owner_map[cid],
        toArea = Card.Processing,
        moveReason = fk.ReasonPut,
        skillName = pindianData.reason,
        moveVisible = true,
      })
    end
  elseif not from:isKongcheng() then
    table.insert(targets, from)
  end
  for _, to in ipairs(pindianData.tos) do
    if results[to] and results[to].toCard then
      virtualize(results[to].toCard)

      local cid = results[to].toCard:getEffectiveId()
      if cid and room:getCardArea(cid) ~= Card.Processing then
        table.insert(moveInfos, {
          ids = { cid },
          from = room.owner_map[cid],
          toArea = Card.Processing,
          moveReason = fk.ReasonPut,
          skillName = pindianData.reason,
          moveVisible = true,
        })
      end
    elseif not to:isKongcheng() then
      table.insert(targets, to)
    end
  end

  if #targets ~= 0 then
    local extraData = {
      num = 1,
      min_num = 1,
      include_equip = false,
      pattern = ".",
      reason = pindianData.reason,
    }
    local prompt = "#askForPindian:::" .. pindianData.reason
    local req_data = { "choose_cards_skill", prompt, false, extraData }

    local req = Request:new(targets, "AskForUseActiveSkill")
    for _, to in ipairs(targets) do
      req:setData(to, req_data)
      req:setDefaultReply(to, {card = {subcards = {to:getCardIds("h")[1]}}})
    end
    req.focus_text = "AskForPindian"

    for _, to in ipairs(targets) do
      local result = req:getResult(to)
      local card = Fk:getCardById(result.card.subcards[1])

      virtualize(card)

      if to == from then
        pindianData.fromCard = card
      else
        pindianData.results[to].toCard = card
      end

      table.insert(moveInfos, {
        ids = { card:getEffectiveId() },
        from = to,
        toArea = Card.Processing,
        moveReason = fk.ReasonPut,
        skillName = pindianData.reason,
        moveVisible = true,
      })

      room:sendLog{
        type = "#ShowPindianCard",
        from = to.id,
        arg = card:toLogString(),
      }
    end
  end

  if #moveInfos > 0 then
    room:moveCards(table.unpack(moveInfos))
  end

  local cid = pindianData.fromCard:getEffectiveId()
  if cid then
    room:sendFootnote({ cid }, {
      type = "##PindianCard",
      from = from.id,
    })
  end
  for _, to in ipairs(pindianData.tos) do
    cid = pindianData.results[to].toCard:getEffectiveId()
    if cid then
      room:sendFootnote({ cid }, {
        type = "##PindianCard",
        from = to.id,
      })
    end
  end

  logic:trigger(fk.PindianCardsDisplayed, nil, pindianData)

  table.removeOne(targets, pindianData.from)
  local pdNum = {} ---@type table<ServerPlayer, integer> @ 所有角色的点数
  pdNum[pindianData.from] = pindianData.fromCard.number
  for _, p in ipairs(pindianData.tos) do
    pdNum[p] = pindianData.results[p].toCard.number
  end
  local winner, num = nil, -1 ---@type ServerPlayer?, integer
  for k, v in pairs(pdNum) do
    if num < v then
      num = v
      winner = k
    elseif num == v then
      winner = nil
    end
  end
  pindianData.winner = winner
  room:sendLog{
    type = "#ShowPindianResult",
    from = pindianData.from.id,
    to = table.map(targets, Util.IdMapper),
    arg = winner == pindianData.from and "pindianwin" or "pindiannotwin",
    toast = true,
  }
  if winner then
    if winner ~= pindianData.from then
      room:sendLog{
        type = "#ShowJointPindianWinner",
        from = winner.id,
        arg = "pindianwin",
        toast = true,
      }
    end
  else
    room:sendLog{
      type = "#JointPindianNoWinner",
      arg = pindianData.reason,
      toast = true,
    }
  end
  for to, result in pairs(pindianData.results) do
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
  local data = self.data
  local room = self.room

  local toThrow = {}
  local cid = data.fromCard and data.fromCard:getEffectiveId()
  if cid and room:getCardArea(cid) == Card.Processing then
    table.insert(toThrow, cid)
  end

  for _, result in pairs(data.results) do
    cid = result.toCard and result.toCard:getEffectiveId()
    if cid and room:getCardArea(cid) == Card.Processing then
      table.insertIfNeed(toThrow, cid)
    end
  end

  if #toThrow > 0 then
    room:moveCards({
      ids = toThrow,
      toArea = Card.DiscardPile,
      moveReason = fk.ReasonPutIntoDiscardPile,
    })
  end
  if not self.interrupted then return end
end)
Fk:loadTranslationTable{
  ["#ShowJointPindianWinner"] = "%from 在共同拼点中 %arg",
  ["#JointPindianNoWinner"] = "共同拼点 %arg 没有赢家",
}
--- 进行共同拼点。
---@param player ServerPlayer
---@param tos ServerPlayer[]
---@param skillName string
---@param initialCard? Card
---@return Utility.JointPindianData
Utility.jointPindian = function(player, tos, skillName, initialCard, subType)
  local pindianData = Utility.JointPindianData:new{
    from = player,
    tos = tos,
    reason = skillName,
    fromCard = initialCard,
    results = {},
    winner = nil,
    subType = subType,
  }
  local event = GameEvent[Utility.JointPindianEvent]:create(pindianData)
  -- local event = GameEvent:new(Utility.JointPindianEvent, pindianData)
  local _, ret = event:exec()
  return pindianData
end

Utility.startZhuLu = function(player, tos, skillName, initialCard)
  return Utility.jointPindian(player, tos, skillName, initialCard, "zhulu")
end

--- 竞争询问一名角色弃牌。可以取消。默认跳过弃牌
---@param room Room
---@param players table<ServerPlayer> @ 询问弃牌角色
---@param minNum integer @ 最小值
---@param maxNum integer @ 最大值
---@param includeEquip? boolean @ 能不能弃装备区？
---@param skillName? string @ 引发弃牌的技能名
---@param pattern? string @ 弃牌需要符合的规则
---@param prompt? string @ 提示信息
---@param skipDiscard? boolean @ 是否跳过弃牌。默认跳过
---@return ServerPlayer?, integer[] @ 响应角色，和弃掉的牌的id列表
Utility.askForRaceDiscard = function (room, players, minNum, maxNum, includeEquip, skillName, pattern, prompt, skipDiscard)
  pattern = pattern or "."
  skipDiscard = skipDiscard or (skipDiscard == nil)
  skillName = skillName or ""
  room:notifyMoveFocus(players, skillName)
  local extra_data = {
    num = maxNum,
    min_num = minNum,
    include_equip = includeEquip,
    skillName = skillName,
    pattern = pattern,
  }
  prompt = prompt or ("#AskForDiscard:::" .. maxNum .. ":" .. minNum)
  local data = {"discard_skill", prompt, true, extra_data}
  local winner = room:doRaceRequest("AskForUseActiveSkill", players, json.encode(data))
  local toDiscard = {}
  if winner then
    local ret = json.decode(winner.client_reply)
    toDiscard = ret.card.subcards
  end
  if winner and not skipDiscard then
    room:throwCard(toDiscard, skillName, winner, winner)
  end
  return winner, toDiscard
end




--- 询问选择若干个牌名
---@param room Room
---@param player ServerPlayer @ 询问角色
---@param names table<string> @ 可选牌名
---@param minNum integer @ 最小值
---@param maxNum integer @ 最大值
---@param skillName? string @ 技能名
---@param prompt? string @ 提示信息
---@param all_names? table<string> @ 所有显示的牌名
---@param cancelable? boolean @ 是否可以取消，默认不可
---@param repeatable? boolean @ 是否可以选择重复的牌名，默认不可
---@return table<string> @ 选择的牌名
Utility.askForChooseCardNames = function (room, player, names, minNum, maxNum, skillName, prompt, all_names, cancelable, repeatable)
  local choices = {}
  skillName = skillName or ""
  prompt = prompt or skillName
  if (cancelable == nil) then cancelable = false end
  if (repeatable == nil) then repeatable = false end
  all_names = all_names or names
  local result = room:askForCustomDialog(
    player, skillName or "",
    "packages/utility/qml/ChooseCardNamesBox.qml",
    { names, minNum, maxNum, prompt, all_names, cancelable, repeatable }
  )
  if result ~= "" then
    choices = json.decode(result)
  elseif not cancelable and minNum > 0 then
    choices = table.random(names, minNum)
    if #choices < minNum and repeatable then
      for i = 1, minNum - #choices do
        table.insert(choices, names[1])
      end
    end
  end
  return choices
end
Fk:loadTranslationTable{
  ["Clear All"] = "清空",
}

-- 用于选牌名的 interaction type ，和UI.ComboBox差不多，照着用就行
-- 必输参数：可选牌名choices；可输参数：全部牌名all_choices
Utility.CardNameBox = function(spec)
  spec.choices = type(spec.choices) == "table" and spec.choices or Util.DummyTable
  spec.all_choices = type(spec.all_choices) == "table" and spec.all_choices or spec.choices
  spec.default_choice = spec.default_choice and spec.default_choice or spec.choices[1]
  spec.type = "custom"
  spec.qml_path = "packages/utility/qml/SkillCardName"
  return spec
end


--- 按组展示牌，并询问选择若干个牌组（用于清正等）
---@param room Room
---@param player ServerPlayer @ 询问角色
---@param listNames table<string> @ 牌组名的表
---@param listCards table<table<integer>> @ 牌组所含id表的表
---@param minNum integer @ 最小值
---@param maxNum integer @ 最大值
---@param skillName? string @ 技能名
---@param prompt? string @ 提示信息
---@param allowEmpty? boolean @ 是否可以选择空的牌组，默认不可
---@param cancelable? boolean @ 是否可以取消，默认可
---@return table<string> @ 返回选择的牌组的组名列表
Utility.askForChooseCardList = function (room, player, listNames, listCards, minNum, maxNum, skillName, prompt, allowEmpty, cancelable)
  local choices = {}
  skillName = skillName or ""
  prompt = prompt or skillName
  if (allowEmpty == nil) then allowEmpty = false end
  if (cancelable == nil) then cancelable = true end
  local availableList = table.simpleClone(listNames)
  if not allowEmpty then
    for i = #listCards, 1, -1 do
      if #listCards[i] == 0 then
        table.remove(availableList, i)
      end
    end
  end
  -- set 'cancelable' to 'true' when the count of cardlist is out of range
  if not cancelable and #availableList < minNum then
    cancelable = true
  end
  local result = room:askForCustomDialog(
    player, skillName,
    "packages/utility/qml/ChooseCardListBox.qml",
    { listNames, listCards, minNum, maxNum, prompt, allowEmpty, cancelable }
  )
  if result ~= "" then
    choices = json.decode(result)
  elseif not cancelable and minNum > 0 then
    if #availableList > 0 then
      choices = table.random(availableList, minNum)
    end
  end
  return choices
end

--注册一些通用的TargetTip

-- 用于增加/减少目标的选人函数的TargetTip
-- extra_data:
-- targets integer[] @ 可选的玩家id数组
-- extra_data integer[] @ 卡牌的当前目标，是玩家id数组
Fk:addTargetTip{
  name = "addandcanceltarget_tip",
  target_tip = function(_, _, to_select, _, _, _, _, extra_data)
    if not table.contains(extra_data.targets, to_select.id) then return end
    if type(extra_data.extra_data) == "table" then
      if table.contains(extra_data.extra_data, to_select.id) then
        return { {content = "@@CancelTarget", type = "warning"} }
      else
        return { {content = "@@AddTarget", type = "normal"} }
      end
    end
  end,
}
Fk:loadTranslationTable{
  ["@@AddTarget"] = "增加目标",
  ["@@CancelTarget"] = "取消目标",
}



--- 从多种规则中选择一种并选牌
---@param player ServerPlayer @ 被询问的玩家
---@param patterns [string, integer, integer, string][] @ 选牌规则组。格式{{规则，选牌下限，选牌上限，提示名},{},...}
---@param skillName? string @ 技能名
---@param cancelable? boolean @ 能否点取消。默认可以
---@param prompt? string @ 提示信息
---@param extra_data? {expand_pile: string|table, discard_skill: boolean, [any]:any} @ 额外信息。可以选择"expand_pile"|"discard_skill"
---@return integer[], string @ 返回选择的牌，和选择的规则提示名
Utility.askForCardByMultiPatterns = function (player, patterns, skillName, cancelable, prompt, extra_data)
  skillName = skillName or "choose_cards_mutlipat_skill"
  cancelable = (cancelable == nil) or cancelable
  prompt = prompt or "#askForCardByMultiPatterns"
  extra_data = extra_data or {}
  local aval_cards = player:getCardIds("he")
  if type(extra_data.expand_pile) == "string" then
    table.insertTable(aval_cards, player:getPile(extra_data.expand_pile))
  elseif type(extra_data.expand_pile) == "table" then
    table.insertTable(aval_cards, extra_data.expand_pile)
  end
  if extra_data.discard_skill then
    aval_cards = table.filter(aval_cards, function(cid)
      return not player:prohibitDiscard(cid)
    end)
  end
  local aval_cardlist = {}
  local selecteable_patterns = {}
  for _, v in ipairs(patterns) do
    local cards = table.filter(aval_cards, function(cid)
      return Exppattern:Parse(v[1]):match(Fk:getCardById(cid))
    end)
    if #cards >= v[2] then
      table.insert(selecteable_patterns, v)
      table.insert(aval_cardlist, cards)
    end
  end
  if cancelable or #selecteable_patterns > 0 then
    extra_data.skillName = skillName
    extra_data.patterns = selecteable_patterns
    extra_data.all_patterns = patterns
    local success, dat = player.room:askToUseActiveSkill(player, {
      skill_name = "choose_cards_mutlipat_skill",
      prompt = prompt,
      cancelable = cancelable,
      extra_data = extra_data
    })
    if dat then
      return dat.cards, dat.interaction
    elseif cancelable then
      return {}, ""
    end
  end

  if #selecteable_patterns == 0 then
    return {}, ""
  else
    for i, v in ipairs(selecteable_patterns) do
      return table.random(aval_cardlist[i], v[2]), v[4]
    end
  end
end

--- GeneralAppearData 描述和武将牌登场有关的数据
---@class GeneralAppearDataSpec
---@field public m string? @ 主将
---@field public d string? @ 副将
---@field public reason string? @ 登场原因
---@field public prevented boolean? @ 登场是否被防止
---@field public prevented_reason string? @ 登场被防止的原因

---@class Utility.GeneralAppearData: GeneralAppearDataSpec, TriggerData
Utility.GeneralAppearData = TriggerData:subclass("GeneralAppearData")

--- 登场TriggerEvent
---@class Utility.GeneralAppearEvent: TriggerEvent
---@field public data Utility.GeneralAppearData
Utility.GeneralAppearEvent = TriggerEvent:subclass("GeneralAppearEvent")

--- 登场前
---@class Utility.GeneralAppeared: Utility.GeneralAppearEvent
Utility.BeforeGeneralAppeared = Utility.GeneralAppearEvent:subclass("Utility.BeforeGeneralAppeared")

--- 登场后
---@class Utility.GeneralAppeared: Utility.GeneralAppearEvent
Utility.GeneralAppeared = Utility.GeneralAppearEvent:subclass("Utility.GeneralAppeared")

---@alias GeneralAppearTrigFunc fun(self: TriggerSkill, event: Utility.GeneralAppearEvent,
---  target: ServerPlayer, player: ServerPlayer, data: Utility.GeneralAppearData):any

---@class SkillSkeleton
---@field public addEffect fun(self: SkillSkeleton, key: Utility.GeneralAppearEvent,
---  data: TrigSkelSpec<GeneralAppearTrigFunc>, attr: TrigSkelAttribute?): SkillSkeleton


--- 令一名隐匿者登场
---@param player ServerPlayer @ 登场的玩家
---@param reason? string @ 登场原因，一般为技能名（泰始）、扣减体力（"HpChanged"）、回合开始（"TurnStart"）
---@return boolean @ 返回是否成功登场
Utility.GeneralAppear = function (player, reason)
  local room = player.room
  local data = {
    m = player:getMark("__hidden_general"),
    d = player:getMark("__hidden_deputy"),
  }
  room.logic:trigger(Utility.BeforeGeneralAppeared, player, data)
  if data.prevented then
    return false
  end
  if Fk.generals[data.m] then
    player.general = player:getMark("__hidden_general")
    room:sendLog{
      type = "#RevealGeneral",
      from = player.id,
      arg = "mainGeneral",
      arg2 = data.m,
    }
  else
    data.m = nil
  end
  if Fk.generals[data.d] then
    player.deputyGeneral = player:getMark("__hidden_deputy")
    room:sendLog{
      type = "#RevealGeneral",
      from = player.id,
      arg = "deputyGeneral",
      arg2 = data.d,
    }
  else
    data.d = nil
  end
  if data.m == nil and data.d == nil then
    return false
  end

  data.reason = reason or "game_rule"
  room:handleAddLoseSkills(player, "-hidden_skill&", nil, false, true)
  room:setPlayerMark(player, "__hidden_general", 0)
  room:setPlayerMark(player, "__hidden_deputy", 0)
  local general = Fk.generals[player.general]
  local deputy = Fk.generals[player.deputyGeneral]
  player.gender = general.gender
  player.kingdom = general.kingdom
  room:broadcastProperty(player, "gender")
  room:broadcastProperty(player, "general")
  room:broadcastProperty(player, "deputyGeneral")
  room:askToChooseKingdom({player})
  room:broadcastProperty(player, "kingdom")

  if player:getMark("__hidden_record") ~= 0 then
    player.maxHp = player:getMark("__hidden_record").maxHp
    player.hp = player:getMark("__hidden_record").hp
  else
    player.maxHp = player:getGeneralMaxHp()
    player.hp = deputy and math.floor((deputy.hp + general.hp) / 2) or general.hp
  end
  player.shield = math.min(general.shield + (deputy and deputy.shield or 0), 5)
  if player:getMark("__hidden_record") ~= 0 then
    room:setPlayerMark(player, "__hidden_record", 0)
  else
    local changer = Fk.game_modes[room.settings.gameMode]:getAdjustedProperty(player)
    if changer then
      for key, value in pairs(changer) do
        player[key] = value
      end
    end
  end
  room:broadcastProperty(player, "maxHp")
  room:broadcastProperty(player, "hp")
  room:broadcastProperty(player, "shield")

  local lordBuff = player.role == "lord" and player.role_shown == true and #room.players > 4
  local skills = general:getSkillNameList(lordBuff)
  if deputy then
    table.insertTable(skills, deputy:getSkillNameList(lordBuff))
  end
  skills = table.filter(skills, function (s)
    local skill = Fk.skills[s]
    return skill and (#skill.skeleton.attached_kingdom == 0 or table.contains(skill.skeleton.attached_kingdom, player.kingdom))
  end)
  if #skills > 0 then
    room:handleAddLoseSkills(player, table.concat(skills, "|"), nil, false)
  end

  room.logic:trigger(Utility.GeneralAppeared, player, data)
end

dofile 'packages/utility/mobile_util.lua'
dofile 'packages/utility/qml_mark.lua'

local extension = Package:new("utility", Package.SpecialPack)
extension:loadSkillSkelsByPath("./packages/utility/aux_skills")
Fk:loadPackage(extension)

return Utility
