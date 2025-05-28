---@class Utility
local Utility = require 'packages/utility/_base'

-- 不用return

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
