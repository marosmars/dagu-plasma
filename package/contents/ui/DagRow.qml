import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "../code/cron.js" as Cron
import "../code/format.js" as Fmt

// One DAG: status icon, name + next run, schedule + last run.
PlasmaComponents3.ItemDelegate {
    id: row

    property var dag: ({})
    property date now: new Date()
    property bool stale: false

    signal activated(string fileName)

    readonly property var nextRun: dag.suspended ? null : Cron.nextRunAny(dag.schedules, now)
    readonly property string lastRun: dag.startedAt
        ? Fmt.whenLabel(new Date(dag.startedAt), now)
          + (Fmt.durationLabel(dag.startedAt, dag.finishedAt) ? " · " + Fmt.durationLabel(dag.startedAt, dag.finishedAt) : "")
        : i18n("never run")

    opacity: stale ? 0.5 : 1
    onClicked: activated(dag.fileName)

    QQC2.ToolTip.visible: hovered && dag.error !== ""
    QQC2.ToolTip.text: dag.error

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing * 2

        Kirigami.Icon {
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            Layout.alignment: Qt.AlignVCenter
            source: {
                if (row.dag.error !== "") return "data-warning";
                switch (row.dag.kind) {
                case "ok": return "data-success";
                case "failed": return "data-error";
                case "warning": return "data-warning";
                case "running": return "media-playback-start";
                default: return "data-information";
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: row.dag.name
                    font.bold: true
                    elide: Text.ElideRight
                }
                PlasmaComponents3.Label {
                    text: row.dag.suspended ? i18n("⏸ suspended")
                        : row.dag.kind === "running" ? i18n("running…")
                        : row.nextRun ? i18n("next %1", Fmt.whenLabel(row.nextRun, row.now))
                        : ""
                    color: row.dag.suspended ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                }
            }
            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: row.dag.schedules.length ? row.dag.schedules.join("  ") : i18n("no schedule")
                    font.family: "monospace"
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.7
                    elide: Text.ElideRight
                }
                PlasmaComponents3.Label {
                    text: i18n("last %1", row.lastRun)
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: row.dag.kind === "failed" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                    opacity: row.dag.kind === "failed" ? 1 : 0.7
                }
            }
        }
    }
}
