// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Fk
import Fk.Pages
import Fk.RoomElement
import Qt5Compat.GraphicalEffects

GraphicsBox {
  id: root

  property var card_names: []
  property var all_names: []
  property string prompt : ""
  property string result : ""


  title.text: Util.processPrompt(prompt)
  width: 600
  property int mainHeight : Math.min(300, 40 * (Math.ceil(all_names.length / 7)))
  height: mainHeight + 40


  Flickable {
    id : cardArea
    height : mainHeight
    anchors.top: title.bottom
    anchors.topMargin: 5
    anchors.left : parent.left
    anchors.leftMargin: 5
    anchors.horizontalCenter: parent.horizontalCenter
    contentHeight: gridLayout.implicitHeight
    clip: true

    GridLayout {
      id: gridLayout
      columns: 7
      width: parent.width
      clip: true

      Repeater {
        id: cardRepeater
        model: all_names

        delegate: Rectangle {
          id: cardItem
          width : 80
          height : 35
          clip : true
          border.color: "#FEF7D6"
          border.width: 2
          radius : 2

          enabled : root.card_names.includes(modelData)

          layer.effect: DropShadow {
            color: "#845422"
            radius: 5
            samples: 25
            spread: 0.7
          }

          Rectangle {
            id : cardImageArea
            anchors.centerIn: parent
            width : parent.width - 4
            height : parent.height - 4
            color: "transparent"
            clip : true
            Image {
              id: cardImage
              anchors.fill: parent
              anchors.centerIn: parent
              anchors.topMargin: -20
              source: SkinBank.getCardPicture(modelData)
              fillMode: Image.PreserveAspectCrop
              scale : 1.05
            }
          }

          Rectangle {
            id : cardGrey
            anchors.fill: parent
            anchors.centerIn: parent
            visible: !this.enabled
            color: Qt.rgba(0, 0, 0, 0.7)
            opacity: 0.7
            z: 2
          }

          GlowText {
            id : cardName
            text: luatr(modelData)
            visible : true
            font.family: fontLi2.name
            font.pixelSize: 15
            font.bold: true
            color : "#111111"
            glow.color: "#EEEEEE"
            glow.spread: 0.6
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.rightMargin: 1
          }


          MouseArea {
            anchors.fill: parent
            anchors.centerIn: parent
            onClicked: {
              result = modelData;
              root.close();
            }


          }

        }
      }

    }
  }

}
