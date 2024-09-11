// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Fk
import Fk.Pages
import Fk.RoomElement

GraphicsBox {
  id: root

  property var selectedItem: []
  property var ok_options: []
  property var cards: []
  property var disable_cards: []
  property string prompt
  property int min
  property int max
  property var cancel_options: []

  property bool isSearching: false
  
  width: 40 + Math.min(7, Math.max(4, cards.length)) * 100
  height: 120 + Math.min(2.2, Math.ceil(cards.length / 7)) * 140

  Component {
    id: cardDelegate
    GeneralCardItem {
      name: modelData
      selectable: !disable_cards.includes(name)
      onSelectedChanged: {
        if (ok_options.length == 0) return;

        if (selected) {
          root.selectedItem.push(name);
          chosenInBox = true;
        } else {
          root.selectedItem.splice(root.selectedItem.indexOf(name), 1);
          chosenInBox = false;
        }

        root.updateCardSelectable();
      }

      onRightClicked: {
        roomScene.startCheat("GeneralDetail", { generals: [modelData] });
      }
    }
  }

  Rectangle {
    id: cardArea
    anchors.fill: parent
    anchors.topMargin: 60
    anchors.leftMargin: 15
    anchors.rightMargin: 15
    anchors.bottomMargin: 55

    color: "#88EEEEEE"
    radius: 10

    Flickable {
      id: generalContainer

      anchors.fill: parent
      anchors.topMargin: 5
      anchors.leftMargin: 5
      anchors.rightMargin: 5
      anchors.bottomMargin: 5

      contentHeight: gridLayout.implicitHeight
      clip: true

      GridLayout {
        id: gridLayout
        columns: 7
        width: parent.width
        clip: true

        Repeater {
          id: to_select
          model: cards
          delegate: cardDelegate
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
      spacing: 8

      Repeater {
        id: ok_buttons
        model: ok_options

        MetroButton {
          Layout.fillWidth: true
          text: Util.processPrompt(modelData)
          enabled: false

          onClicked: {
            close();
            roomScene.state = "notactive";
            const reply = JSON.stringify(
              {
                cards: root.selectedItem,
                choice: modelData,
              }
            );
            ClientInstance.replyToServer("", reply);
          }
        }
      }

      Repeater {
        id: cancel_buttons
        model: cancel_options

        MetroButton {
          Layout.fillWidth: true
          text: Util.processPrompt(modelData)
          enabled: true

          onClicked: {
            close();
            roomScene.state = "notactive";
            const reply = JSON.stringify(
              {
                cards: [],
                choice: modelData,
              }
            );
            ClientInstance.replyToServer("", reply);
          }
        }
      }
    }
  }


  Item {
    id : titleArea
    anchors.top: parent.top
    anchors.topMargin: 5
    anchors.horizontalCenter: parent.horizontalCenter

    height: 40
    width: parent.width - 30


    RowLayout {
      anchors.fill: parent

      Text {
        font.pixelSize: 20
        color: "#E4D5A0"
        text: Util.processPrompt(prompt)
        horizontalAlignment: Text.AlignHCenter
        Layout.fillWidth: true
      }
          
      TextField {
        visible: cards.length > 21
        enabled: !isSearching
        id: word
        placeholderText: isSearching ? "" : "Search..."
        clip: true
        verticalAlignment: Qt.AlignVCenter
        background: Rectangle {
          implicitHeight: 20
          implicitWidth: 120
          color: "#88EEEEEE"
          radius: 5
        }
      }

      ToolButton {
        visible: cards.length > 21
        text: isSearching ? luatr("Back") : luatr("Search")
        enabled: (word.text !== "" || isSearching)
        onClicked: {
          if (isSearching) {
            for (var i = 0; i < to_select.count; i++) {
              to_select.itemAt(i).visible = true;
            }
            isSearching = false;
            generalContainer.contentWidth = Math.min(7, cards.length) * 100;
          } else {
            var findNum = 0;
            for (var i = 0; i < to_select.count; i++) {
              const item = to_select.itemAt(i);
              if (luatr(item.name).indexOf(word.text) === -1) {
                item.visible = false;
              } else {
                findNum++;
              }
              generalContainer.contentWidth = Math.min(7, findNum) * 100;
            }
            word.text = "";
            isSearching = true;
          }
        }
        background: Rectangle {
          implicitHeight: 35
          implicitWidth: 40
          color: "#88EEEEEE"
          radius: 5
        }
      }
      
    }
  }

  function updateCardSelectable() {
    if (selectedItem.length > max) {
      const item = to_select.itemAt(cards.indexOf(selectedItem[0]));
      item.selected = false;
    } else {
      let item;
      for (let i = 0; i < ok_buttons.count; i++) {
        item = ok_buttons.itemAt(i);
        item.enabled = (selectedItem.length >= min && selectedItem.length <= max)
      }
    }
  }

  function loadData(data) {
    const d = data;
    cards = d[0];
    ok_options = d[1];
    prompt = d[2] ?? "";
    cancel_options = d[3] ?? []
    min = d[4] ?? 1
    max = d[5] ?? 1
    disable_cards = d[6] ?? []
  }
}

