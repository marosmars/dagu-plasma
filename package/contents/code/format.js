.pragma library

// Pure helpers for turning the dagu API response into display values.

var DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
var MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

function pad(n) {
    return n < 10 ? '0' + n : '' + n;
}

function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

// "13:00" today, "tmrw 08:00", "yday 23:05", "Mon 09:00" within a week, else "20 Nov".
function whenLabel(date, now) {
    if (!date) return '';
    var hm = pad(date.getHours()) + ':' + pad(date.getMinutes());
    var days = Math.round((startOfDay(date) - startOfDay(now)) / 86400000);
    if (days === 0) return hm;
    if (days === 1) return 'tmrw ' + hm;
    if (days === -1) return 'yday ' + hm;
    if (Math.abs(days) < 7) return DAYS[date.getDay()] + ' ' + hm;
    return date.getDate() + ' ' + MONTHS[date.getMonth()];
}

// "44s", "3m", "1h 5m"; empty when either end is missing.
function durationLabel(startedAt, finishedAt) {
    if (!startedAt || !finishedAt) return '';
    var secs = Math.round((new Date(finishedAt) - new Date(startedAt)) / 1000);
    if (isNaN(secs) || secs < 0) return '';
    if (secs < 60) return secs + 's';
    var mins = Math.round(secs / 60);
    if (mins < 60) return mins + 'm';
    return Math.floor(mins / 60) + 'h ' + (mins % 60) + 'm';
}

// Collapse dagu status labels into: ok, failed, warning, running, none.
function statusKind(label) {
    switch (label) {
    case 'succeeded':
        return 'ok';
    case 'failed':
    case 'aborted':
    case 'rejected':
        return 'failed';
    case 'partially_succeeded':
        return 'warning';
    case 'running':
    case 'queued':
    case 'waiting':
        return 'running';
    default:
        return 'none';
    }
}

// Overall widget state for the compact icon: down, failed, running or ok.
function overallState(rows, reachable) {
    if (!reachable) return 'down';
    var running = false;
    for (var i = 0; i < rows.length; i++) {
        if (rows[i].kind === 'failed' || rows[i].kind === 'warning') return 'failed';
        if (rows[i].kind === 'running') running = true;
    }
    return running ? 'running' : 'ok';
}

// Flatten GET /api/v2/dags into plain rows, sorted by name.
function toRows(payload) {
    var dags = (payload && payload.dags) || [];
    var rows = [];
    for (var i = 0; i < dags.length; i++) {
        var entry = dags[i] || {};
        var dag = entry.dag || {};
        var run = entry.latestDAGRun || {};
        var status = run.statusLabel || 'not_started';
        rows.push({
            name: dag.name || entry.fileName || '',
            fileName: entry.fileName || dag.name || '',
            schedules: (dag.schedule || []).map(function (s) { return s.expression; }),
            suspended: !!entry.suspended,
            status: status,
            kind: statusKind(status),
            startedAt: run.startedAt || '',
            finishedAt: run.finishedAt || '',
            error: (entry.errors || []).join('\n'),
        });
    }
    rows.sort(function (a, b) { return a.name < b.name ? -1 : a.name > b.name ? 1 : 0; });
    return rows;
}
