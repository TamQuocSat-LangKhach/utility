// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Fk
import Fk.Pages
import Fk.RoomElement

GraphicsBox {
  id: root

  property var selectedGeneral: []
  property var generals: ["liubei"]
  property var skillList: []
  property var shownSkills: []
  property var selectedSkill: []

  property string titleName: ""

  title.text: luatr(titleName)
  width: 585
  height: 210 + Math.min(270, Math.ceil(generals.length / 7) * 110)

  Rectangle {
    id : generalArea
    width : parent.width 
    height : parent.height - 180
    anchors.top: title.bottom
    anchors.topMargin: 10
    anchors.horizontalCenter: parent.horizontalCenter
    clip : true
    border.color: "#FEF7D6"
    border.width: 3
    radius : 4
    color: "transparent"

    GridView {
      id : generalCard
      
      anchors.centerIn: parent
      width : parent.width - 10
      height : parent.height - 14
      cellWidth: 80
      cellHeight: 110
      Layout.alignment: Qt.AlignHCenter
      clip: true

      model: generals

      delegate: GeneralCardItem {
        id: cardItem
        autoBack: false
        name: modelData
        scale : 0.8

        Image {
          id : generalChosen
          visible: (selectedGeneral.length && selectedGeneral[0] == modelData)
          source: SkinBank.CARD_DIR + "chosen"
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 8
          scale: 1.2
        }

        onSelectedChanged: {
          if (selectedGeneral.length && selectedGeneral[0] !== modelData) {
            selectedSkill = [];
          }
          selectedGeneral = [modelData];
          shownSkills = skillList[index];
          updateSelectable();
        }

        onRightClicked: {
          roomScene.startCheat("GeneralDetail", { generals: [modelData] });
        }

      }
    }
  }

  Rectangle {
    id : skillArea
    width : parent.width
    height : 90
    anchors.top: generalArea.bottom
    anchors.topMargin: 5
    anchors.horizontalCenter: parent.horizontalCenter
    clip : true
    border.color: "#FEF7D6"
    border.width: 3
    radius : 4
    color: "transparent"

    GridView {
      id : skillShown
      width : parent.width - 10
      height : parent.height - 8
      anchors.centerIn: parent
      cellWidth: 80
      cellHeight: 40
      Layout.alignment: Qt.AlignHCenter
      clip: true

      model: shownSkills

      delegate: SkillButton {
        id : skill_buttons
        skill: luatr(modelData)
        type: "active"
        enabled: true
        orig: modelData
        scale: 0.85

        onPressedChanged: {
          if (pressed) {
            if (selectedSkill.length) {
              root.selectedSkill[0].pressed = false;
            }
            selectedSkill = [this];
          } else {
            selectedSkill = [];
            this.pressed = false;
          }
          updateSelectable();
        }

        /* default choose first skill
        Component.onCompleted: {
          if (selectedSkill.length == 0 && shownSkills.length == 1) {
            this.pressed = true;
            selectedSkill = [this];
            updateSelectable();
          }
        }
        */

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
        Layout.fillWidth: true
        text: luatr("OK")
        id: buttonConfirm
        enabled: selectedGeneral.length && selectedSkill.length

        onClicked: {
          close();
          roomScene.state = "notactive";
          ClientInstance.replyToServer("", JSON.stringify([root.selectedGeneral[0], root.selectedSkill[0].orig]));
        }
      }

      MetroButton {
        id: buttonDetail
        enabled: selectedGeneral.length
        text: luatr("Show General Detail")
        onClicked: {
          if (selectedSkill.length) {
            roomScene.startCheat("../../packages/utility/qml/SkillDetail", { skills: [root.selectedSkill[0].orig] });
          } else {
            roomScene.startCheat("GeneralDetail", { generals: selectedGeneral });
          }
        }
      }


      MetroButton {
        Layout.fillWidth: true
        text: luatr("Cancel")
        enabled: true

        onClicked: {
          root.close();
          roomScene.state = "notactive";
          ClientInstance.replyToServer("", "");
        }
      }
    }
  }

  function updateSelectable() {
    buttonConfirm.enabled = selectedSkill.length;
    buttonDetail.enabled = selectedGeneral.length;
  }

  function loadData(data) {
    generals = data[0];
    skillList = data[1];
    titleName = data[2];
  }
}
