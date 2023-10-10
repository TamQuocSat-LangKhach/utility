// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import Fk.Pages
import Fk.RoomElement

GraphicsBox {
  id: root

  property var selected: []
  property var active_skills: []
  property int min
  property int max
  property string prompt

  title.text: Backend.translate(prompt !== "" ? prompt : "$Choice")
  width: 40 + Math.min(8, Math.max(4, active_skills.length)) * 88
  height: 230

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

  ColumnLayout {
    anchors.fill: parent
    anchors.topMargin: 40
    anchors.leftMargin: 20
    anchors.rightMargin: 20
    anchors.bottomMargin: 20

    GridLayout {
      Layout.alignment: Qt.AlignHCenter
      columns: 8
      Repeater {
        id: skill_buttons
        model: active_skills

        SkillButton {
          skill: Backend.translate(modelData)
          type: "active"
          enabled: true
          orig: modelData

          onPressedChanged: {
            if (pressed) {
              root.selected.push(orig);
            } else {
              root.selected.splice(root.selected.indexOf(orig), 1);
            }

            root.updateSelectable();
          }
        }
      }
    }

    Row {
      Layout.alignment: Qt.AlignHCenter
      spacing: 8

      MetroButton {
        Layout.alignment: Qt.AlignHCenter
        id: buttonConfirm
        text: Backend.translate("OK")
        width: 120
        height: 35

        onClicked: {
          close();
          roomScene.state = "notactive";
          ClientInstance.replyToServer("", JSON.stringify(root.selected));
        }
      }

      MetroButton {
        id: detailBtn
        width: 80
        height: 35
        text: Backend.translate("Show General Detail")
        onClicked: roomScene.startCheat("../../packages/utility/qml/SkillDetail", { skills: root.selected.length > 0 ? root.selected : root.active_skills});
      }
    }
  }

  function updateSelectable() {
    buttonConfirm.enabled = (selected.length <= max && selected.length >= min);
  }

  function loadData(data) {
    const d = data;
    active_skills = d[0];
    min = d[1];
    max = d[2];
    prompt = d[3];
  
    updateSelectable()
  }
}

