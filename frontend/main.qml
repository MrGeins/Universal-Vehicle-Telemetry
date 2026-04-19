import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCharts
import QtPositioning
import QtLocation

ApplicationWindow {
    visible: true
    minimumWidth: 900
    minimumHeight: 600
    width: 1200
    height: 800
    title: "Universal Telemetry Dashboard"
    color: "#080c14"

    // ── Palette ────────────────────────────────────────────────────────────────
    readonly property color clrBg:        "#080c14"
    readonly property color clrSurface:   "#0d1421"
    readonly property color clrCard:      "#111928"
    readonly property color clrBorder:    "#1e2d45"
    readonly property color clrAccent:    "#00d4ff"
    readonly property color clrGreen:     "#00e676"
    readonly property color clrRed:       "#ff3d5a"
    readonly property color clrAmber:     "#ffab00"
    readonly property color clrTextPrim:  "#e8f0fe"
    readonly property color clrTextSec:   "#5c7a9e"
    readonly property color clrTextMuted: "#2a4060"

    // ── State ──────────────────────────────────────────────────────────────────
    property double  currentSpeed:    0
    property double  currentTemp:     0
    property int     currentBattery:  0
    property double  currentAltitude: 0
    property bool    isWarning:       false
    property string  vehicleId:       "IDLE"
    property var     currentCoords:   QtPositioning.coordinate(45.4642, 9.1900)
    property bool    missionActive:   false
    property int     dataPoints:      0

    // ── Data fetch ─────────────────────────────────────────────────────────────
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: fetchData()
    }

    function fetchData() {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                updateUI(JSON.parse(xhr.responseText))
            }
        }
        xhr.open("GET", "http://localhost:8080/api/latest", true)
        xhr.send()
    }

    function updateUI(data) {
        if (data.vehicle_id === "WAITING..." || data.gps.latitude === undefined) return
        vehicleId       = data.vehicle_id
        currentSpeed    = data.physics.speed_kmh
        currentTemp     = data.system_status.engine_temp
        currentBattery  = data.system_status.battery_level
        currentAltitude = data.gps.altitude
        isWarning       = data.system_status.warning_light
        missionActive   = true
        dataPoints++

        currentCoords = QtPositioning.coordinate(data.gps.latitude, data.gps.longitude)
        mapView.center = currentCoords
        routeLine.addCoordinate(currentCoords)

        var ts = new Date().getTime()
        lineSeries.append(ts, currentSpeed)
        if (lineSeries.count > 120) lineSeries.remove(0)
        chartView.axisX().min = new Date(ts - 12000)
        chartView.axisX().max = new Date(ts)
    }

    // ── Animated warning pulse ─────────────────────────────────────────────────
    SequentialAnimation {
        id: warnAnim; loops: Animation.Infinite; running: isWarning
        NumberAnimation { target: warnDot; property: "opacity"; to: 0.1; duration: 500 }
        NumberAnimation { target: warnDot; property: "opacity"; to: 1.0; duration: 500 }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  ROOT LAYOUT
    // ══════════════════════════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Header bar ────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 52
            color: clrSurface

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width; height: 1
                color: clrBorder
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 20; rightMargin: 20 }

                // Logo / title
                Row {
                    spacing: 10
                    Rectangle {
                        width: 8; height: 32; radius: 2
                        color: clrAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            text: "TELEMETRY"
                            color: clrAccent
                            font { pixelSize: 13; letterSpacing: 4; weight: Font.Bold }
                        }
                        Text {
                            text: "UNIVERSAL DASHBOARD"
                            color: clrTextSec
                            font { pixelSize: 8; letterSpacing: 2 }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Live indicator
                Row {
                    spacing: 8
                    visible: missionActive
                    Rectangle {
                        id: liveDot
                        width: 8; height: 8; radius: 4
                        color: clrGreen
                        anchors.verticalCenter: parent.verticalCenter
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.2; duration: 700 }
                            NumberAnimation { to: 1.0; duration: 700 }
                        }
                    }
                    Text {
                        text: "LIVE"
                        color: clrGreen
                        font { pixelSize: 11; letterSpacing: 3; weight: Font.Bold }
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Rectangle { width: 1; height: 28; color: clrBorder; visible: missionActive }

                // Vehicle ID badge
                Rectangle {
                    height: 28; width: lblVehicle.width + 24
                    color: Qt.rgba(0, 0.83, 1, 0.08)
                    border { color: clrAccent; width: 1 }
                    radius: 4
                    Text {
                        id: lblVehicle
                        anchors.centerIn: parent
                        text: vehicleId
                        color: clrAccent
                        font { pixelSize: 12; letterSpacing: 2; weight: Font.Bold }
                    }
                }

                // Data point counter
                Text {
                    text: dataPoints + " pts"
                    color: clrTextSec
                    font { pixelSize: 11; letterSpacing: 1 }
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // ── Main area ─────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ── LEFT SIDEBAR ──────────────────────────────────────────────────
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 320
                color: clrSurface

                Rectangle {
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                    width: 1; color: clrBorder
                }

                ColumnLayout {
                    anchors { fill: parent; margins: 16 }
                    spacing: 12

                    // ── Mission Control ───────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        height: missionControlCol.implicitHeight + 24
                        color: clrCard
                        border { color: clrBorder; width: 1 }
                        radius: 8

                        Column {
                            id: missionControlCol
                            anchors { fill: parent; margins: 12 }
                            spacing: 10

                            // Section label
                            Row {
                                spacing: 6
                                Rectangle { width: 3; height: 12; radius: 1.5; color: clrAccent; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: "MISSION CONTROL"
                                    color: clrTextSec
                                    font { pixelSize: 9; letterSpacing: 2.5; weight: Font.Medium }
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            // Inputs row
                            RowLayout {
                                width: parent.width
                                spacing: 8

                                TextField {
                                    id: inputOrigin
                                    Layout.fillWidth: true
                                    placeholderText: "Partenza"
                                    font.pixelSize: 12
                                    color: clrTextPrim
                                    placeholderTextColor: clrTextSec
                                    leftPadding: 10
                                    background: Rectangle {
                                        color: "#0a1525"; radius: 5
                                        border { color: inputOrigin.activeFocus ? clrAccent : clrBorder; width: 1 }
                                    }
                                }
                                TextField {
                                    id: inputDest
                                    Layout.fillWidth: true
                                    placeholderText: "Destinazione"
                                    font.pixelSize: 12
                                    color: clrTextPrim
                                    placeholderTextColor: clrTextSec
                                    leftPadding: 10
                                    background: Rectangle {
                                        color: "#0a1525"; radius: 5
                                        border { color: inputDest.activeFocus ? clrAccent : clrBorder; width: 1 }
                                    }
                                }
                            }

                            // Vehicle selector + button
                            RowLayout {
                                width: parent.width
                                spacing: 8

                                ComboBox {
                                    id: comboVehicle
                                    Layout.preferredWidth: 110
                                    model: ListModel {
                                        ListElement { text: "🚗  Auto";   value: "CAR"   }
                                        ListElement { text: "🚆  Treno";  value: "TRAIN" }
                                        ListElement { text: "✈️  Aereo"; value: "PLANE" }
                                    }
                                    textRole: "text"; valueRole: "value"
                                    font.pixelSize: 12
                                    contentItem: Text {
                                        leftPadding: 10
                                        text: comboVehicle.displayText
                                        color: clrTextPrim
                                        font: comboVehicle.font
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        color: "#0a1525"; radius: 5
                                        border { color: comboVehicle.pressed ? clrAccent : clrBorder; width: 1 }
                                    }
                                }

                                Button {
                                    Layout.fillWidth: true
                                    text: missionActive ? "⏹  STOP" : "▶  START MISSION"
                                    font { pixelSize: 11; weight: Font.Bold; letterSpacing: 1 }
                                    onClicked: {
                                        var xhr = new XMLHttpRequest()
                                        xhr.open("POST", "http://localhost:8080/api/mission", true)
                                        xhr.setRequestHeader("Content-Type", "application/json")
                                        xhr.send(JSON.stringify({
                                            origin: inputOrigin.text,
                                            destination: inputDest.text,
                                            vehicle_type: comboVehicle.currentValue
                                        }))
                                        routeLine.path = []
                                        if (missionActive) { missionActive = false; vehicleId = "IDLE" }
                                    }
                                    background: Rectangle {
                                        radius: 5
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0; color: missionActive ? Qt.rgba(1,0.24,0.35,0.9) : Qt.rgba(0,0.83,1,0.15) }
                                            GradientStop { position: 1; color: missionActive ? Qt.rgba(1,0.24,0.35,0.6) : Qt.rgba(0,0.83,1,0.08) }
                                        }
                                        border { color: missionActive ? clrRed : clrAccent; width: 1 }
                                    }
                                    contentItem: Text {
                                        text: parent.text
                                        color: missionActive ? clrRed : clrAccent
                                        font: parent.font
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                            }
                        }
                    }

                    // ── Speed ─────────────────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        height: 100
                        color: clrCard
                        border { color: clrBorder; width: 1 }
                        radius: 8

                        // Accent left bar
                        Rectangle {
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: 3; radius: 1.5
                            color: currentSpeed > 800 ? clrAccent : clrGreen
                            Behavior on color { ColorAnimation { duration: 400 } }
                        }

                        Column {
                            anchors { fill: parent; leftMargin: 20; topMargin: 14 }
                            spacing: 4
                            Text {
                                text: "VELOCITY"
                                color: clrTextSec
                                font { pixelSize: 9; letterSpacing: 2.5 }
                            }
                            Row {
                                spacing: 6
                                Text {
                                    text: Math.round(currentSpeed).toString()
                                    color: currentSpeed > 800 ? clrAccent : clrGreen
                                    font { pixelSize: 46; weight: Font.Thin }
                                    Behavior on color { ColorAnimation { duration: 300 } }
                                }
                                Text {
                                    text: "km/h"
                                    color: clrTextSec
                                    font.pixelSize: 14
                                    anchors.bottom: parent.bottom
                                    bottomPadding: 10
                                }
                            }
                        }
                    }

                    // ── Metric grid ───────────────────────────────────────────
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 10
                        columnSpacing: 10

                        // Engine Temp
                        MetricCard {
                            Layout.fillWidth: true
                            label: "ENGINE TEMP"
                            value: currentTemp.toFixed(1) + " °C"
                            icon: "🌡"
                            accent: currentTemp > 100 ? clrRed : clrAccent
                            warning: currentTemp > 100
                        }

                        // Altitude
                        MetricCard {
                            Layout.fillWidth: true
                            label: "ALTITUDE"
                            value: Math.round(currentAltitude) + " m"
                            icon: "▲"
                            accent: clrAccent
                            warning: false
                        }

                        // Battery (full-width with bar)
                        BatteryCard {
                            Layout.columnSpan: 2
                            Layout.fillWidth: true
                            batteryLevel: currentBattery
                        }

                        // Status
                        Rectangle {
                            Layout.columnSpan: 2
                            Layout.fillWidth: true
                            height: 42
                            color: clrCard
                            border { color: isWarning ? clrRed : clrBorder; width: 1 }
                            radius: 8
                            Behavior on border.color { ColorAnimation { duration: 300 } }

                            RowLayout {
                                anchors { fill: parent; margins: 12 }
                                spacing: 8

                                Row {
                                    spacing: 6
                                    Rectangle { width: 3; height: 12; radius: 1.5; color: clrTextSec; anchors.verticalCenter: parent.verticalCenter }
                                    Text {
                                        text: "SYSTEM STATUS"
                                        color: clrTextSec
                                        font { pixelSize: 9; letterSpacing: 2 }
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                Item { Layout.fillWidth: true }

                                Rectangle {
                                    id: warnDot
                                    width: 8; height: 8; radius: 4
                                    color: isWarning ? clrRed : clrGreen
                                    anchors.verticalCenter: parent.verticalCenter
                                    Behavior on color { ColorAnimation { duration: 300 } }
                                }
                                Text {
                                    text: isWarning ? "WARNING" : "NOMINAL"
                                    color: isWarning ? clrRed : clrGreen
                                    font { pixelSize: 13; weight: Font.Bold; letterSpacing: 1 }
                                    anchors.verticalCenter: parent.verticalCenter
                                    Behavior on color { ColorAnimation { duration: 300 } }
                                }
                            }
                        }
                    }

                    // ── Speed chart ───────────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: clrCard
                        border { color: clrBorder; width: 1 }
                        radius: 8
                        clip: true

                        Column {
                            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 10; leftMargin: 12 }
                            spacing: 2
                            Row {
                                spacing: 6
                                Rectangle { width: 3; height: 12; radius: 1.5; color: clrGreen; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: "SPEED HISTORY"
                                    color: clrTextSec
                                    font { pixelSize: 9; letterSpacing: 2.5 }
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        ChartView {
                            id: chartView
                            anchors { fill: parent; topMargin: 28 }
                            theme: ChartView.ChartThemeDark
                            backgroundColor: "transparent"
                            plotAreaColor: "transparent"
                            legend.visible: false
                            antialiasing: true
                            margins { top: 4; bottom: 4; left: 4; right: 4 }

                            DateTimeAxis {
                                id: axisX
                                format: "mm:ss"
                                gridLineColor: clrBorder
                                labelsColor: clrTextSec
                                labelsFont { pixelSize: 9 }
                                lineVisible: false
                                tickCount: 5
                            }
                            ValueAxis {
                                id: axisY
                                min: 0; max: 1000
                                gridLineColor: clrBorder
                                labelsColor: clrTextSec
                                labelsFont { pixelSize: 9 }
                                lineVisible: false
                                tickCount: 5
                            }
                            AreaSeries {
                                axisX: axisX; axisY: axisY
                                borderColor: clrGreen
                                borderWidth: 2
                                color: Qt.rgba(0, 0.90, 0.46, 0.15)
                                upperSeries: LineSeries {
                                    id: lineSeries
                                }
                            }
                        }
                    }
                }
            }

            // ── MAP PANEL ─────────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Plugin {
                    id: mapPlugin
                    name: "osm"
                    PluginParameter { name: "osm.mapping.providersrepository.disabled"; value: "true" }
                }

                Map {
                    id: mapView
                    anchors.fill: parent
                    plugin: mapPlugin
                    center: currentCoords
                    zoomLevel: 13
                    copyrightsVisible: false

                    // Animated route
                    MapPolyline {
                        id: routeLine
                        line.width: 3
                        line.color: Qt.rgba(0, 0.83, 1, 0.85)
                    }

                    // Vehicle dot
                    MapQuickItem {
                        coordinate: currentCoords
                        anchorPoint.x: 12; anchorPoint.y: 12
                        sourceItem: Item {
                            width: 24; height: 24
                            // Pulse ring
                            Rectangle {
                                anchors.centerIn: parent
                                width: 24; height: 24; radius: 12
                                color: "transparent"
                                border { color: clrAccent; width: 1.5 }
                                SequentialAnimation on scale {
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 1.8; duration: 900; easing.type: Easing.OutQuad }
                                    NumberAnimation { to: 1.0; duration: 100 }
                                }
                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.0; duration: 900 }
                                    NumberAnimation { to: 1.0; duration: 100 }
                                }
                            }
                            // Core dot
                            Rectangle {
                                anchors.centerIn: parent
                                width: 12; height: 12; radius: 6
                                color: clrAccent
                                border { color: "white"; width: 2 }
                            }
                        }
                    }
                }

                // Map overlays (coordinates HUD)
                Rectangle {
                    anchors { bottom: parent.bottom; left: parent.left; margins: 12 }
                    height: 28
                    width: coordText.width + 20
                    color: Qt.rgba(0.05, 0.08, 0.13, 0.85)
                    border { color: clrBorder; width: 1 }
                    radius: 5
                    Text {
                        id: coordText
                        anchors.centerIn: parent
                        text: currentCoords.latitude.toFixed(5) + "  " + currentCoords.longitude.toFixed(5)
                        color: clrTextSec
                        font { pixelSize: 10; family: "monospace"; letterSpacing: 1 }
                    }
                }

                // Zoom controls
                Column {
                    anchors { right: parent.right; top: parent.top; margins: 12 }
                    spacing: 1
                    ZoomButton { text: "+"; onClicked: mapView.zoomLevel = Math.min(mapView.zoomLevel + 1, 19) }
                    ZoomButton { text: "−"; onClicked: mapView.zoomLevel = Math.max(mapView.zoomLevel - 1, 3) }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    //  COMPONENTS
    // ══════════════════════════════════════════════════════════════════════════
    component MetricCard: Rectangle {
        property string label: ""
        property string value: ""
        property string icon: ""
        property color  accent: "#00d4ff"
        property bool   warning: false

        height: 62
        color: clrCard
        border { color: warning ? clrRed : clrBorder; width: 1 }
        radius: 8
        Behavior on border.color { ColorAnimation { duration: 300 } }

        Column {
            anchors { fill: parent; margins: 10 }
            spacing: 3
            Row {
                spacing: 5
                Text { text: icon; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: label
                    color: clrTextSec
                    font { pixelSize: 9; letterSpacing: 2 }
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            Text {
                text: value
                color: warning ? clrRed : clrTextPrim
                font { pixelSize: 18; weight: Font.Light }
                Behavior on color { ColorAnimation { duration: 300 } }
            }
        }
    }

    component BatteryCard: Rectangle {
        property int batteryLevel: 0

        height: 60
        color: clrCard
        border { color: batteryLevel < 20 ? clrRed : clrBorder; width: 1 }
        radius: 8
        Behavior on border.color { ColorAnimation { duration: 300 } }

        Column {
            anchors { fill: parent; margins: 10 }
            spacing: 6
            Row {
                spacing: 5
                Rectangle { width: 3; height: 10; radius: 1.5; color: batteryLevel < 20 ? clrRed : clrGreen; anchors.verticalCenter: parent.verticalCenter; Behavior on color { ColorAnimation {} } }
                Text {
                    text: "BATTERY"
                    color: clrTextSec
                    font { pixelSize: 9; letterSpacing: 2.5 }
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item { width: 1 }
                Text {
                    text: batteryLevel + "%"
                    color: batteryLevel < 20 ? clrRed : clrGreen
                    font { pixelSize: 13; weight: Font.Bold }
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on color { ColorAnimation {} }
                }
            }
            // Battery bar
            Rectangle {
                width: parent.width - 1; height: 6; radius: 3
                color: Qt.rgba(1,1,1,0.05)
                Rectangle {
                    width: parent.width * (batteryLevel / 100)
                    height: parent.height; radius: parent.radius
                    color: batteryLevel < 20 ? clrRed : batteryLevel < 50 ? clrAmber : clrGreen
                    Behavior on width  { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    Behavior on color  { ColorAnimation { duration: 400 } }
                }
            }
        }
    }

    component ZoomButton: Rectangle {
        property string text: ""
        signal clicked()

        width: 32; height: 32; radius: 4
        color: zoomMa.pressed ? Qt.rgba(0, 0.83, 1, 0.2) : Qt.rgba(0.05, 0.08, 0.13, 0.85)
        border { color: clrBorder; width: 1 }
        Text {
            anchors.centerIn: parent
            text: parent.text
            color: clrAccent
            font { pixelSize: 18; weight: Font.Light }
        }
        MouseArea {
            id: zoomMa
            anchors.fill: parent
            onClicked: parent.clicked()
        }
    }
}
