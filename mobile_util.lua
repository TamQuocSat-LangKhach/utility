local Utility = require 'packages/utility/_base'

-- 不用return


--- 更改某角色蓄力技的能量或能量上限
---@param player ServerPlayer @ 角色
---@param num? integer @ 改变的能量
---@param max? integer @ 改变的能量上限
Utility.skillCharged = function(player, num, max)
  local room = player.room
  num = num or 0
  max = max or 0
  local max_num = math.max(0, player:getMark("skill_charge_max") + max)
  local new_num = math.min(max_num, math.max(0, player:getMark("skill_charge") + num))
  room:setPlayerMark(player, "skill_charge_max", max_num)
  room:setPlayerMark(player, "skill_charge", new_num)
  room:setPlayerMark(player, "@skill_charge", (max_num == 0 and num == 0) and 0 or (new_num.."/"..max_num))
end
Fk:loadTranslationTable{
  ["@skill_charge"] = "蓄力",
}




--- 进行谋奕/对策
---@param room Room @ 房间
---@param from ServerPlayer @ 拥有技能的角色
---@param to ServerPlayer @ 被发动技能的角色
---@param from_choices string[] @ 第一个角色的选项
---@param to_choices string[] @ 第二个角色的选项
---@param skillName string @ 技能名
---@param msg_type? integer @ 发送消息的类型 1:谋奕 2:对策 其他：不发送
---@param prompts? string|string[] @ 询问选择时的提示信息
---@return string[] @ 返回双方的选项
Utility.doStrategy = function(room, from, to, from_choices, to_choices, skillName, msg_type, prompts)
  msg_type = msg_type or 0
  if not prompts then
    if msg_type == 1 then
      prompts = {"#strategy-ask:" .. from.id, "#strategy-ask:" .. from.id}
    elseif msg_type == 2 then
      prompts = {"#countermeausre-ask:" .. from.id, "#countermeausre-ask:" .. from.id}
    else
      prompts = {"",""}
    end
  elseif type(prompts) == "string" then
    prompts = {prompts, prompts}
  end
  local data1 = json.encode({ from_choices, from_choices, skillName, prompts[1], true })
  from.request_data = data1
  local data2 = json.encode({ to_choices, to_choices, skillName, prompts[2], true })
  to.request_data = data2
  room:notifyMoveFocus({from,to}, "AskForChoice")
  room:doBroadcastRequest("AskForChoice", {from,to})
  local from_c = from.reply_ready and from.client_reply or table.random(from_choices)
  local to_c = to.reply_ready and to.client_reply or table.random(to_choices)
  local same = (table.indexOf(from_choices, from_c) == table.indexOf(to_choices, to_c))
  if msg_type == 1 then
    room:sendLog{
      type = "#StrategiesResult",
      from = from.id,
      to = {to.id},
      arg = same and "strategy_failed" or "strategy_success",
      toast = true,
    }
  elseif msg_type == 2 then
    room:sendLog{
      type = "#StrategiesResult",
      from = from.id,
      to = {to.id},
      arg = same and "countermeausre_success" or "countermeausre_failed",
      toast = true,
    }
  end
  return {from_c, to_c}
end
Fk:loadTranslationTable{
  ["strategy_success"] = "谋奕 成功",
  ["strategy_failed"] = "谋奕 失败",
  ["countermeausre_success"] = "对策 成功",
  ["countermeausre_failed"] = "对策 失败",
  ["#strategy-ask"] = "请响应“谋奕”：若你与对方选择不同，则%src谋奕成功，反之%src失败",
  ["#countermeausre-ask"] = "请响应“对策”：若你与对方选择相同，则%src对策成功，反之%src失败",
  ["#StrategiesResult"] = "%from 对 %to %arg",
}
















