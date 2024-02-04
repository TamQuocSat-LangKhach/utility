-- 在脸上显示花色（如老宝烈弓）
-- 传入值：suit数组（不是suit string）
Fk:addQmlMark{
  name = "suits",
  qml_path = "",
  how_to_show = function(_, value)
    if type(value) ~= "table" then return " " end
    return table.concat(table.map(value, function(suit)
      return Fk:translate(Card.getSuitString({ suit = suit }, true))
    end), " ")
  end,
}

--仅自己可见的mark
--额外的，后继带$前缀为武将牌堆，后继带&前缀为卡牌牌堆，此时公开逻辑变为是否能点击展示这些卡牌
Fk:addQmlMark{
  name = "private",
  qml_path = function(name, value, p)
    if (value.players == nil and Self == p) or (value.players and table.contains(value.players, p.id)) then
      if string.startsWith(name, "@[private]$") then
        return "packages/utility/qml/ViewPile"
      elseif string.startsWith(name, "@[private]&") then
        return "packages/utility/qml/ViewGeneralPile"
      end
    end
    return ""
  end,
  how_to_show = function(name, value, p)
    if string.startsWith(name, "@[private]$") or string.startsWith(name, "@[private]&") then
      return tostring(#value.value)
    elseif (value.players == nil and Self == p) or (value.players and table.contains(value.players, p.id)) then
      return table.concat(table.map(value.value, function(_value)
        return Fk:translate(_value)
      end), " ")
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
