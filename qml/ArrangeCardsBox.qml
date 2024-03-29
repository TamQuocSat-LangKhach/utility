// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import Fk.Pages
import Fk.RoomElement

GraphicsBox {
  id: root
  property string prompt
  property var cards: []
  property var result: []
  property var pilecards: []
  property var areaNames: []
  property int padding: 25

  title.text: Backend.translate(prompt !== "" ? prompt : "Please arrange cards")
  width: body.width + padding * 2
  height: title.height + body.height + padding * 2

  ColumnLayout {
    id: body
    x: padding
    y: parent.height - padding - height
    spacing: 10

    Repeater {
      id: areaRepeater
      model: 2

      Row {
        spacing: 5

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          color: "#6B5D42"
          width: 20
          height: 100
          radius: 5

          Text {
            anchors.fill: parent
            width: 20
            height: 100
            text: areaNames.length > index ? qsTr(areaNames[index]) : ""
            color: "white"
            font.family: fontLibian.name
            font.pixelSize: 18
            style: Text.Outline
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
          }
        }

        Rectangle {
          id: cardsArea
          color: "#1D1E19"
          width: 800
          height: 130

        }
        property alias cardsArea: cardsArea
      }
    }
      

    MetroButton {
      Layout.alignment: Qt.AlignHCenter
      id: buttonConfirm
      text: Backend.translate("OK")
      width: 120
      height: 35

      onClicked: {
        close();
        roomScene.state = "notactive";
        const reply = JSON.stringify(getResult());
        ClientInstance.replyToServer("", reply);
      }
    }
  }

  Repeater {
    id: cardItem
    model: cards

    CardItem {
      x: index
      y: -1
      cid: modelData.cid
      name: modelData.name
      suit: modelData.suit
      number: modelData.number
      draggable: true
      onReleased: updateCardReleased(this);
    }
  }

  function updateCardReleased(card) {
    let _card = result[0][0];
    if (Math.abs(card.y - _card.y) >= card.height) return;
    let i;
    for (i = 0; i < result[0].length; i++) {
      _card = result[0][i]
      if (Math.abs(card.x - _card.x) <= 50) {
        result[1][result[1].indexOf(card)] = _card;
        result[0][i] = card;
        break;
      }
    }
    arrangeCards();
  }

  function arrangeCards() {
    let i, j;
    let card, box, pos, pile;
    let spacing
    for (j = 0; j < 2; j++){
      pile = areaRepeater.itemAt(j);
      if (pile.y === 0){
        pile.y = j * 150
      }
      spacing = (result[j].length > 8) ? (700 / (result[j].length - 1)) : 100
      for (i = 0; i < result[j].length; i++) {
        box = pile.cardsArea;
        pos = mapFromItem(pile, box.x, box.y);
        card = result[j][i];
        card.draggable = (j > 0)
        card.origX = pos.x + i * spacing;
        card.origY = pos.y;
        card.z = i + 1;
        card.initialZ = i + 1;
        card.maxZ = result[j].length;
        card.goBack(true);
      }
    }
  }

  function initializeCards() {
    result = new Array(2);
    let i;
    for (i = 0; i < result.length; i++){
      result[i] = [];
    }

    let card;
    for (i = 0; i < cardItem.count; i++) {
      card = cardItem.itemAt(i);
      if (i < pilecards.length) {
        result[0].push(card);
      } else {
        result[1].push(card);
      }
    }

    arrangeCards();
  }

  function getResult() {
    const ret = [];
    result.forEach(t => {
      const t2 = [];
      t.forEach(v => t2.push(v.cid));
      ret.push(t2);
    });
    return ret;
  }
  
  function loadData(data) {
    const d = data;

    pilecards = d[1];

    let all_cards = d[1].map(cid => {
      return JSON.parse(Backend.callLuaFunction("GetCardData", [cid]));
    });

    d[3].forEach(cid => all_cards.push(JSON.parse(Backend.callLuaFunction("GetCardData", [cid]))));

    cards = all_cards;

    areaNames = [Backend.translate(d[0]), Backend.translate(d[2])];

    prompt = d[4] ?? "";

    initializeCards();
  }
}
