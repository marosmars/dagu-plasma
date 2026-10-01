import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "../code/format.js" as Fmt

// One DAG: status icon, name (+ schedule), and prominent next / last run times.
PlasmaComponents3.ItemDelegate {
    id: row

    property var dag: ({})
    property date now: new Date()
    property bool stale: false
    property bool compact: false
    property bool showSchedule: true
    property bool showDuration: true
    property bool use24h: true

    signal activated(string fileName)

    readonly property bool failed: dag.kind === "failed" || dag.kind === "warning"
    readonly property string nextText: dag.suspended ? i18n("suspended")
        : dag.kind === "running" ? i18n("running…")
        : dag.next ? Fmt.whenLabel(dag.next, now, use24h)
        : "—"
    readonly property string duration: showDuration ? Fmt.durationLabel(dag.startedAt, dag.finishedAt) : ""
    readonly property string lastText: dag.startedAt
        ? Fmt.whenLabel(new Date(dag.startedAt), now, use24h) + (duration ? " · " + duration : "")
        : i18n("never")
    readonly property color lastColor: failed ? Kirigami.Theme.negativeTextColor
        : dag.kind === "ok" ? Kirigami.Theme.positiveTextColor
        : Kirigami.Theme.textColor
    readonly property color nextColor: dag.suspended ? Kirigami.Theme.neutralTextColor
        : dag.kind === "running" ? Kirigami.Theme.highlightColor
        : Kirigami.Theme.textColor

    opacity: stale ? 0.5 : 1
    onClicked: activated(dag.fileName)

    QQC2.ToolTip.visible: hovered
    QQC2.ToolTip.text: [
        dag.name + " — " + dag.status,
        dag.schedules && dag.schedules.length ? i18n("Schedule: %1", dag.schedules.join(", ")) : "",
        dag.error || "",
    ].filter(s => s !== "").join("\n")

    contentItem: RowLayout {
        spacing: Kirigami.Units.largeSpacing

        // Status: a plain coloured dot (an icon here read as a checkbox); warning icon for DAG errors
        Item {
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                anchors.centerIn: parent
                visible: !row.dag.error
                width: Math.round(parent.width * 0.75)
                height: width
                radius: width / 2
                color: {
                    switch (row.dag.kind) {
                    case "ok": return Kirigami.Theme.positiveTextColor;
                    case "failed": return Kirigami.Theme.negativeTextColor;
                    case "warning": return Kirigami.Theme.neutralTextColor;
                    case "running": return Kirigami.Theme.highlightColor;
                    default: return Kirigami.Theme.disabledTextColor;
                    }
                }
                SequentialAnimation on opacity {
                    running: row.dag.kind === "running"
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) parent.opacity = 1
                    NumberAnimation { to: 0.3; duration: 700 }
                    NumberAnimation { to: 1; duration: 700 }
                }
            }
            Kirigami.Icon {
                anchors.fill: parent
                visible: !!row.dag.error
                source: "data-warning"
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: row.dag.name
                font.bold: true
                elide: Text.ElideRight
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: !row.compact && row.showSchedule
                text: row.dag.schedules && row.dag.schedules.length ? row.dag.schedules.join("  ") : i18n("no schedule")
                font.family: "monospace"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.6
                elide: Text.ElideRight
            }
        }

        // Next / last as two fixed-width columns: small caption over a large value
        Repeater {
            model: [
                { caption: i18n("NEXT"), value: row.nextText, color: row.nextColor, size: 1.25 },
                { caption: i18n("LAST"), value: row.lastText, color: row.lastColor, size: 1.0 },
            ]
            delegate: ColumnLayout {
                required property var modelData
                Layout.alignment: Qt.AlignVCenter
                // Fixed width (min = max) so NEXT / LAST line up across rows
                readonly property real columnWidth: Kirigami.Units.gridUnit * (row.use24h ? 6.5 : 8)
                Layout.preferredWidth: columnWidth
                Layout.minimumWidth: columnWidth
                Layout.maximumWidth: columnWidth
                Layout.leftMargin: Kirigami.Units.largeSpacing
                spacing: 0
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    visible: !row.compact
                    text: modelData.caption
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.letterSpacing: 1
                    opacity: 0.55
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: modelData.value
                    color: modelData.color
                    font.bold: true
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * modelData.size
                    elide: Text.ElideRight
                }
            }
        }
    }
}
