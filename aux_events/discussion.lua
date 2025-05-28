---@class Utility
local Utility = require 'packages/utility/_base'

-- 不用return

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
  local _, ret = event:exec()
  return discussionData
end
