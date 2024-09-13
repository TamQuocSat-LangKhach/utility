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
  property var selectedItem: []
  property int min
  property int max
  property string prompt : ""
  property bool cancelable : false
  property bool repeatable : false

  title.text: Util.processPrompt(prompt)
  width: 600
  height: Math.min(300, 40 * (Math.ceil(all_names.length / 7))) + 100


  Flickable {
    id : cardArea
    height : parent.height - 100
    anchors.top: title.bottom
    anchors.topMargin: 0
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
          property int num : 0

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
            id : numText
            text: repeatable ? num.toString() : "√"
            visible : num !== 0
            font.family: fontLibian.name
            font.pixelSize: 30
            font.bold: true
            color: "#FE2222"
            glow.color: "#FEF7D6"
            glow.spread: 0.5
            anchors.centerIn: parent
          }

          GlowText {
            id : cardName
            text: luatr(modelData)
            visible : num == 0
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
            enabled : cardItem.enabled
            onClicked: {
              if (repeatable) {
                if (selectedItem.length < max) {
                  selectedItem.push(modelData);
                  cardItem.num ++;
                }
              } else {
                let index = selectedItem.indexOf(modelData);
                if (index !== -1) {
                  selectedItem.splice(index, 1);
                  cardItem.num = 0;
                } else if (selectedItem.length < max) {
                  selectedItem.push(modelData);
                  cardItem.num = 1;
                }
              }
              updateSelectable()
            }

          }

        }
      }

    }
  }


  Item {
    id: buttonArea
    anchors.fill: parent
    anchors.bottomMargin: 10
    height: 40

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      spacing: 30

      MetroButton {
        id: buttonConfirm
        Layout.fillWidth: true
        text: luatr("OK")
        enabled: selectedItem.length >= min

        onClicked: {
          close();
          roomScene.state = "notactive";
          ClientInstance.replyToServer("", JSON.stringify(selectedItem));
        }
      }

      MetroButton {
        id: buttonClear
        Layout.fillWidth: true
        enabled: selectedItem.length
        text: luatr("Clear All")
        onClicked: {
          this.enabled = false;
          buttonConfirm.enabled = (min == 0);
          selectedItem = [];
          for (let i = 0; i < cardRepeater.count; ++i) {
            cardRepeater.itemAt(i).num = 0;
          }
        }
      }


      MetroButton {
        id: buttonCancel
        Layout.fillWidth: true
        text: luatr("Cancel")
        enabled: cancelable

        onClicked: {
          root.close();
          roomScene.state = "notactive";
          ClientInstance.replyToServer("", "");
        }
      }
    }
  }

  function updateSelectable() {
    buttonClear.enabled = selectedItem.length;
    buttonConfirm.enabled = selectedItem.length >= min;
  }

  function loadData(data) {
    card_names = data[0];
    all_names = data[4];
    
    min = data[1];
    max = data[2];
    prompt = data[3];
    cancelable = data[5];
    repeatable = data[6];
  }
}
