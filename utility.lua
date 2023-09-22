-- 这个文件用来堆一些常用的函数，视情况可以分成多个文件
-- 因为不是拓展包，所以不能用init.lua（否则会被当拓展包加载并报错）
-- 因为本体里面已经有util了所以命名为完整版utility

-- 要使用的话在拓展开头加一句local U = require "packages/utility/utility.lua" 即可

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
      if data.card.skill:modTargetFilter(p.id, {}, data.from, data.card, bypass_distances) then
        table.insert(tos, p.id)
      end
    end
  end
  return tos
end





return Utility
