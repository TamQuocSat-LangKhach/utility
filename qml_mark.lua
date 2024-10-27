-- 在脸上显示花色（如老宝烈弓）
-- 传入值：suit数组（不是suit string）
Fk:addQmlMark{
  name = "suits",
  qml_path = "",
  how_to_show = function(_, value)
    if type(value) ~= "table" then return " " end
    return table.concat(table.map(value, function(suit)
      return Fk:translate(Card.getSuitString({ suit = suit }, true))
    end), "")
  end,
}
-- 在脸上显示角色武将名（若有副将，改为显示位置）
-- 传入值：角色ID
Fk:addQmlMark{
  name = "chara",
  qml_path = "",
  how_to_show = function(_, value)
    if type(value) == "string" then value = tonumber(value) end --- 实际访问的时候这里会出string
    if not value or type(value) ~= "number" then return " " end
    local player = Fk:currentRoom():getPlayerById(value)
    if (not player) or (not player.general) or (player.general == "") then return " " end
    local ret = player.general
    if player.deputyGeneral and player.deputyGeneral ~= "" then
      ret = "seat#" .. player.seat
    end
    return Fk:translate(ret)
  end,
}
-- 在脸上显示类别
-- 传入值：card type数组（不是card string）
Fk:addQmlMark{
  name = "cardtypes",
  qml_path = "",
  how_to_show = function(_, value)
    if type(value) ~= "table" then return " " end
    local types = {}
    if table.contains(value, 1) then
      table.insert(types, Fk:translate("basic_char"))
    end
    if table.contains(value, 2) then
      table.insert(types, Fk:translate("trick_char"))
    end
    if table.contains(value, 3) then
      table.insert(types, Fk:translate("equip_char"))
    end
    return table.concat(types, " ")
  end,
}

--仅自己可见的mark
--额外的，后继带$前缀为武将牌堆，后继带&前缀为卡牌牌堆，此时公开逻辑变为是否能点击展示这些卡牌
Fk:addQmlMark{
  name = "private",
  qml_path = function(name, value, p)
    if (value.players == nil and Self == p) or (value.players and table.contains(value.players, Self.id)) then
      if string.startsWith(name, "@[private]$") then
        return "packages/utility/qml/ViewPile"
      elseif string.startsWith(name, "@[private]&") then
        return "packages/utility/qml/ViewGeneralPile"
      elseif string.startsWith(name, "@[private]:") then
        return "packages/utility/qml/DetailBox"
      end
    end
    return ""
  end,
  how_to_show = function(name, value, p)
    if type(value) ~= "table" then return " " end
    if string.startsWith(name, "@[private]$") or string.startsWith(name, "@[private]&") or string.startsWith(name, "@[private]:") then
      return tostring(#value.value)
    elseif (value.players == nil and Self == p) or (value.players and table.contains(value.players, Self.id)) then
      return table.concat(table.map(value.value, Util.TranslateMapper), " ")
    end
    return " "
  end,
}

-- 详细描述mark: @[:]xxxx
Fk:addQmlMark{
  name = ":",
  how_to_show = function(name, value)
    if type(value) == "string" then
      return Fk:translate(value)
    elseif type(value) == "table" then
      return tostring(#value)
    end
    return " "
  end,
  qml_path = "packages/utility/qml/DetailBox"
}

--先辅mark
--作为table只有两个参数：
--具体值（value，若为数字，默认为武将id），和是否对其他人可见（visible）
Fk:addQmlMark{
  name = "xianfu",
  qml_path = "",
  how_to_show = function(name, value, p)
    if type(value) ~= "table" then return " " end
    if (value.visible or Self == p) then
      if type(value.value) == "number" then
        local visual = Fk:currentRoom():getPlayerById(value.value)
        if visual then
          local ret = Fk:translate(visual.general)
          -- if visual.deputyGeneral and visual.deputyGeneral ~= "" then
          --   ret = ret .. "/" .. Fk:translate(visual.deputyGeneral)
          -- end
          return ret
        end
      end
      return tostring(value.value)
    end
    return "#hidden"
  end,
}
