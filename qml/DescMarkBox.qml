import QtQuick
import QtQuick.Layouts
import Fk.RoomElement

ColumnLayout {
  id: root
  anchors.fill: parent
  property var extra_data: ({ name: "", data: [] })
  signal finish()

  BigGlowText {
    Layout.fillWidth: true
    Layout.preferredHeight: childrenRect.height + 4

    text: luatr(extra_data.name)
  }

  ListView {
    Layout.fillWidth: true
    Layout.fillHeight: true

    clip: true
    spacing: 20
    TextEdit {
      id: skillDesc

      width: parent.width
      font.pixelSize: 18
      color: "#E4D5A0"
      text: extra_data.name == ""  ? "" : luatr(":" + extra_data.name.slice(7))

      readOnly: true
      selectByKeyboard: true
      selectByMouse: false
      wrapMode: TextEdit.WordWrap
      textFormat: TextEdit.RichText
    }
  }

}

