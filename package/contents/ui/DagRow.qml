import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore

import "../code/cron.js" as Cron
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
    property string baseUrl: ""
    property string authHeader: ""
    property int historyCount: 5
    property bool showSeparator: true

    // Hover details, fetched on first hover and refetched when a new run appears
    property var detail: null
    property var lastRun: null
    property var logs: ({})
    property string loadedFor: ""

    signal activated(string fileName)
    signal lastRunActivated(var dag)
    signal contextRequested(var dag)

    // Header mode renders the column captions with the exact same layout as a row
    property bool isHeader: false

    readonly property bool failed: dag.kind === "failed" || dag.kind === "warning"
    readonly property string countdown: dag.next ? (Fmt.countdownLabel(dag.next, now) || "") : ""
    // Every cell: line 1 = bold primary value, line 2 = small secondary detail
    readonly property string nextPrimary: dag.suspended ? i18n("suspended")
        : dag.kind === "running" ? i18n("running…")
        : dag.next ? (countdown || Fmt.whenLabel(dag.next, now, use24h))
        : "—"
    readonly property string nextSecondary: dag.suspended || dag.kind === "running" || !dag.next ? ""
        : countdown ? Fmt.whenLabel(dag.next, now, use24h) : ""
    readonly property string lastPrimary: dag.startedAt ? Fmt.whenLabel(new Date(dag.startedAt), now, use24h) : i18n("never")
    readonly property string lastSecondary: {
        var parts = [];
        if (dag.startedAt && dag.kind !== "ok") parts.push((dag.status || "").replace(/_/g, " "));
        var dur = showDuration ? Fmt.durationLabel(dag.startedAt, dag.finishedAt) : "";
        if (dur) parts.push(i18n("took %1", dur));
        return parts.join(" · ");
    }
    readonly property color lastColor: failed ? Kirigami.Theme.negativeTextColor
        : dag.kind === "ok" ? Kirigami.Theme.positiveTextColor
        : Kirigami.Theme.textColor
    readonly property color nextColor: dag.suspended ? Kirigami.Theme.neutralTextColor
        : dag.kind === "running" ? Kirigami.Theme.highlightColor
        : Kirigami.Theme.textColor

    // Shared column geometry (header and rows use the same numbers)
    readonly property real lineHeight: primaryMetrics.height
    readonly property real dotSize: Math.round(Kirigami.Units.gridUnit * 0.45)
    readonly property real dotGap: Math.round(Kirigami.Units.gridUnit * 0.2)
    readonly property string historyCaption: i18np("LAST RUN", "LAST %1 RUNS", historyCount)
    // Caption width plus its letter spacing (FontMetrics ignores it)
    readonly property real historyWidth: Math.max(historyCount * (dotSize + dotGap),
        captionMetrics.advanceWidth(historyCaption) + historyCaption.length + Kirigami.Units.smallSpacing)
    readonly property real timeWidth: Kirigami.Units.gridUnit * (use24h ? 6 : 7.5)
    readonly property bool twoLines: !compact && !isHeader

    FontMetrics {
        id: primaryMetrics
        font.bold: true
        font.pointSize: Kirigami.Theme.defaultFont.pointSize
    }
    FontMetrics {
        id: captionMetrics
        font.pointSize: Kirigami.Theme.smallFont.pointSize
    }

    hoverEnabled: !isHeader
    background.visible: !isHeader
    opacity: stale ? 0.5 : 1
    onClicked: if (!isHeader) activated(dag.fileName)

    function getJson(path, callback) {
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) return;
            try {
                callback(JSON.parse(xhr.responseText));
            } catch (e) {
                console.warn("dagu widget: bad JSON from", path, e);
            }
        };
        xhr.open("GET", baseUrl + path);
        if (authHeader) xhr.setRequestHeader("Authorization", authHeader);
        xhr.send();
    }

    function loadLog(runId, stepName, stream, tail) {
        var name = encodeURIComponent(dag.fileName);
        getJson("/api/v2/dag-runs/" + name + "/" + runId + "/steps/" + encodeURIComponent(stepName)
                + "/log?stream=" + stream + "&tail=" + tail, function (res) {
            var copy = Object.assign({}, row.logs);
            var entry = Object.assign({}, copy[stepName] || {});
            entry[stream] = (res.content || "").replace(/\s+$/, "");
            entry[stream + "Total"] = res.totalLines || 0;
            copy[stepName] = entry;
            row.logs = copy;
        });
    }

    function loadDetails() {
        var key = dag.fileName + "@" + dag.startedAt + "@" + dag.status;
        if (loadedFor === key) return;
        loadedFor = key;
        var name = encodeURIComponent(dag.fileName);
        getJson("/api/v2/dags/" + name, res => row.detail = res.dag || {});
        getJson("/api/v2/dags/" + name + "/dag-runs?limit=1", function (res) {
            var run = (res.dagRuns || [])[0] || null;
            row.lastRun = run;
            row.logs = {};
            if (!run) return;
            (run.nodes || []).forEach(function (node) {
                var stepName = node.step && node.step.name;
                if (!stepName) return;
                row.loadLog(run.dagRunId, stepName, "stdout", 8);
                row.loadLog(run.dagRunId, stepName, "stderr", 4);
            });
        });
    }

    function nextTooltip() {
        var upcoming = dag.suspended ? [] : Cron.nextRuns(dag.schedules || [], now, 4)
            .map(d => Fmt.whenLabel(d, now, use24h));
        return Fmt.nextTooltipHtml(dag, upcoming, detail);
    }

    function lastTooltip() {
        var times = "";
        if (lastRun && lastRun.startedAt) {
            times = Fmt.whenLabel(new Date(lastRun.startedAt), now, use24h);
            if (lastRun.finishedAt) {
                times += " → " + Fmt.whenLabel(new Date(lastRun.finishedAt), now, use24h)
                    + " (" + Fmt.durationLabel(lastRun.startedAt, lastRun.finishedAt) + ")";
            }
        }
        return Fmt.lastTooltipHtml(lastRun, logs, times);
    }

    // Right-click: per-DAG menu (left clicks pass through to the delegate)
    MouseArea {
        anchors.fill: parent
        z: 1
        enabled: !row.isHeader
        acceptedButtons: Qt.RightButton
        onClicked: row.contextRequested(row.dag)
    }

    // Thin line under the row (off for the last row)
    Kirigami.Separator {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: row.leftPadding
        anchors.rightMargin: row.rightPadding
        visible: row.showSeparator
        opacity: row.isHeader ? 0.8 : 0.4
    }

    component Caption: PlasmaComponents3.Label {
        Layout.preferredHeight: row.lineHeight
        verticalAlignment: Text.AlignBottom
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        font.letterSpacing: 1
        opacity: 0.55
        elide: Text.ElideRight
    }
    component Primary: PlasmaComponents3.Label {
        Layout.preferredHeight: row.lineHeight
        verticalAlignment: Text.AlignVCenter
        font.bold: true
        font.pointSize: Kirigami.Theme.defaultFont.pointSize
        elide: Text.ElideRight
    }
    component Secondary: PlasmaComponents3.Label {
        visible: row.twoLines
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: 0.6
        elide: Text.ElideRight
    }

    contentItem: RowLayout {
        spacing: Kirigami.Units.largeSpacing

        // Status dot, centred on line 1; warning icon for DAG errors
        Item {
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: row.lineHeight
            Layout.alignment: Qt.AlignTop

            Rectangle {
                anchors.centerIn: parent
                visible: !row.isHeader && !row.dag.error
                width: Math.round(Kirigami.Units.iconSizes.small * 0.7)
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
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.small
                height: width
                visible: !row.isHeader && !!row.dag.error
                source: "data-warning"
            }
        }

        // Name / schedule
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 0

            HoverHandler { id: nameHover; enabled: !row.isHeader }
            QQC2.ToolTip.visible: nameHover.hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            QQC2.ToolTip.text: [
                row.dag.name + " — " + (row.dag.status || "").replace(/_/g, " "),
                row.dag.error || "",
            ].filter(s => s !== "").join("\n")

            Caption { visible: row.isHeader; Layout.fillWidth: true; text: i18n("WORKFLOW") }
            Primary { visible: !row.isHeader; Layout.fillWidth: true; text: row.dag.name || "" }
            Secondary {
                visible: row.twoLines && row.showSchedule
                Layout.fillWidth: true
                text: row.dag.schedules && row.dag.schedules.length ? row.dag.schedules.join("  ") : i18n("no schedule")
                font.family: "monospace"
            }
        }

        // Recent runs: dots on line 1 (oldest left), summary on line 2; hover a dot for details
        ColumnLayout {
            visible: row.historyCount > 0
            Layout.alignment: Qt.AlignTop
            // Extra gap so the dots don't crowd the NEXT column
            Layout.rightMargin: Kirigami.Units.gridUnit
            Layout.preferredWidth: row.historyWidth
            Layout.minimumWidth: row.historyWidth
            Layout.maximumWidth: row.historyWidth
            spacing: 0

            Caption { visible: row.isHeader; Layout.fillWidth: true; text: row.historyCaption }
            Row {
                visible: !row.isHeader
                Layout.preferredHeight: row.lineHeight
                spacing: row.dotGap

                Repeater {
                    model: (row.dag.history || []).slice(-row.historyCount)
                    delegate: PlasmaCore.ToolTipArea {
                        required property var modelData
                        width: row.dotSize
                        height: row.lineHeight
                        mainText: modelData.status.replace(/_/g, " ")
                        subText: modelData.startedAt ? Fmt.whenLabel(new Date(modelData.startedAt), row.now, row.use24h) : ""

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: row.dotSize
                            height: width
                            radius: width / 2
                            opacity: 0.85
                            color: {
                                switch (modelData.kind) {
                                case "ok": return Kirigami.Theme.positiveTextColor;
                                case "failed": return Kirigami.Theme.negativeTextColor;
                                case "warning": return Kirigami.Theme.neutralTextColor;
                                case "running": return Kirigami.Theme.highlightColor;
                                default: return Kirigami.Theme.disabledTextColor;
                                }
                            }
                        }
                    }
                }
            }
            Secondary { Layout.fillWidth: true; text: Fmt.historySummary((row.dag.history || []).slice(-row.historyCount)) }
        }

        // NEXT and LAST: same two-line cell; hover for details (next: schedule + input, last: steps + output)
        Repeater {
            // Static model: cells bind to row properties. A model holding the live values was
            // rebuilt on every change, recreating the cells mid-load and crashing plasmashell.
            model: ["next", "last"]
            delegate: PlasmaCore.ToolTipArea {
                id: valueTip
                required property string modelData
                readonly property bool isNext: modelData === "next"
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: row.timeWidth
                Layout.minimumWidth: row.timeWidth
                Layout.maximumWidth: row.timeWidth
                implicitHeight: valueColumn.implicitHeight

                active: !row.isHeader
                mainText: isNext ? i18n("Next run") : i18n("Last run")
                subText: row.isHeader ? "" : isNext ? row.nextTooltip() : row.lastTooltip()
                textFormat: Text.RichText
                onAboutToShow: row.loadDetails()

                // LAST is a link to that run's page in the dagu UI
                MouseArea {
                    anchors.fill: parent
                    enabled: !row.isHeader && !valueTip.isNext && row.dag.runId !== ""
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: row.lastRunActivated(row.dag)
                }

                ColumnLayout {
                    id: valueColumn
                    anchors.fill: parent
                    spacing: 0

                    Caption { visible: row.isHeader; Layout.fillWidth: true; text: valueTip.isNext ? i18n("NEXT") : i18n("LAST") }
                    Primary {
                        visible: !row.isHeader
                        Layout.fillWidth: true
                        text: valueTip.isNext ? row.nextPrimary : row.lastPrimary
                        color: valueTip.isNext ? row.nextColor : row.lastColor
                    }
                    Secondary { Layout.fillWidth: true; text: (valueTip.isNext ? row.nextSecondary : row.lastSecondary) || " " }
                }
            }
        }
    }
}
