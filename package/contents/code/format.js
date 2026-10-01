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

function clockLabel(date, use24h) {
    if (use24h === false) {
        var h = date.getHours() % 12 || 12;
        return h + ':' + pad(date.getMinutes()) + (date.getHours() < 12 ? ' AM' : ' PM');
    }
    return pad(date.getHours()) + ':' + pad(date.getMinutes());
}

// "13:00" today, "tmrw 08:00", "yday 23:05", "Mon 09:00" within a week, else "20 Nov".
// use24h defaults to true; false gives "1:00 PM".
function whenLabel(date, now, use24h) {
    if (!date) return '';
    var hm = clockLabel(date, use24h);
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
        if (isFailure(rows[i].kind)) return 'failed';
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

function isFailure(kind) {
    return kind === 'failed' || kind === 'warning';
}

// Rows whose name is not in the hidden list.
function visibleRows(rows, hidden) {
    var skip = {};
    for (var i = 0; i < (hidden || []).length; i++) skip[hidden[i]] = true;
    return rows.filter(function (r) { return !skip[r.name]; });
}

var STATUS_ORDER = { failed: 0, warning: 1, running: 2, none: 3, ok: 4 };

function byName(a, b) {
    return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
}

// Sorted copy: "name", "nextRun" (rows carry a `next` Date or null; null last),
// or "status" (failures first). Ties break by name.
function sortRows(rows, by) {
    var copy = rows.slice();
    copy.sort(function (a, b) {
        if (by === 'nextRun') {
            var an = a.next ? a.next.getTime() : Infinity;
            var bn = b.next ? b.next.getTime() : Infinity;
            if (an !== bn) return an < bn ? -1 : 1;
        } else if (by === 'status') {
            var as = STATUS_ORDER[a.kind] !== undefined ? STATUS_ORDER[a.kind] : 3;
            var bs = STATUS_ORDER[b.kind] !== undefined ? STATUS_ORDER[b.kind] : 3;
            if (as !== bs) return as - bs;
        }
        return byName(a, b);
    });
    return copy;
}

// Rows that failed since the previous fetch. prevRows null = first fetch, never notify.
function newFailures(prevRows, rows) {
    if (!prevRows) return [];
    var prev = {};
    for (var i = 0; i < prevRows.length; i++) prev[prevRows[i].name] = prevRows[i];
    return rows.filter(function (r) {
        if (!isFailure(r.kind)) return false;
        var p = prev[r.name];
        return !p || !isFailure(p.kind) || p.startedAt !== r.startedAt;
    });
}

// ---- Hover details ----

function escapeHtml(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// Substitute ${VAR} / $VAR from a dagu env list of "KEY=VALUE" strings.
function expandVars(text, envList) {
    var env = {};
    (envList || []).forEach(function (kv) {
        var i = kv.indexOf('=');
        if (i > 0) env[kv.slice(0, i)] = kv.slice(i + 1);
    });
    return String(text).replace(/\$\{(\w+)\}|\$(\w+)/g, function (m, a, b) {
        var key = a || b;
        return env[key] !== undefined ? env[key] : m;
    });
}

function shortPath(p) {
    return (p || '').replace(/^\/home\/[^/]+(?=\/|$)/, '~');
}

// [{ name, dir, command }] for each step: vars expanded, program shortened to its name.
function stepInputs(detail) {
    var env = (detail && detail.env) || [];
    return ((detail && detail.steps) || []).map(function (step) {
        var cmds = step.commands && step.commands.length
            ? step.commands
            : [{ command: step.command || '', args: step.args || [] }];
        var command = cmds.map(function (c) {
            var program = expandVars(c.command || '', env);
            if (/^\//.test(program) && program.indexOf(' ') < 0) program = program.split('/').pop();
            return [program].concat((c.args || []).map(function (a) { return expandVars(a, env); })).join(' ');
        }).join(' && ');
        return { name: step.name, dir: shortPath(expandVars(step.dir || '', env)), command: command };
    });
}

var MONO = 'font-family:monospace; white-space:pre-wrap;';

function section(title) {
    return '<p style="margin-top:6px; margin-bottom:2px;"><b>' + escapeHtml(title) + '</b></p>';
}

// Tooltip for the NEXT column: schedule, upcoming runs, step inputs.
function nextTooltipHtml(row, upcoming, detail) {
    var html = section('Schedule');
    html += '<p style="' + MONO + '">' + (row.schedules && row.schedules.length
        ? escapeHtml(row.schedules.join('   ')) : 'no schedule') + '</p>';
    if (upcoming && upcoming.length) {
        html += section('Upcoming') + '<p>' + escapeHtml(upcoming.join(' · ')) + '</p>';
    }
    var inputs = stepInputs(detail);
    if (inputs.length) {
        html += section('Input');
        inputs.forEach(function (s) {
            html += '<p style="margin-bottom:2px;">' + escapeHtml(s.name)
                + (s.dir ? ' <span style="opacity:0.7">in ' + escapeHtml(s.dir) + '</span>' : '') + '</p>'
                + '<p style="' + MONO + ' margin-left:8px;">' + escapeHtml(s.command) + '</p>';
        });
    } else if (!detail) {
        html += '<p style="opacity:0.7">loading…</p>';
    }
    return html;
}

function tailBlock(label, text, total) {
    if (!text) return '';
    var shown = text.split('\n').length;
    var note = total > shown ? ' <span style="opacity:0.7">(last ' + shown + ' of ' + total + ' lines)</span>' : '';
    return '<p style="margin-top:4px; margin-bottom:0;">' + label + note + '</p>'
        + '<p style="' + MONO + ' margin-left:8px;">' + escapeHtml(text) + '</p>';
}

// Tooltip for the LAST column: run status/times, per-step status and output tails.
// logs: { stepName: { stdout, stderr, stdoutTotal, stderrTotal } }
function lastTooltipHtml(run, logs, timesLabel) {
    if (!run) return '<p>never run</p>';
    var html = '<p><b>' + escapeHtml((run.statusLabel || '').replace(/_/g, ' ')) + '</b>'
        + (timesLabel ? '  ' + escapeHtml(timesLabel) : '') + '</p>';
    (run.nodes || []).forEach(function (node) {
        var name = (node.step && node.step.name) || '';
        var dur = durationLabel(node.startedAt, node.finishedAt);
        html += section(name + ' — ' + (node.statusLabel || '').replace(/_/g, ' ') + (dur ? ' · ' + dur : ''));
        var log = (logs || {})[name];
        if (!log) {
            html += '<p style="opacity:0.7">loading output…</p>';
            return;
        }
        var out = tailBlock('stdout', log.stdout, log.stdoutTotal) + tailBlock('stderr', log.stderr, log.stderrTotal);
        html += out || '<p style="opacity:0.7">no output</p>';
    });
    return html;
}
