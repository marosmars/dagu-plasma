.pragma library

// Minimal 5-field cron parser (minute hour day-of-month month day-of-week).
// Supports *, n, a-b, a,b,c, */n, a/n, a-b/n. Local time. No @shorthands.

var FIELDS = [
    { min: 0, max: 59 }, // minute
    { min: 0, max: 23 }, // hour
    { min: 1, max: 31 }, // day of month
    { min: 1, max: 12 }, // month
    { min: 0, max: 7 },  // day of week (0 and 7 = Sunday)
];

function parseField(text, min, max) {
    var allowed = [];
    for (var i = 0; i <= max; i++) allowed.push(false);
    var parts = text.split(',');
    for (var p = 0; p < parts.length; p++) {
        var m = /^(\*|\d+(?:-\d+)?)(?:\/(\d+))?$/.exec(parts[p]);
        if (!m) return null;
        var lo, hi;
        var step = m[2] !== undefined ? parseInt(m[2], 10) : 1;
        if (m[1] === '*') {
            lo = min;
            hi = max;
        } else {
            var range = m[1].split('-');
            lo = parseInt(range[0], 10);
            // "a/n" runs from a to max; plain "a" is a single value
            hi = range.length === 2 ? parseInt(range[1], 10) : (m[2] !== undefined ? max : lo);
        }
        if (step < 1 || lo < min || hi > max || lo > hi) return null;
        for (var v = lo; v <= hi; v += step) allowed[v] = true;
    }
    return allowed;
}

function parseCron(expr) {
    if (typeof expr !== 'string') return null;
    var parts = expr.trim().split(/\s+/);
    if (parts.length !== 5) return null;
    var fields = [];
    for (var i = 0; i < 5; i++) {
        var f = parseField(parts[i], FIELDS[i].min, FIELDS[i].max);
        if (!f) return null;
        fields.push(f);
    }
    var dow = fields[4];
    if (dow[7]) dow[0] = true;
    return {
        minute: fields[0],
        hour: fields[1],
        dom: fields[2],
        month: fields[3],
        dow: dow,
        domRestricted: parts[2] !== '*',
        dowRestricted: parts[4] !== '*',
    };
}

function dayMatches(c, date) {
    var domOk = c.dom[date.getDate()];
    var dowOk = c.dow[date.getDay()];
    // Standard cron: when both are restricted, either one matching is enough
    if (c.domRestricted && c.dowRestricted) return domOk || dowOk;
    return domOk && dowOk;
}

// First matching time strictly after `from`, within 366 days, or null.
function nextRun(expr, from) {
    var c = parseCron(expr);
    if (!c) return null;
    var t = new Date(from.getTime());
    t.setSeconds(0, 0);
    t.setMinutes(t.getMinutes() + 1);
    var limit = from.getTime() + 366 * 24 * 3600 * 1000;
    while (t.getTime() <= limit) {
        if (!c.month[t.getMonth() + 1] || !dayMatches(c, t)) {
            t.setDate(t.getDate() + 1);
            t.setHours(0, 0, 0, 0);
            continue;
        }
        if (!c.hour[t.getHours()]) {
            t.setHours(t.getHours() + 1, 0, 0, 0);
            continue;
        }
        if (!c.minute[t.getMinutes()]) {
            t.setMinutes(t.getMinutes() + 1, 0, 0);
            continue;
        }
        return t;
    }
    return null;
}

// Earliest next run across several expressions, or null.
function nextRunAny(exprs, from) {
    var best = null;
    for (var i = 0; i < (exprs || []).length; i++) {
        var n = nextRun(exprs[i], from);
        if (n && (!best || n.getTime() < best.getTime())) best = n;
    }
    return best;
}
