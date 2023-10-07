// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
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

  title.text: Backend.translate(prompt !== "" ? processPrompt(prompt) : "$ChooseCard")
  // TODO: Adjust the UI design in case there are more than 7 cards
  width: 40 + Math.min(8.5, Math.max(4, cards.length)) * 100
  height: 260

  Component {
    id: cardDelegate
    GeneralCardItem {
      name: modelData
      autoBack: false
      selectable: !disable_cards.includes(name)
      onSelectedChanged: {
        if (ok_options.length == 0) return;

        if (selected) {
          origY = origY - 20;
          root.selectedItem.push(name);
        } else {
          origY = origY + 20;
          root.selectedItem.splice(root.selectedItem.indexOf(name), 1);
        }
        origX = x;
        goBack(true);

        root.updateCardSelectable();
      }
    }
  }

  function processPrompt(prompt) {
    const data = prompt.split(":");
    let raw = Backend.translate(data[0]);
    const src = parseInt(data[1]);
    const dest = parseInt(data[2]);
    if (raw.match("%src")) raw = raw.replace(/%src/g, Backend.translate(getPhoto(src).general));
    if (raw.match("%dest")) raw = raw.replace(/%dest/g, Backend.translate(getPhoto(dest).general));
    if (raw.match("%arg2")) raw = raw.replace(/%arg2/g, Backend.translate(data[4]));
    if (raw.match("%arg")) raw = raw.replace(/%arg/g, Backend.translate(data[3]));
    return raw;
  }

  Rectangle {
    id: right
    anchors.fill: parent
    anchors.topMargin: 40
    anchors.leftMargin: 15
    anchors.rightMargin: 15
    anchors.bottomMargin: 50

    color: "#88EEEEEE"
    radius: 10

    Flickable {
      id: flickableContainer
      ScrollBar.horizontal: ScrollBar {}

      flickableDirection: Flickable.HorizontalFlick
      anchors.fill: parent
      anchors.topMargin: 0
      anchors.leftMargin: 5
      anchors.rightMargin: 5
      anchors.bottomMargin: 10

      contentWidth: cardsList.width
      contentHeight: cardsList.height
      clip: true

      ColumnLayout {
        id: cardsList
        anchors.top: parent.top
        anchors.topMargin: 25

        Row {
          spacing: 5
          Repeater {
            id: to_select
            model: cards
            delegate: cardDelegate
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
      spacing: 8

      Repeater {
        id: ok_buttons
        model: ok_options

        MetroButton {
          Layout.fillWidth: true
          text: processPrompt(modelData)
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
          text: processPrompt(modelData)
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

