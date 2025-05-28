-- 这个文件用来堆一些常用的函数，视情况可以分成多个文件
-- 因为不是拓展包，所以不能用init.lua（否则会被当拓展包加载并报错）
-- 因为本体里面已经有util了所以命名为完整版utility

-- 要使用的话在拓展开头加一句 local U = require "packages/utility/utility" 即可(注意别加.lua)

---@class Utility
local Utility = require 'packages/utility/_base'

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

dofile 'packages/utility/mobile_util.lua'
dofile 'packages/utility/qml_mark.lua'

dofile 'packages/utility/aux_events/joint_pindian.lua'
dofile 'packages/utility/aux_events/discussion.lua'
dofile 'packages/utility/aux_events/delayed_pindian.lua'
dofile 'packages/utility/aux_events/general_appear.lua'
dofile 'packages/utility/aux_events/present.lua'

local extension = Package:new("utility", Package.SpecialPack)
extension:loadSkillSkelsByPath("./packages/utility/aux_skills")
Fk:loadPackage(extension)

return Utility
