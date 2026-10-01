import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_serverUrl: serverUrl.text
    property alias cfg_refreshSeconds: refreshSeconds.value

    Kirigami.FormLayout {
        QQC2.TextField {
            id: serverUrl
            Kirigami.FormData.label: i18n("Dagu server URL:")
            placeholderText: "http://localhost:8085"
        }
        QQC2.SpinBox {
            id: refreshSeconds
            Kirigami.FormData.label: i18n("Refresh every (seconds):")
            from: 5
            to: 3600
        }
    }
}
