---@class Utility
local Utility = require 'packages/utility/_base'

-- 不用return

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
