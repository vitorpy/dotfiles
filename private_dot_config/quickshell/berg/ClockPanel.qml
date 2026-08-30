import QtQuick
import Quickshell

PanelWindow {
    id: root

    required property var theme
    required property var clockState

    readonly property string screenName: screen ? screen.name : ""
    readonly property var displayedMonth: new Date(
        clockState.now.getFullYear(),
        clockState.now.getMonth() + monthOffset,
        1
    )
    readonly property int firstWeekday: (displayedMonth.getDay() + 6) % 7
    property int monthOffset: 0

    visible: clockState.panelOpen
        && clockState.panelScreenName === screenName
    color: "transparent"
    implicitWidth: 620
    implicitHeight: 548
    aboveWindows: true
    focusable: false
    exclusiveZone: 0

    anchors {
        top: true
        left: true
    }

    margins {
        top: 69
        left: Math.max(16, Math.round(((screen ? screen.width : implicitWidth) - implicitWidth) / 2))
    }

    function dateForCell(index: int): var {
        return new Date(
            displayedMonth.getFullYear(),
            displayedMonth.getMonth(),
            index - firstWeekday + 1
        );
    }

    function sameDate(left: var, right: var): bool {
        return left.getFullYear() === right.getFullYear()
            && left.getMonth() === right.getMonth()
            && left.getDate() === right.getDate();
    }

    function timezoneLabel(value: string): string {
        if (!value)
            return "Local time";
        const segments = value.split("/");
        return segments[segments.length - 1].replace(/_/g, " ");
    }

    function nextHourLabel(): string {
        if (!clockState.weather || !clockState.weather.next_hour)
            return "Next hour";
        const value = clockState.weather.next_hour.time || "";
        return /T[0-9]{2}:[0-9]{2}$/.test(value)
            ? value.split("T")[1]
            : "Next hour";
    }

    function artworkByline(): string {
        if (!clockState.artwork)
            return "";
        return [clockState.artwork.creator, clockState.artwork.date]
            .filter(value => typeof value === "string" && value.length > 0)
            .join(" — ");
    }

    function artworkCredit(): string {
        if (!clockState.artwork)
            return "";
        const artwork = clockState.artwork;
        const parts = [];
        if (typeof artwork.provider_name === "string" && artwork.provider_name)
            parts.push(artwork.provider_name);
        if (typeof artwork.attribution === "string" && artwork.attribution
                && artwork.attribution !== artwork.provider_name)
            parts.push(artwork.attribution);
        if (typeof artwork.rights === "string" && artwork.rights)
            parts.push(artwork.rights);
        return parts.join(" · ");
    }

    onVisibleChanged: {
        if (visible)
            monthOffset = 0;
    }

    Rectangle {
        anchors.fill: parent
        color: root.theme.surfaceContainerHigh
        border.color: root.theme.outlineVariant
        border.width: 1
        radius: 14

        Rectangle {
            id: accent

            anchors {
                left: parent.left
                top: parent.top
                bottom: headerDivider.top
            }
            width: 4
            color: root.theme.primary
            radius: 2
        }

        Item {
            id: header

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 16
            }
            height: 66

            Text {
                id: timeLabel

                anchors {
                    left: parent.left
                    top: parent.top
                }
                text: Qt.formatDateTime(root.clockState.now, "HH:mm")
                color: root.theme.foreground
                font.family: root.theme.textFont
                font.pixelSize: 32
                font.weight: Font.DemiBold
            }

            Text {
                anchors {
                    left: timeLabel.right
                    leftMargin: 14
                    bottom: timeLabel.bottom
                    bottomMargin: 3
                }
                text: Qt.formatDateTime(root.clockState.now, "dddd, d MMMM yyyy")
                color: root.theme.foregroundMuted
                font.family: root.theme.textFont
                font.pixelSize: 14
            }

            Rectangle {
                id: healthBadge

                visible: root.clockState.health !== "ready"
                anchors {
                    right: closeButton.left
                    rightMargin: 10
                    verticalCenter: closeButton.verticalCenter
                }
                width: healthText.implicitWidth + 16
                height: 30
                color: root.theme.error
                radius: 8

                Text {
                    id: healthText

                    anchors.centerIn: parent
                    text: root.clockState.health === "loading" ? "UPDATING" : "STALE"
                    color: root.theme.onErrorColor
                    font.family: root.theme.textFont
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }
            }

            Rectangle {
                id: closeButton

                anchors {
                    right: parent.right
                    top: parent.top
                }
                width: 34
                height: 34
                color: closeMouse.containsMouse ? root.theme.hoverLayer : root.theme.surfaceContainer
                border.color: root.theme.outlineVariant
                border.width: 1
                radius: 9

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: root.theme.foreground
                    font.family: root.theme.textFont
                    font.pixelSize: 19
                }

                MouseArea {
                    id: closeMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.clockState.closePanel()
                }
            }

            Text {
                anchors {
                    left: parent.left
                    bottom: parent.bottom
                }
                text: root.timezoneLabel(root.clockState.currentTimezone)
                color: root.theme.primary
                font.family: root.theme.textFont
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
        }

        Rectangle {
            id: headerDivider

            anchors {
                left: parent.left
                right: parent.right
                top: header.bottom
                topMargin: 16
            }
            height: 1
            color: root.theme.outlineVariant
        }

        Rectangle {
            id: calendarCard

            anchors {
                left: parent.left
                leftMargin: 16
                top: headerDivider.bottom
                topMargin: 14
            }
            width: 360
            height: 300
            color: root.theme.surfaceContainer
            border.color: root.theme.outlineVariant
            border.width: 1
            radius: 12

            Text {
                anchors {
                    left: parent.left
                    leftMargin: 14
                    top: parent.top
                    topMargin: 13
                }
                text: Qt.formatDateTime(root.displayedMonth, "MMMM yyyy")
                color: root.theme.foreground
                font.family: root.theme.textFont
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }

            Row {
                anchors {
                    right: parent.right
                    rightMargin: 10
                    top: parent.top
                    topMargin: 8
                }
                spacing: 5

                Repeater {
                    model: [
                        { "label": "‹", "delta": -1 },
                        { "label": "Today", "delta": 0 },
                        { "label": "›", "delta": 1 }
                    ]

                    Rectangle {
                        required property var modelData

                        width: modelData.delta === 0 ? 58 : 30
                        height: 30
                        color: monthMouse.containsMouse ? root.theme.hoverLayer : "transparent"
                        border.color: root.theme.outlineVariant
                        border.width: 1
                        radius: 8

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: root.theme.foreground
                            font.family: root.theme.textFont
                            font.pixelSize: modelData.delta === 0 ? 11 : 18
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: monthMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (parent.modelData.delta === 0)
                                    root.monthOffset = 0;
                                else
                                    root.monthOffset += parent.modelData.delta;
                            }
                        }
                    }
                }
            }

            Row {
                id: weekdayRow

                anchors {
                    left: parent.left
                    leftMargin: 14
                    right: parent.right
                    rightMargin: 14
                    top: parent.top
                    topMargin: 53
                }
                height: 24

                Repeater {
                    model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

                    Text {
                        required property string modelData

                        width: weekdayRow.width / 7
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: root.theme.foregroundMuted
                        font.family: root.theme.textFont
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
            }

            Grid {
                id: calendarGrid

                anchors {
                    left: parent.left
                    leftMargin: 14
                    right: parent.right
                    rightMargin: 14
                    top: weekdayRow.bottom
                    topMargin: 3
                }
                columns: 7
                rows: 6
                columnSpacing: 4
                rowSpacing: 4

                Repeater {
                    model: 42

                    Rectangle {
                        required property int index

                        readonly property var day: root.dateForCell(index)
                        readonly property bool inMonth: day.getMonth() === root.displayedMonth.getMonth()
                        readonly property bool today: root.sameDate(day, root.clockState.now)

                        width: (calendarGrid.width - calendarGrid.columnSpacing * 6) / 7
                        height: 31
                        color: today ? root.theme.primary : "transparent"
                        border.color: today ? root.theme.primary : "transparent"
                        border.width: 1
                        radius: 8

                        Text {
                            anchors.centerIn: parent
                            text: parent.day.getDate().toString()
                            color: parent.today
                                ? root.theme.onErrorColor
                                : (parent.inMonth ? root.theme.foreground : root.theme.foregroundMuted)
                            opacity: parent.inMonth || parent.today ? 1 : 0.42
                            font.family: root.theme.textFont
                            font.pixelSize: 12
                            font.weight: parent.today ? Font.Bold : Font.Medium
                        }
                    }
                }
            }
        }

        Rectangle {
            id: detailsCard

            anchors {
                left: calendarCard.right
                leftMargin: 12
                right: parent.right
                rightMargin: 16
                top: calendarCard.top
            }
            height: calendarCard.height
            color: root.theme.surfaceContainer
            border.color: root.theme.outlineVariant
            border.width: 1
            radius: 12

            Text {
                anchors {
                    left: parent.left
                    leftMargin: 14
                    top: parent.top
                    topMargin: 13
                }
                text: "TIME ZONES"
                color: root.theme.foregroundMuted
                font.family: root.theme.textFont
                font.pixelSize: 10
                font.weight: Font.Bold
            }

            Text {
                anchors {
                    left: parent.left
                    leftMargin: 14
                    top: parent.top
                    topMargin: 35
                }
                text: `${root.timezoneLabel(root.clockState.currentTimezone)} · ${Qt.formatDateTime(root.clockState.now, "HH:mm")}`
                color: root.theme.foreground
                font.family: root.theme.textFont
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            Text {
                visible: root.clockState.currentTimezone !== root.clockState.warsawTimezone
                    && root.clockState.warsawFull.length > 0
                anchors {
                    left: parent.left
                    leftMargin: 14
                    top: parent.top
                    topMargin: 57
                }
                text: `Warsaw · ${root.clockState.warsawCompact}`
                color: root.theme.primary
                font.family: root.theme.textFont
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    topMargin: 88
                }
                height: 1
                color: root.theme.outlineVariant
            }

            Text {
                anchors {
                    left: parent.left
                    leftMargin: 14
                    top: parent.top
                    topMargin: 103
                }
                text: root.clockState.weather
                    ? `WEATHER · ${root.clockState.weather.location.city.toUpperCase()}`
                    : "WEATHER"
                color: root.theme.foregroundMuted
                font.family: root.theme.textFont
                font.pixelSize: 10
                font.weight: Font.Bold
            }

            Item {
                visible: root.clockState.weather !== null
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    topMargin: 127
                    bottom: parent.bottom
                    margins: 14
                }

                Text {
                    id: temperatureLabel

                    anchors {
                        left: parent.left
                        top: parent.top
                    }
                    text: root.clockState.weather
                        ? `${root.clockState.rounded(root.clockState.weather.current.temperature_c)}°`
                        : ""
                    color: root.theme.foreground
                    font.family: root.theme.textFont
                    font.pixelSize: 30
                    font.weight: Font.DemiBold
                }

                Text {
                    anchors {
                        left: temperatureLabel.right
                        leftMargin: 9
                        right: parent.right
                        verticalCenter: temperatureLabel.verticalCenter
                    }
                    text: root.clockState.weather ? root.clockState.weather.current.condition : ""
                    color: root.theme.foreground
                    elide: Text.ElideRight
                    font.family: root.theme.textFont
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                Text {
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: temperatureLabel.bottom
                        topMargin: 3
                    }
                    text: root.clockState.weather
                        ? `Feels ${root.clockState.rounded(root.clockState.weather.current.apparent_temperature_c)}° · Wind ${root.clockState.rounded(root.clockState.weather.current.wind_speed_kmh)} km/h`
                        : ""
                    color: root.theme.foregroundMuted
                    font.family: root.theme.textFont
                    font.pixelSize: 11
                }

                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        topMargin: 72
                    }
                    height: 1
                    color: root.theme.outlineVariant
                }

                Text {
                    anchors {
                        left: parent.left
                        top: parent.top
                        topMargin: 87
                    }
                    text: root.nextHourLabel()
                    color: root.theme.primary
                    font.family: root.theme.textFont
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                Text {
                    anchors {
                        right: parent.right
                        top: parent.top
                        topMargin: 85
                    }
                    text: root.clockState.weather
                        ? `${root.clockState.rounded(root.clockState.weather.next_hour.temperature_c)}°`
                        : ""
                    color: root.theme.foreground
                    font.family: root.theme.textFont
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }

                Text {
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        topMargin: 111
                    }
                    text: root.clockState.weather
                        ? `${root.clockState.weather.next_hour.condition} · ${root.clockState.rounded(root.clockState.weather.next_hour.precipitation_probability)}% rain`
                        : ""
                    color: root.theme.foregroundMuted
                    elide: Text.ElideRight
                    font.family: root.theme.textFont
                    font.pixelSize: 11
                }
            }

            Text {
                visible: root.clockState.weather === null
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    topMargin: 135
                    margins: 14
                }
                text: "Weather data is unavailable"
                color: root.theme.foregroundMuted
                wrapMode: Text.WordWrap
                font.family: root.theme.textFont
                font.pixelSize: 12
            }
        }

        Rectangle {
            id: artworkCard

            anchors {
                left: parent.left
                leftMargin: 16
                right: parent.right
                rightMargin: 16
                top: calendarCard.bottom
                topMargin: 12
                bottom: parent.bottom
                bottomMargin: 16
            }
            color: root.theme.surfaceContainer
            border.color: root.theme.outlineVariant
            border.width: 1
            radius: 12

            Rectangle {
                anchors {
                    left: parent.left
                    leftMargin: 12
                    top: parent.top
                    topMargin: 14
                    bottom: parent.bottom
                    bottomMargin: 14
                }
                width: 3
                color: root.theme.primary
                radius: 2
            }

            Text {
                anchors {
                    left: parent.left
                    leftMargin: 27
                    top: parent.top
                    topMargin: 13
                }
                text: "CURRENT ARTWORK"
                color: root.theme.foregroundMuted
                font.family: root.theme.textFont
                font.pixelSize: 10
                font.weight: Font.Bold
            }

            Rectangle {
                id: rotateArtworkButton

                anchors {
                    right: parent.right
                    rightMargin: 10
                    top: parent.top
                    topMargin: 9
                }
                width: 30
                height: 30
                color: rotateArtworkMouse.containsMouse
                    ? root.theme.hoverLayer
                    : root.theme.surfaceContainerHigh
                border.color: root.theme.outlineVariant
                border.width: 1
                radius: 8
                opacity: root.clockState.artworkRotating ? 0.6 : 1

                Text {
                    anchors.centerIn: parent
                    text: root.theme.reboot
                    color: root.clockState.artworkRotating
                        ? root.theme.primary
                        : root.theme.foreground
                    font.family: root.theme.symbolFont
                    font.pixelSize: 14
                }

                MouseArea {
                    id: rotateArtworkMouse

                    anchors.fill: parent
                    enabled: !root.clockState.artworkRotating
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.clockState.rotateArtwork()
                }
            }

            Text {
                id: artworkTitle

                anchors {
                    left: parent.left
                    leftMargin: 27
                    right: rotateArtworkButton.left
                    rightMargin: 10
                    top: parent.top
                    topMargin: 33
                }
                text: root.clockState.artwork ? root.clockState.artwork.title : "No artwork metadata available"
                color: root.theme.foreground
                elide: Text.ElideRight
                font.family: root.theme.textFont
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            Text {
                anchors {
                    left: parent.left
                    leftMargin: 27
                    right: parent.right
                    rightMargin: 14
                    top: artworkTitle.bottom
                    topMargin: 5
                }
                text: root.artworkByline()
                visible: text.length > 0
                color: root.theme.foregroundMuted
                elide: Text.ElideRight
                font.family: root.theme.textFont
                font.pixelSize: 11
            }

            Text {
                anchors {
                    left: parent.left
                    leftMargin: 27
                    right: parent.right
                    rightMargin: 14
                    bottom: parent.bottom
                    bottomMargin: 12
                }
                text: root.artworkCredit()
                visible: text.length > 0
                color: root.theme.foregroundMuted
                elide: Text.ElideRight
                font.family: root.theme.textFont
                font.pixelSize: 10
            }
        }

        Text {
            visible: root.clockState.lastError.length > 0
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                bottomMargin: 2
            }
            horizontalAlignment: Text.AlignHCenter
            text: root.clockState.lastError.split("\n")[0]
            color: root.theme.error
            elide: Text.ElideRight
            font.family: root.theme.textFont
            font.pixelSize: 9
        }
    }
}
