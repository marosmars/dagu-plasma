import QtQuick
import org.kde.plasma.workspace.dbus as DBus

// Reads and writes the widget's secrets in KWallet (folder "dagu-plasma") over D-Bus.
QtObject {
    id: wallet

    readonly property string folder: "dagu-plasma"
    readonly property string appId: "dagu-plasma"
    property int handle: -1
    property string error: ""
    // Called when a wallet call fails, so callers waiting on a reply can carry on
    property var onFailure: null

    // Typed replies come back wrapped ({ value: ... }); return the plain value
    function unwrap(v) {
        return v !== null && v !== undefined && v.value !== undefined ? v.value : v;
    }

    // signature documents the call only: passing it to asyncCall makes it drop the arguments
    function call(member, signature, args, resolve, reject) {
        DBus.SessionBus.asyncCall({
            service: "org.kde.kwalletd6",
            path: "/modules/kwalletd6",
            iface: "org.kde.KWallet",
            member: member,
            arguments: args,
        }, reply => resolve({ value: unwrap(reply.value) }), reject || function (reply) {
            // reject receives the DBusPendingReply; the D-Bus error sits in reply.error
            var err = reply && reply.error ? reply.error.name + ": " + reply.error.message : String(reply);
            wallet.error = i18n("KWallet error: %1", err);
            console.warn("dagu widget: KWallet", member, "failed:", wallet.error);
            if (wallet.onFailure) wallet.onFailure();
        });
    }

    // Calls done(handle) with an open wallet handle, opening the network wallet once.
    function withHandle(done) {
        if (handle >= 0) {
            call("isOpen", "i", [new DBus.int32(handle)], function (reply) {
                if (reply.value) done(handle);
                else { wallet.handle = -1; withHandle(done); }
            });
            return;
        }
        call("networkWallet", "", [], function (reply) {
            call("open", "sxs", [new DBus.string(reply.value), new DBus.int64(0), new DBus.string(appId)],
                function (opened) {
                    if (opened.value < 0) {
                        wallet.error = i18n("KWallet could not be opened.");
                        return;
                    }
                    wallet.handle = opened.value;
                    wallet.error = "";
                    done(opened.value);
                });
        });
    }

    // read(key, cb): cb(secret) with "" when missing
    function read(key, cb) {
        if (!key) { cb(""); return; }
        withHandle(function (h) {
            call("readPassword", "isss", [new DBus.int32(h), new DBus.string(folder), new DBus.string(key), new DBus.string(appId)],
                reply => cb(reply.value || ""));
        });
    }

    // write(key, value, cb): stores value, or removes the entry when value is empty
    function write(key, value, cb) {
        if (!key) { if (cb) cb(false); return; }
        withHandle(function (h) {
            call("createFolder", "iss", [new DBus.int32(h), new DBus.string(folder), new DBus.string(appId)], function () {
                if (value) {
                    call("writePassword", "issss", [new DBus.int32(h), new DBus.string(folder), new DBus.string(key),
                        new DBus.string(value), new DBus.string(appId)], reply => { if (cb) cb(reply.value === 0); });
                } else {
                    call("removeEntry", "isss", [new DBus.int32(h), new DBus.string(folder), new DBus.string(key),
                        new DBus.string(appId)], reply => { if (cb) cb(reply.value === 0); });
                }
            });
        });
    }
}
