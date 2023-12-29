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
--可通过给角色添加前缀为"QMLMARKSHOWN_"的mark来使得此mark公开（TODO:需不需要做成list以实现仅对部分角色公开？）
--额外的，后继带$前缀为武将牌堆，后继带&前缀为卡牌牌堆，此时公开逻辑变为是否能点击展示这些卡牌
Fk:addQmlMark{
  name = "private",
  qml_path = function(name, value, p)
    if Self == p or p:getMark("QMLMARKSHOWN_"..name) ~= 0 then
      if string.startsWith(name, "@[private]$") then
        return "packages/utility/qml/ViewPile"
      elseif string.startsWith(name, "@[private]&") then
        return "packages/utility/qml/ViewGeneralPile"
      end
    end
    return ""
  end,
  how_to_show = function(name, value, p)
    if type(value) == "table" then
      if string.startsWith(name, "@[private]$") or string.startsWith(name, "@[private]&") then
        return #value
      end
      if Self == p or p:getMark("QMLMARKSHOWN_"..name) ~= 0 then
        return table.concat(table.map(value, function(_value)
          return Fk:translate(_value)
        end), " ")
      end
    elseif Self == p or p:getMark("QMLMARKSHOWN_"..name) ~= 0 then
      return Fk:translate(value)
    end
    return " "
  end,
}
