// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Fk
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

  title.text: prompt === "" ? luatr("$Choice") : Util.processPrompt(prompt)
  width: Math.max(40 + Math.min(5, active_skills.count) * (88 + (generals ? 36 : 0)), 248)
  height: Math.max(60 + Math.min(32, active_skills.count) * 11, 230)

  Flickable {
    ScrollBar.vertical: ScrollBar {}
    flickableDirection: Flickable.VerticalFlick
    

    anchors.fill: parent
    anchors.topMargin: 40
    anchors.leftMargin: 20
    anchors.rightMargin: 20
    anchors.bottomMargin: 50

    contentWidth: skillsList.width
    contentHeight: skillsList.height
    clip: true

    GridLayout {
      id: skillsList
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
            skill: luatr(name)
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
  }

  Row {
    Layout.alignment: Qt.AlignHCenter
    spacing: 8
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 10

    MetroButton {
      Layout.alignment: Qt.AlignHCenter
      id: buttonConfirm
      text: luatr("OK")
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
      text: luatr("Show General Detail")
      onClicked: {
        let _skills = [];
        if (root.selected.length > 0) {
          _skills = root.selected;
        } else {
          for (let i = 0; i < active_skills.count; i++){
            _skills.push(active_skills.get(i).name);
          }
        }
        roomScene.startCheat("../../packages/utility/qml/SkillDetail", { skills: _skills });
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

