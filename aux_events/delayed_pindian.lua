---@class Utility
local Utility = require 'packages/utility/_base'

-- 不用return

--- DelayedPindianData 延时拼点的数据
---@class DelayedPindianDataSpec
---@field public from ServerPlayer @ 拼点发起者
---@field public tos ServerPlayer[] @ 拼点目标
---@field public fromCard? Card @ 拼点发起者的初始拼点牌
---@field public results table<ServerPlayer, PindianResult> @ 结果
---@field public winner? ServerPlayer @ 拼点胜利者，可能不存在
---@field public reason string @ 拼点原因，一般为技能名

---@class Utility.DelayedPindianData: DelayedPindianDataSpec, PindianData
Utility.DelayedPindianData = PindianData:subclass("DelayedPindianData")

--- 延时拼点 GameEvent
Utility.DelayedPindianEvent = "DelayedPindian"

local main = function (self)
  local pindianData = self.data ---@type DelayedPindianDataSpec
  local room = self.room
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
  ---@param card Card
  local virtualize = function (card)
    local _card = card:clone(card.suit, card.number)
    if card:getEffectiveId() then
      _card.subcards = { card:getEffectiveId() }
    end
    return _card
  end

  ---@type ServerPlayer[]
  local targets = {}
  local moveInfos = {}
  if pindianData.fromCard then
    pindianData.fromCard = virtualize(pindianData.fromCard)
    local cid = pindianData.fromCard:getEffectiveId()
    if cid and room:getCardArea(cid) ~= Card.Processing and
      not table.find(moveInfos, function (info)
        return table.contains(info.ids, cid)
      end) then
      table.insert(moveInfos, {
        ids = { cid },
        from = room.owner_map[cid],
        toArea = Card.Processing,
        moveReason = fk.ReasonPut,
        skillName = pindianData.reason,
        moveVisible = false,
      })
    end
  elseif not from:isKongcheng() then
    table.insert(targets, from)
  end
  for _, to in ipairs(pindianData.tos) do
    if results[to] and results[to].toCard then
      results[to].toCard = virtualize(results[to].toCard)

      local cid = results[to].toCard:getEffectiveId()
      if cid and room:getCardArea(cid) ~= Card.Processing and
        not table.find(moveInfos, function (info)
          return table.contains(info.ids, cid)
        end) then
        table.insert(moveInfos, {
          ids = { cid },
          from = room.owner_map[cid],
          toArea = Card.Processing,
          moveReason = fk.ReasonPut,
          skillName = pindianData.reason,
          moveVisible = false,
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
      req:setDefaultReply(to, {card = {subcards = {to:getCardIds(Player.Hand)[1]}}})
    end
    req.focus_text = "AskForPindian"

    for _, to in ipairs(targets) do
      local result = req:getResult(to)
      local card = Fk:getCardById(result.card.subcards[1])

      card = virtualize(card)

      if to == from then
        pindianData.fromCard = card
      else
        pindianData.results[to].toCard = card
      end

      if not table.find(moveInfos, function (info)
        return table.contains(info.ids, card:getEffectiveId())
      end) then
        table.insert(moveInfos, {
          ids = { card:getEffectiveId() },
          from = to,
          toArea = Card.Processing,
          moveReason = fk.ReasonPut,
          skillName = pindianData.reason,
          moveVisible = false,
        })
      end
    end
  end

  if #moveInfos > 0 then
    room:moveCards(table.unpack(moveInfos))
  end
end

local clear = function (self)
end

Fk:addGameEvent(Utility.DelayedPindianEvent, nil, main, clear, nil)

--- 进行延时拼点。
---@param player ServerPlayer
---@param tos ServerPlayer[]
---@param skillName string
---@param initialCard? Card
---@return Utility.DelayedPindianData
Utility.delayedPindian = function(player, tos, skillName, initialCard)
  local pindianData = Utility.DelayedPindianData:new{
    from = player,
    tos = tos,
    reason = skillName,
    fromCard = initialCard,
    results = {},
    winner = nil,
  }
  local event = GameEvent[Utility.DelayedPindianEvent]:create(pindianData)
  local _, ret = event:exec()
  return pindianData
end

--- 展示延时拼点牌并确定结果。
---@param data Utility.DelayedPindianData 延时拼点数据
---@return Utility.DelayedPindianData
Utility.delayedPindianDisplay = function(data)
  local pindianData = data
  local room = data.from.room
  local logic = room.logic
  local from = pindianData.from
  local cid = pindianData.fromCard:getEffectiveId()
  if cid then
    room:sendLog{
      type = "#ShowPindianCard",
      from = from.id,
      arg = pindianData.fromCard:toLogString(),
    }
    room:doBroadcastNotify("ShowCard", json.encode{
      from = nil,
      cards = { cid },
    })
    room:sendFootnote({ cid }, {
      type = "##PindianCard",
      from = from.id,
    })
  end
  for _, to in ipairs(pindianData.tos) do
    cid = pindianData.results[to].toCard:getEffectiveId()
    if cid then
      room:sendLog{
        type = "#ShowPindianCard",
        from = to.id,
        arg = pindianData.results[to].toCard:toLogString(),
      }
      room:doBroadcastNotify("ShowCard", json.encode{
        from = nil,
        cards = { cid },
      })
      room:sendFootnote({ cid }, {
        type = "##PindianCard",
        from = to.id,
      })
    end
  end

  logic:trigger(fk.PindianCardsDisplayed, nil, pindianData)

  for _, to in ipairs(pindianData.tos) do
    local result = pindianData.results[to]
    local fromCard, toCard = pindianData.fromCard, result.toCard
    if fromCard and toCard then
      if fromCard.number > toCard.number then
        result.winner = from
      elseif fromCard.number < toCard.number then
        result.winner = to
      end

      local singlePindianData = {
        from = from,
        to = to,
        fromCard = pindianData.fromCard,
        toCard = result.toCard,
        winner = result.winner,
        reason = pindianData.reason,
      }

      room:sendLog{
        type = "#ShowPindianResult",
        from = from.id,
        to = { to.id },
        arg = result.winner == from and "pindianwin" or "pindiannotwin"
      }

      -- room:setCardEmotion(pindianData._fromCard.id, result.winner == from and "pindianwin" or "pindiannotwin")
      -- room:setCardEmotion(pindianData.results[to]._toCard.id, result.winner == to and "pindianwin" or "pindiannotwin")

      logic:trigger(fk.PindianResultConfirmed, nil, singlePindianData)
    end
  end

  logic:trigger(fk.PindianFinished, from, pindianData)
  return data
end

--- 清理延时拼点牌。如果正常执行拼点流程，则直接调用此函数，否则给Turn加cleaner调用此函数。
---@param data Utility.DelayedPindianData 延时拼点数据
---@return Utility.DelayedPindianData
Utility.delayedPindianCleaner = function(data)
  local room = data.from.room

  local toThrow = {}
  local cid = data.fromCard and data.fromCard:getEffectiveId()
  if cid and room:getCardArea(cid) == Card.Processing then
    table.insertIfNeed(toThrow, cid)
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
end

Fk:loadTranslationTable{
  ["delayedPindian"] = "<b>延时拼点：</b><br>拼点牌亮出前，不立刻公布结果，将拼点牌扣置并移出游戏。此回合结束后，若仍未满足公开结果条件，"..
  "将这些拼点牌置入弃牌堆，且不执行后续拼点流程和时机。",
}
