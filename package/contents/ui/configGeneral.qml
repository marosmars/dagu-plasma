import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "../code/format.js" as Fmt

KCM.SimpleKCM {
    id: page

    property alias cfg_serverUrl: serverUrl.text
    property alias cfg_refreshSeconds: refreshSeconds.value
    property string cfg_authMode: "none"
    property alias cfg_username: username.text

    property var cfg_hiddenDags: []
    property string cfg_sortBy: "name"
    property alias cfg_historyCount: historyCount.value
    property alias cfg_compactRows: compactRows.checked
    property alias cfg_showSchedule: showSchedule.checked
    property alias cfg_showDuration: showDuration.checked
    property bool cfg_use24h: true
    property alias cfg_notifyOnFailure: notifyOnFailure.checked

    // Plasma passes each option's default as cfg_<name>Default; the page must declare them
    property string cfg_serverUrlDefault
    property int cfg_refreshSecondsDefault
    property string cfg_authModeDefault
    property string cfg_usernameDefault

    property var cfg_hiddenDagsDefault
    property int cfg_historyCountDefault
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
                page.fetchError = Fmt.requestError(xhr.status === 200 ? -1 : xhr.status, serverUrl.text)
                    || i18n("Could not load workflows from %1", serverUrl.text);
            }
            (page.cfg_hiddenDags || []).forEach(n => { if (names.indexOf(n) < 0) names.push(n); });
            names.sort();
            page.dagNames = names;
        };
        xhr.open("GET", serverUrl.text.replace(/\/+$/, "") + "/api/v2/dags?perPage=200");
        var secret = cfg_authMode === "basic" ? password.text : apiToken.text;
        var header = Fmt.authHeader(cfg_authMode, username.text, secret, secret, Qt.btoa);
        if (header) xhr.setRequestHeader("Authorization", header);
        xhr.send();
    }

    // The password / token is kept in KWallet, saved as soon as the field is edited
    Wallet { id: wallet }
    property string walletStatus: ""
    readonly property string walletKey: Fmt.walletKey(cfg_authMode, serverUrl.text, username.text)

    function loadSecret() {
        password.text = "";
        apiToken.text = "";
        walletStatus = "";
        if (!walletKey) return;
        wallet.read(walletKey, function (value) {
            if (page.cfg_authMode === "basic") password.text = value;
            else apiToken.text = value;
            page.walletStatus = value ? i18n("Loaded from KWallet.") : "";
        });
    }

    function saveSecret(value) {
        wallet.write(walletKey, value, function (ok) {
            page.walletStatus = !ok ? (wallet.error || i18n("Could not save to KWallet."))
                : value ? i18n("Saved in KWallet.") : i18n("Removed from KWallet.");
            page.loadDagNames();
        });
    }

    function setHidden(name, hidden) {
        var list = (cfg_hiddenDags || []).filter(n => n !== name);
        if (hidden) list.push(name);
        cfg_hiddenDags = list;
    }

    Component.onCompleted: { loadSecret(); loadDagNames(); }

    Kirigami.FormLayout {
        QQC2.TextField {
            id: serverUrl
            Kirigami.FormData.label: i18n("Dagu server URL:")
            placeholderText: "http://localhost:8085"
            onEditingFinished: page.loadDagNames()
        }
        QQC2.ComboBox {
            id: authMode
            Kirigami.FormData.label: i18n("Authentication:")
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18n("None"), value: "none" },
                { text: i18n("Username and password (basic)"), value: "basic" },
                { text: i18n("API token (bearer)"), value: "token" },
            ]
            currentIndex: Math.max(0, indexOfValue(page.cfg_authMode))
            onActivated: { page.cfg_authMode = currentValue; page.loadSecret(); page.loadDagNames(); }
        }
        QQC2.TextField {
            id: username
            visible: page.cfg_authMode === "basic"
            Kirigami.FormData.label: i18n("Username:")
            onEditingFinished: { page.loadSecret(); page.loadDagNames(); }
        }
        Kirigami.PasswordField {
            id: password
            visible: page.cfg_authMode === "basic"
            Kirigami.FormData.label: i18n("Password:")
            onEditingFinished: page.saveSecret(text)
        }
        Kirigami.PasswordField {
            id: apiToken
            visible: page.cfg_authMode === "token"
            Kirigami.FormData.label: i18n("API token:")
            onEditingFinished: page.saveSecret(text.trim())
        }
        QQC2.Label {
            visible: page.cfg_authMode !== "none"
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
            text: (page.walletStatus ? page.walletStatus + " " : "")
                + (wallet.error ? wallet.error + " " : "")
                + i18n("The password or token is stored in KWallet, not in the Plasma config. HTTPS certificates are verified; for a self-signed certificate, add it to the system trust store.")
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
        QQC2.SpinBox {
            id: historyCount
            Kirigami.FormData.label: i18n("Run history dots:")
            from: 0
            to: 20
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("How many recent runs to show per workflow; 0 hides the column")
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
