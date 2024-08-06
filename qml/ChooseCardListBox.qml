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

  property var listNames: []
  property var listCards: []
  property var selectedItem: []
  property int min
  property int max
  property string prompt : ""
  property bool allowEmpty : false
  property bool cancelable : true

  title.text: Util.processPrompt(prompt)
  width: 600
  height: Math.min(370, 160 * (Math.ceil(listNames.length / 2))) + 90

  Flickable {
    id : cardArea
    height : parent.height - 90
    anchors.top: title.bottom
    anchors.topMargin: 10
    anchors.left : parent.left
    anchors.leftMargin: 5
    anchors.horizontalCenter: parent.horizontalCenter
    contentHeight: gridLayout.implicitHeight
    ScrollBar.horizontal: ScrollBar {}
    flickableDirection: Flickable.VerticalFlick
    clip: true

    GridLayout {
      id: gridLayout
      columns: 2
      width: parent.width
      clip: true

      Repeater {
        id: cardAreaRepeater
        model: listCards

        delegate: Rectangle {
          id: listArea
          width : 280
          height : 150
          clip : true
          border.color: "#FEF7D6"
          border.width: 3
          radius : 3
          color: "#88EEEEEE"

          property string listName : listNames[index]
          property bool chosen : selectedItem.includes(listName)
          property int cardNum : modelData.length

          RowLayout {
            id : cardArea
            width : parent.width - 20
            height : parent.height - 20
            anchors.centerIn: parent
            spacing: (cardNum < 4) ? -28 :  (this.width - 100) / (cardNum - 1) - 100
            clip : true

            Repeater {
              id: cardRepeater
              model: modelData

              CardItem {
                id: cardItem
                x: 20
                y: 220
                cid: modelData.cid
                name: modelData.name
                suit: modelData.suit
                number: modelData.number
                draggable: true
              }
            }
          }

          MouseArea {
            anchors.fill: parent
            onClicked: {
              if (chosen) {
                let index = selectedItem.indexOf(listName);
                if (index !== -1) {
                  chosen = false;
                  root.selectedItem.splice(index, 1);
                }
              } else {
                if (selectedItem.length < max && (cardNum || allowEmpty)) {
                  selectedItem.push(listName);
                  chosen = true;
                }
              }
              updateSelectable()
            }
          }

          Rectangle {
            id : nameArea
            anchors.bottom: parent.bottom
            width : parent.width
            height : parent.height * 0.25
            color: Qt.rgba(0, 0, 0, 0.7)
            opacity: 0.7

            GlowText {
              id : nameText
              text: Util.processPrompt(listName) + " (" + cardNum.toString() + ")"
              font.family: fontLibian.name
              font.pixelSize: 27
              font.bold: true
              color: "#FEF7D6"
              glow.color: "#845422"
              glow.spread: 0.5
              anchors.centerIn: parent
            }

            Image {
              id : generalChosen
              visible: chosen
              source: SkinBank.CARD_DIR + "chosen"
              anchors.bottom: parent.bottom
              anchors.right: parent.right
              anchors.bottomMargin : 5
              anchors.rightMargin : 5
              scale : 0.95
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
          for (let i = 0; i < cardAreaRepeater.count; ++i) {
            cardAreaRepeater.itemAt(i).chosen = false;
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
    listNames = data[0];
    //listCards = data[1];

    listCards = data[1].map(t => {
      return t.map(cid => {
        return lcall("GetCardData", cid);
      });
    });
    
    min = data[2];
    max = data[3];
    prompt = data[4];
    allowEmpty = data[5];
    cancelable = data[6];
  }
}
