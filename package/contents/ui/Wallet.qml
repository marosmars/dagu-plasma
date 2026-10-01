import QtQuick
import org.kde.plasma.workspace.dbus as DBus

// Reads and writes the widget's secrets in KWallet (folder "dagu-plasma") over D-Bus.
QtObject {
    id: wallet

    readonly property string folder: "dagu-plasma"
    readonly property string appId: "dagu-plasma"
    property int handle: -1
    property string error: ""

    // Typed replies come back wrapped ({ value: ... }); return the plain value
    function unwrap(v) {
        return v !== null && v !== undefined && v.value !== undefined ? v.value : v;
    }

    // Calls org.kde.KWallet.<member>. No `signature` key: asyncCall drops the arguments when given one.
    function call(member, args, resolve, fail) {
        DBus.SessionBus.asyncCall({
            service: "org.kde.kwalletd6",
            path: "/modules/kwalletd6",
            iface: "org.kde.KWallet",
            member: member,
            arguments: args,
        }, reply => resolve(unwrap(reply.value)), function (reply) {
            // reject receives the pending reply; the D-Bus error sits in reply.error
            var err = reply && reply.error ? reply.error.name + ": " + reply.error.message : String(reply);
            wallet.error = i18n("KWallet error: %1", err);
            console.warn("dagu widget: KWallet", member, "failed:", err);
            if (fail) fail();
        });
    }

    // done(handle) with an open handle to the network wallet, opened once and reused
    function withHandle(done, fail) {
        if (handle >= 0) {
            call("isOpen", [new DBus.int32(handle)], function (open) {
                if (open) done(handle);
                else { wallet.handle = -1; withHandle(done, fail); }
            }, fail);
            return;
        }
        call("networkWallet", [], function (name) {
            call("open", [new DBus.string(name), new DBus.int64(0), new DBus.string(appId)], function (h) {
                if (h < 0) {
                    wallet.error = i18n("KWallet could not be opened.");
                    if (fail) fail();
                    return;
                }
                wallet.handle = h;
                wallet.error = "";
                done(h);
            }, fail);
        }, fail);
    }

    // read(key, cb, fail): cb(secret), "" when there is no entry
    function read(key, cb, fail) {
        if (!key) { cb(""); return; }
        withHandle(function (h) {
            call("readPassword", [new DBus.int32(h), new DBus.string(folder), new DBus.string(key), new DBus.string(appId)],
                value => cb(value || ""), fail);
        }, fail);
    }

    // write(key, value, cb): cb(ok). Stores value, or removes the entry when value is empty.
    function write(key, value, cb) {
        var done = cb || function () {};
        var fail = () => done(false);
        if (!key) { fail(); return; }
        withHandle(function (h) {
            var base = [new DBus.int32(h), new DBus.string(folder), new DBus.string(key)];
            call("createFolder", [new DBus.int32(h), new DBus.string(folder), new DBus.string(appId)], function () {
                if (value) {
                    call("writePassword", base.concat([new DBus.string(value), new DBus.string(appId)]),
                        result => done(result === 0), fail);
                } else {
                    call("removeEntry", base.concat([new DBus.string(appId)]), result => done(result === 0), fail);
                }
            }, fail);
        }, fail);
    }
}
