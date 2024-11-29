// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import Fk.RoomElement

ColumnLayout {
  id: root
  anchors.fill: parent
  property var extra_data: ({ name: "", data: {} })
  signal finish()

  BigGlowText {
    Layout.fillWidth: true
    Layout.preferredHeight: childrenRect.height

    text: luatr(extra_data.name)
  }

  GridView {
    cellWidth: 130
    cellHeight: 170
    Layout.preferredWidth: root.width - root.width % 97
    Layout.fillHeight: true
    Layout.alignment: Qt.AlignHCenter
    clip: true

    model: extra_data.data.map(playerId => {
      const player = leval(
        `(function()
          local player = ClientInstance:getPlayerById(${playerId})
          return {
            id = player.id,
            general = player.general,
            deputyGeneral = player.deputyGeneral,
            screenName = player.player:getScreenName(),
            kingdom = player.kingdom,
            seat = player.seat,
            role = 'hidden',
          }
        end)()`
      );
      return player;
    });

    delegate: Photo {
      scale: 0.65
      playerid: modelData.id
      general: modelData.general
      deputyGeneral: modelData.deputyGeneral
      role: modelData.role
      state: "candidate"
      screenName: modelData.screenName
      kingdom: modelData.kingdom
      seatNumber: modelData.seat
      selectable: true

      Component.onCompleted: {
        this.visibleChildren[12].visible = false;
      }
    }
      
  }
}
