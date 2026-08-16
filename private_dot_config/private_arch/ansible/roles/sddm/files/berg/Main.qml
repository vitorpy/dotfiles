import QtQuick 2.15
import SddmComponents 2.0 as SDDM

Rectangle {
    id: root

    readonly property color surface: "#000000"
    readonly property color card: Qt.rgba(0, 0, 0, 0.72)
    readonly property color cardHigh: "#282828"
    readonly property color foreground: "#d7d7d7"
    readonly property color muted: "#acacae"
    readonly property color outline: "#646667"
    readonly property color primary: "#f49f31"
    readonly property color error: "#d54135"
    readonly property var unitedGeometry: screenModel.geometry(-1)
    readonly property var primaryGeometry: screenModel.geometry(screenModel.primary)
    readonly property string backgroundUrl: config.stringValue("background")
    readonly property string metadataUrl: config.stringValue("metadata")
    readonly property int selectedSession: sessionPicker.index
    property date now: new Date()
    property var artwork: ({
    })
    property bool authenticating: false
    property string statusMessage: ""
    property bool statusIsError: false
    property string pendingPowerAction: ""

    function metadataText(key) {
        const value = artwork[key];
        return typeof value === "string" ? value.trim() : "";
    }

    function artworkByline() {
        const parts = [];
        const creator = metadataText("creator");
        const date = metadataText("date");
        if (creator)
            parts.push(creator);

        if (date)
            parts.push(date);

        return parts.join(" · ");
    }

    function artworkSource() {
        const provider = metadataText("provider_name") || metadataText("provider");
        const attribution = metadataText("attribution");
        if (provider && attribution && provider !== attribution)
            return `${provider} · ${attribution}`;

        return provider || attribution;
    }

    function loadArtworkMetadata() {
        if (!metadataUrl)
            return ;

        const request = new XMLHttpRequest();
        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE)
                return ;

            if (request.status !== 0 && request.status !== 200)
                return ;

            try {
                const parsed = JSON.parse(request.responseText);
                if (parsed && typeof parsed === "object" && typeof parsed.title === "string")
                    artwork = parsed;

            } catch (error) {
                artwork = ({
                });
            }
        };
        request.open("GET", metadataUrl);
        request.send();
    }

    function submitLogin() {
        if (authenticating)
            return ;

        const username = usernameField.text.trim();
        if (!username) {
            statusMessage = "Enter a username.";
            statusIsError = true;
            usernameField.forceActiveFocus();
            return ;
        }
        if (!passwordField.text) {
            statusMessage = "Enter your password.";
            statusIsError = true;
            passwordField.forceActiveFocus();
            return ;
        }
        authenticating = true;
        statusIsError = false;
        statusMessage = "Authenticating…";
        sddm.login(username, passwordField.text, selectedSession);
    }

    function requestPower(action) {
        pendingPowerAction = action;
        confirmation.forceActiveFocus();
    }

    function confirmPower() {
        const action = pendingPowerAction;
        pendingPowerAction = "";
        if (action === "restart")
            sddm.reboot();
        else if (action === "poweroff")
            sddm.powerOff();
    }

    width: unitedGeometry.width
    height: unitedGeometry.height
    color: surface
    Component.onCompleted: {
        loadArtworkMetadata();
        if (usernameField.text.length === 0)
            usernameField.forceActiveFocus();
        else
            passwordField.forceActiveFocus();
    }

    Connections {
        function onLoginSucceeded() {
            authenticating = true;
            statusIsError = false;
            statusMessage = "Starting Hyprland…";
        }

        function onLoginFailed() {
            authenticating = false;
            statusIsError = true;
            statusMessage = "Authentication failed. Try again.";
            passwordField.text = "";
            passwordField.forceActiveFocus();
        }

        function onInformationMessage(message) {
            authenticating = false;
            statusIsError = true;
            statusMessage = message;
        }

        target: sddm
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    Repeater {
        model: screenModel

        Item {
            x: geometry.x
            y: geometry.y
            width: geometry.width
            height: geometry.height

            Rectangle {
                anchors.fill: parent
                color: root.surface
            }

            Image {
                anchors.fill: parent
                source: root.backgroundUrl
                asynchronous: true
                cache: false
                fillMode: Image.PreserveAspectCrop
                visible: status === Image.Ready
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.2)
            }

        }

    }

    Item {
        id: primaryScreen

        x: primaryGeometry.x
        y: primaryGeometry.y
        width: primaryGeometry.width
        height: primaryGeometry.height

        Rectangle {
            id: clockCard

            width: Math.min(544, parent.width - 48)
            height: 176
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 24
            anchors.rightMargin: 24
            radius: 15
            color: root.card

            Column {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 4

                Text {
                    width: parent.width
                    text: Qt.formatDateTime(root.now, "HH:mm")
                    color: root.foreground
                    font.family: "Noto Sans"
                    font.pixelSize: 72
                    font.weight: Font.Light
                    horizontalAlignment: Text.AlignRight
                }

                Text {
                    width: parent.width
                    text: Qt.formatDateTime(root.now, "dddd, dd MMMM yyyy")
                    color: root.foreground
                    font.family: "Noto Sans"
                    font.pixelSize: 22
                    horizontalAlignment: Text.AlignRight
                }

            }

        }

        Rectangle {
            id: loginCard

            width: Math.min(496, parent.width - 48)
            height: 344
            anchors.centerIn: parent
            radius: 15
            color: root.card
            border.width: passwordField.activeFocus ? 2 : 1
            border.color: root.statusIsError ? root.error : (passwordField.activeFocus ? root.primary : root.outline)

            Column {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 14

                Text {
                    text: "Welcome back"
                    color: root.foreground
                    font.family: "Noto Sans"
                    font.pixelSize: 25
                    font.weight: Font.DemiBold
                }

                Text {
                    text: sddm.hostName
                    color: root.muted
                    font.family: "Noto Sans"
                    font.pixelSize: 14
                }

                Rectangle {
                    width: parent.width
                    height: 48
                    radius: 12
                    color: root.cardHigh
                    border.width: usernameField.activeFocus ? 2 : 1
                    border.color: usernameField.activeFocus ? root.primary : root.outline

                    TextInput {
                        id: usernameField

                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        color: root.foreground
                        selectionColor: root.primary
                        selectedTextColor: root.surface
                        font.family: "Noto Sans"
                        font.pixelSize: 16
                        verticalAlignment: TextInput.AlignVCenter
                        text: userModel.lastUser
                        enabled: !root.authenticating
                        selectByMouse: true
                        KeyNavigation.tab: passwordField
                        Keys.onReturnPressed: passwordField.forceActiveFocus()
                        Keys.onEnterPressed: passwordField.forceActiveFocus()
                    }

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        verticalAlignment: Text.AlignVCenter
                        visible: usernameField.text.length === 0
                        text: "Username"
                        color: root.muted
                        font.family: "Noto Sans"
                        font.pixelSize: 16
                    }

                }

                Rectangle {
                    width: parent.width
                    height: 52
                    radius: 12
                    color: root.cardHigh
                    border.width: passwordField.activeFocus ? 2 : 1
                    border.color: root.statusIsError ? root.error : (passwordField.activeFocus ? root.primary : root.outline)

                    TextInput {
                        id: passwordField

                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: keyboard.capsLock ? 74 : 16
                        color: root.foreground
                        selectionColor: root.primary
                        selectedTextColor: root.surface
                        font.family: "Noto Sans"
                        font.pixelSize: 17
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        passwordCharacter: "●"
                        enabled: !root.authenticating
                        selectByMouse: true
                        KeyNavigation.backtab: usernameField
                        KeyNavigation.tab: loginButton
                        Keys.onReturnPressed: root.submitLogin()
                        Keys.onEnterPressed: root.submitLogin()
                    }

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        verticalAlignment: Text.AlignVCenter
                        visible: passwordField.text.length === 0
                        text: "Password"
                        color: root.muted
                        font.family: "Noto Sans"
                        font.pixelSize: 16
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        visible: keyboard.capsLock
                        text: "CAPS"
                        color: "#FEE334"
                        font.family: "Noto Sans"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }

                }

                Row {
                    width: parent.width
                    height: 42
                    spacing: 12

                    SDDM.ComboBox {
                        id: sessionPicker

                        width: parent.width - layoutHint.width - parent.spacing
                        height: parent.height
                        model: sessionModel
                        index: sessionModel.lastIndex
                        color: root.cardHigh
                        borderColor: root.outline
                        focusColor: root.primary
                        hoverColor: root.primary
                        menuColor: root.cardHigh
                        textColor: root.foreground
                        borderWidth: activeFocus ? 2 : 1
                        arrowIcon: "chevron-down.svg"
                        arrowColor: root.cardHigh
                        font.family: "Noto Sans"
                        font.pixelSize: 14
                        KeyNavigation.backtab: passwordField
                        KeyNavigation.tab: loginButton
                    }

                    Rectangle {
                        id: layoutHint

                        width: 146
                        height: parent.height
                        radius: 12
                        color: root.cardHigh
                        border.width: 1
                        border.color: root.outline

                        Text {
                            anchors.centerIn: parent
                            text: "PL / US · Alt+Shift"
                            color: root.muted
                            font.family: "Noto Sans"
                            font.pixelSize: 12
                        }

                    }

                }

                Row {
                    width: parent.width
                    height: 42
                    spacing: 12

                    Text {
                        width: parent.width - loginButton.width - parent.spacing
                        height: parent.height
                        text: root.statusMessage
                        color: root.statusIsError ? root.error : root.muted
                        font.family: "Noto Sans"
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    BergButton {
                        id: loginButton

                        width: 132
                        height: parent.height
                        text: root.authenticating ? "Please wait…" : "Log in"
                        filled: true
                        enabled: !root.authenticating
                        KeyNavigation.backtab: sessionPicker
                        KeyNavigation.tab: usernameField
                        onClicked: root.submitLogin()
                    }

                }

            }

        }

        Rectangle {
            width: Math.min(544, parent.width - 48)
            height: artworkColumn.implicitHeight + 48
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: 24
            anchors.bottomMargin: 24
            visible: root.metadataText("title").length > 0
            radius: 15
            color: root.card

            Column {
                id: artworkColumn

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                spacing: 5

                Text {
                    width: parent.width
                    text: root.metadataText("title")
                    color: root.foreground
                    font.family: "Noto Sans"
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: text.length > 0
                    text: root.artworkByline()
                    color: root.foreground
                    font.family: "Noto Sans"
                    font.pixelSize: 14
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: text.length > 0
                    text: root.artworkSource()
                    color: root.muted
                    font.family: "Noto Sans"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }

            }

        }

        Row {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 24
            anchors.bottomMargin: 24
            spacing: 10

            BergButton {
                visible: sddm.canSuspend
                text: "Suspend"
                onClicked: sddm.suspend()
            }

            BergButton {
                text: "Restart"
                onClicked: root.requestPower("restart")
            }

            BergButton {
                text: "Power off"
                danger: true
                onClicked: root.requestPower("poweroff")
            }

        }

        Item {
            id: confirmation

            anchors.fill: parent
            visible: root.pendingPowerAction.length > 0
            focus: visible
            z: 100
            Keys.onEscapePressed: {
                root.pendingPowerAction = "";
                passwordField.forceActiveFocus();
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.62)
            }

            MouseArea {
                anchors.fill: parent
            }

            Rectangle {
                width: Math.min(420, parent.width - 48)
                height: 190
                anchors.centerIn: parent
                radius: 15
                color: root.cardHigh
                border.width: 1
                border.color: root.pendingPowerAction === "poweroff" ? root.error : root.primary

                Column {
                    anchors.fill: parent
                    anchors.margins: 28
                    spacing: 22

                    Text {
                        width: parent.width
                        text: root.pendingPowerAction === "poweroff" ? "Power off this computer?" : "Restart this computer?"
                        color: root.foreground
                        font.family: "Noto Sans"
                        font.pixelSize: 21
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        width: parent.width
                        text: "Any unsaved work in other sessions may be lost."
                        color: root.muted
                        font.family: "Noto Sans"
                        font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 12

                        BergButton {
                            text: "Cancel"
                            onClicked: {
                                root.pendingPowerAction = "";
                                passwordField.forceActiveFocus();
                            }
                        }

                        BergButton {
                            text: root.pendingPowerAction === "poweroff" ? "Power off" : "Restart"
                            danger: root.pendingPowerAction === "poweroff"
                            filled: true
                            onClicked: root.confirmPower()
                        }

                    }

                }

            }

        }

    }

}
