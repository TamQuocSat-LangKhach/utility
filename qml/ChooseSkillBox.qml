// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import Fk.Pages
import Fk.RoomElement
import Fk.Common

GraphicsBox {
  id: root

  property var selected: []
  // property var active_skills: []
  property int min
  property int max
  property string prompt
  property var generals

  title.text: Backend.translate(prompt !== "" ? processPrompt(prompt) : "$Choice")
  width: 40 + Math.min(5, active_skills.count) * (88 + (generals ? 36 : 0))
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
      columns: 5
      Repeater {
        id: skill_buttons
        model: ListModel {
          id: active_skills
        }

        RowLayout {
          Avatar {
            id: avatarPic
            visible: _general != ""
            Layout.preferredHeight: 36
            Layout.preferredWidth: 36
            general: _general
          }

          SkillButton {
            skill: Backend.translate(name)
            type: "active"
            enabled: true
            orig: name

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
        onClicked: {
          let _skills = [];
          if (root.selected.length > 0) {
            _skills = root.selected;
          } else {
            for (let i = 0; i < active_skills.count; i++){
              _skills.push(active_skills.get(i).name);
            }
          }
          roomScene.startCheat("../../packages/utility/qml/SkillDetail", { skills: _skills});
        }
      }
    }
  }

  function updateSelectable() {
    buttonConfirm.enabled = (selected.length <= max && selected.length >= min);
  }

  function loadData(data) {
    let skills, i;
    [skills, min, max, prompt, generals] = data;

    if (!generals) {
      for (i = 0; i < skills.length; i++) {
        active_skills.append({
          name: skills[i],
          _general: "",
        });
      }
    } else {
      for (i = 0; i < skills.length; i++) {
        active_skills.append({
          name: skills[i],
          _general: generals[i] ?? "",
        });
      }
    }

    updateSelectable()
  }
}

