---@class Utility
local Utility = require 'packages/utility/_base'

-- 不用return

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
