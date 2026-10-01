import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property alias cfg_serverUrl: serverUrl.text
    property alias cfg_refreshSeconds: refreshSeconds.value
    property var cfg_hiddenDags: []
    property string cfg_sortBy: "name"
    property alias cfg_compactRows: compactRows.checked
    property alias cfg_showSchedule: showSchedule.checked
    property alias cfg_showDuration: showDuration.checked
    property bool cfg_use24h: true
    property alias cfg_notifyOnFailure: notifyOnFailure.checked

    // Plasma passes each option's default as cfg_<name>Default; the page must declare them
    property string cfg_serverUrlDefault
    property int cfg_refreshSecondsDefault
    property var cfg_hiddenDagsDefault
    property string cfg_sortByDefault
    property bool cfg_compactRowsDefault
    property bool cfg_showScheduleDefault
    property bool cfg_showDurationDefault
    property bool cfg_use24hDefault
    property bool cfg_notifyOnFailureDefault

    // DAG names known to the server, plus hidden ones it no longer reports
    property var dagNames: []
    property string fetchError: ""

    function loadDagNames() {
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            var names = [];
            try {
                if (xhr.status !== 200) throw new Error("HTTP " + xhr.status);
                var dags = JSON.parse(xhr.responseText).dags || [];
                names = dags.map(d => (d.dag && d.dag.name) || d.fileName);
                page.fetchError = "";
            } catch (e) {
                page.fetchError = i18n("Could not load workflows from %1", serverUrl.text);
            }
            (page.cfg_hiddenDags || []).forEach(n => { if (names.indexOf(n) < 0) names.push(n); });
            names.sort();
            page.dagNames = names;
        };
        xhr.open("GET", serverUrl.text.replace(/\/+$/, "") + "/api/v2/dags?perPage=200");
        xhr.send();
    }

    function setHidden(name, hidden) {
        var list = (cfg_hiddenDags || []).filter(n => n !== name);
        if (hidden) list.push(name);
        cfg_hiddenDags = list;
    }

    Component.onCompleted: loadDagNames()

    Kirigami.FormLayout {
        QQC2.TextField {
            id: serverUrl
            Kirigami.FormData.label: i18n("Dagu server URL:")
            placeholderText: "http://localhost:8085"
            onEditingFinished: page.loadDagNames()
        }
        QQC2.SpinBox {
            id: refreshSeconds
            Kirigami.FormData.label: i18n("Refresh every (seconds):")
            from: 5
            to: 3600
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Workflows")
        }
        ColumnLayout {
            Kirigami.FormData.label: i18n("Show:")
            Kirigami.FormData.labelAlignment: Qt.AlignTop
            Repeater {
                model: page.dagNames
                QQC2.CheckBox {
                    required property string modelData
                    text: modelData
                    checked: (page.cfg_hiddenDags || []).indexOf(modelData) < 0
                    onToggled: page.setHidden(modelData, !checked)
                }
            }
            QQC2.Label {
                visible: page.fetchError !== ""
                text: page.fetchError
                color: Kirigami.Theme.negativeTextColor
            }
        }
        QQC2.ComboBox {
            id: sortBy
            Kirigami.FormData.label: i18n("Sort by:")
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18n("Name"), value: "name" },
                { text: i18n("Next run"), value: "nextRun" },
                { text: i18n("Status (failures first)"), value: "status" },
            ]
            currentIndex: Math.max(0, indexOfValue(page.cfg_sortBy))
            onActivated: page.cfg_sortBy = currentValue
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Appearance")
        }
        QQC2.CheckBox {
            id: compactRows
            Kirigami.FormData.label: i18n("Layout:")
            text: i18n("Compact (one line per workflow)")
        }
        QQC2.CheckBox {
            id: showSchedule
            text: i18n("Show cron schedule")
            enabled: !compactRows.checked
        }
        QQC2.CheckBox {
            id: showDuration
            text: i18n("Show last run duration")
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Time format:")
            model: [i18n("24-hour (13:00)"), i18n("12-hour (1:00 PM)")]
            currentIndex: page.cfg_use24h ? 0 : 1
            onActivated: index => page.cfg_use24h = index === 0
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Notifications")
        }
        QQC2.CheckBox {
            id: notifyOnFailure
            Kirigami.FormData.label: i18n("Failures:")
            text: i18n("Notify when a workflow run fails")
        }
    }
}
