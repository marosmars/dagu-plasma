import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.notification

import "../code/cron.js" as Cron
import "../code/format.js" as Fmt

PlasmoidItem {
    id: root

    property var dags: []
    property bool reachable: true
    property bool loaded: false
    property date lastOk
    property date now: new Date()

    readonly property var cfg: Plasmoid.configuration
    readonly property string baseUrl: cfg.serverUrl.replace(/\/+$/, "")
    // Visible rows, each with its computed next run, in the configured order
    readonly property var shownDags: Fmt.sortRows(
        Fmt.visibleRows(dags, cfg.hiddenDags).map(d => Object.assign({}, d, {
            next: d.suspended ? null : Cron.nextRunAny(d.schedules, now),
        })),
        cfg.sortBy)
    readonly property string overall: Fmt.overallState(shownDags, reachable)
    readonly property color stateColor: {
        switch (overall) {
        case "down": return Kirigami.Theme.disabledTextColor;
        case "failed": return Kirigami.Theme.negativeTextColor;
        case "running": return Kirigami.Theme.highlightColor;
        default: return Kirigami.Theme.positiveTextColor;
        }
    }

    Plasmoid.icon: "view-calendar-tasks"
    toolTipMainText: i18n("Dagu workflows")
    toolTipSubText: {
        if (!reachable) return i18n("Dagu not reachable at %1", baseUrl);
        var failed = shownDags.filter(d => d.kind === "failed" || d.kind === "warning").length;
        return failed ? i18np("%1 workflow failed", "%1 workflows failed", failed)
                      : i18np("%1 workflow, all OK", "%1 workflows, all OK", shownDags.length);
    }

    // Big enough (desktop, or a resized window) shows the list; panels show the icon.
    switchWidth: Kirigami.Units.gridUnit * 14
    switchHeight: Kirigami.Units.gridUnit * 6

    function refresh() {
        now = new Date();
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try {
                    var rows = Fmt.toRows(JSON.parse(xhr.responseText));
                    if (root.cfg.notifyOnFailure) {
                        Fmt.newFailures(root.loaded ? root.dags : null, Fmt.visibleRows(rows, root.cfg.hiddenDags))
                            .forEach(root.notifyFailure);
                    }
                    root.dags = rows;
                    root.reachable = true;
                    root.loaded = true;
                    root.lastOk = new Date();
                    return;
                } catch (e) {
                    console.warn("dagu widget: bad JSON", e);
                }
            }
            root.reachable = false;
        };
        xhr.open("GET", baseUrl + "/api/v2/dags?perPage=200");
        xhr.send();
    }

    function notifyFailure(dag) {
        console.info("dagu widget: notifying failure of", dag.name);
        var n = failureNotification.createObject(root, {
            title: i18n("Dagu: %1 %2", dag.name, dag.status.replace(/_/g, " ")),
            text: dag.startedAt ? i18n("Run started %1", Fmt.whenLabel(new Date(dag.startedAt), new Date(), cfg.use24h)) : "",
        });
        n.sendEvent();
    }

    Component {
        id: failureNotification
        Notification {
            componentName: "plasma_workspace"
            eventId: "notification"
            iconName: "data-error"
            autoDelete: true
        }
    }

    function openUrl(path) {
        Qt.openUrlExternally(baseUrl + path);
    }

    Timer {
        interval: Math.max(5, root.cfg.refreshSeconds) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    compactRepresentation: MouseArea {
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        Kirigami.Icon {
            id: compactIcon
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
            source: Plasmoid.icon
            active: parent.containsMouse
        }
        Rectangle {
            width: Math.round(compactIcon.width * 0.4)
            height: width
            radius: width / 2
            anchors.right: compactIcon.right
            anchors.bottom: compactIcon.bottom
            color: root.stateColor
            border.color: Kirigami.Theme.backgroundColor
            border.width: 1
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        Layout.preferredHeight: Kirigami.Units.gridUnit * 3
            + list.count * Kirigami.Units.gridUnit * (root.cfg.compactRows ? 1.8 : 2.8)
        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                PlasmaComponents3.ToolButton {
                    text: i18n("Dagu")
                    icon.name: "view-calendar-tasks"
                    font.bold: true
                    onClicked: root.openUrl("/")
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: Kirigami.Units.smallSpacing * 2
                    height: width
                    radius: width / 2
                    color: root.stateColor
                }
                PlasmaComponents3.Label {
                    text: root.baseUrl.replace(/^https?:\/\//, "")
                    opacity: 0.7
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "view-refresh"
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    text: i18n("Refresh")
                    onClicked: root.refresh()
                }
            }
        }

        // Own right-click menu: the rows and buttons otherwise swallow Plasma's context menu
        MouseArea {
            anchors.fill: parent
            z: 10
            acceptedButtons: Qt.RightButton
            onClicked: mouse => contextMenu.popup()
        }
        PlasmaComponents3.Menu {
            id: contextMenu
            PlasmaComponents3.MenuItem {
                text: i18n("Configure Dagu Workflows…")
                icon.name: "configure"
                onTriggered: Plasmoid.internalAction("configure").trigger()
            }
            PlasmaComponents3.MenuItem {
                text: i18n("Open Dagu")
                icon.name: "internet-web-browser"
                onTriggered: root.openUrl("/")
            }
            PlasmaComponents3.MenuItem {
                text: i18n("Refresh")
                icon.name: "view-refresh"
                onTriggered: root.refresh()
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                visible: !root.reachable
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.negativeTextColor
                text: root.loaded
                    ? i18n("Dagu not reachable. Last update %1.", Fmt.whenLabel(root.lastOk, root.now, root.cfg.use24h))
                    : i18n("Dagu not reachable at %1.", root.baseUrl)
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.shownDags
                delegate: DagRow {
                    width: ListView.view.width
                    dag: modelData
                    now: root.now
                    stale: !root.reachable
                    compact: root.cfg.compactRows
                    showSchedule: root.cfg.showSchedule
                    showDuration: root.cfg.showDuration
                    use24h: root.cfg.use24h
                    baseUrl: root.baseUrl
                    onActivated: fileName => root.openUrl("/dags/" + encodeURIComponent(fileName))
                }
            }
        }
    }
}
