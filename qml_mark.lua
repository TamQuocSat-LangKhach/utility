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
