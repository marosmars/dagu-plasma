import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadQmlJs } from './load.mjs';

const { whenLabel, durationLabel, statusKind, overallState, toRows } = loadQmlJs('format.js', [
    'whenLabel', 'durationLabel', 'statusKind', 'overallState', 'toRows',
]);

const d = (y, mo, day, h, mi) => new Date(y, mo - 1, day, h, mi, 0, 0);
const NOW = d(2026, 10, 1, 10, 40); // Thursday

test('whenLabel: today, tomorrow, yesterday, this week, further', () => {
    assert.equal(whenLabel(d(2026, 10, 1, 13, 0), NOW), '13:00');
    assert.equal(whenLabel(d(2026, 10, 2, 8, 0), NOW), 'tmrw 08:00');
    assert.equal(whenLabel(d(2026, 9, 30, 23, 5), NOW), 'yday 23:05');
    assert.equal(whenLabel(d(2026, 10, 5, 9, 0), NOW), 'Mon 09:00');
    assert.equal(whenLabel(d(2026, 11, 20, 9, 0), NOW), '20 Nov');
    assert.equal(whenLabel(null, NOW), '');
});

test('durationLabel', () => {
    assert.equal(durationLabel('2026-10-01T08:44:15+02:00', '2026-10-01T08:47:26+02:00'), '3m');
    assert.equal(durationLabel('2026-10-01T08:44:15+02:00', '2026-10-01T08:44:59+02:00'), '44s');
    assert.equal(durationLabel('2026-10-01T08:00:00+02:00', '2026-10-01T09:05:00+02:00'), '1h 5m');
    assert.equal(durationLabel('2026-10-01T08:00:00+02:00', ''), '');
    assert.equal(durationLabel('', ''), '');
});

test('statusKind maps dagu labels', () => {
    assert.equal(statusKind('succeeded'), 'ok');
    assert.equal(statusKind('failed'), 'failed');
    assert.equal(statusKind('aborted'), 'failed');
    assert.equal(statusKind('partially_succeeded'), 'warning');
    assert.equal(statusKind('running'), 'running');
    assert.equal(statusKind('queued'), 'running');
    assert.equal(statusKind('not_started'), 'none');
    assert.equal(statusKind(undefined), 'none');
    assert.equal(statusKind('something_new'), 'none');
});

test('overallState priority: down > failed > running > ok', () => {
    const r = kind => ({ kind });
    assert.equal(overallState([r('ok')], false), 'down');
    assert.equal(overallState([r('ok'), r('failed'), r('running')], true), 'failed');
    assert.equal(overallState([r('ok'), r('warning')], true), 'failed');
    assert.equal(overallState([r('ok'), r('running')], true), 'running');
    assert.equal(overallState([r('ok'), r('none')], true), 'ok');
    assert.equal(overallState([], true), 'ok');
});

test('toRows flattens the v2 /dags response and sorts by name', () => {
    const rows = toRows({
        dags: [
            {
                dag: { name: 'zeta', schedule: [{ expression: '0 8 * * *' }] },
                fileName: 'zeta',
                suspended: true,
                errors: null,
                latestDAGRun: {
                    dagRunId: 'run-1',
                    statusLabel: 'failed',
                    startedAt: '2026-10-01T08:00:00+02:00',
                    finishedAt: '2026-10-01T08:01:00+02:00',
                },
            },
            { dag: { name: 'alpha' }, fileName: 'alpha-file', errors: ['bad yaml'] },
        ],
    });
    assert.equal(rows.length, 2);
    assert.deepEqual(rows[0], {
        name: 'alpha', fileName: 'alpha-file', schedules: [], suspended: false,
        status: 'not_started', kind: 'none', startedAt: '', finishedAt: '', error: 'bad yaml', runId: '',
    });
    assert.deepEqual(rows[1], {
        name: 'zeta', fileName: 'zeta', schedules: ['0 8 * * *'], suspended: true,
        status: 'failed', kind: 'failed', startedAt: '2026-10-01T08:00:00+02:00',
        finishedAt: '2026-10-01T08:01:00+02:00', error: '', runId: 'run-1',
    });
});

test('toRows tolerates a malformed payload', () => {
    assert.deepEqual(toRows({}), []);
    assert.deepEqual(toRows(null), []);
});

const more = loadQmlJs('format.js', ['whenLabel', 'visibleRows', 'sortRows', 'newFailures']);

test('whenLabel in 12h mode', () => {
    assert.equal(more.whenLabel(d(2026, 10, 1, 13, 0), NOW, false), '1:00 PM');
    assert.equal(more.whenLabel(d(2026, 10, 1, 0, 5), NOW, false), '12:05 AM');
    assert.equal(more.whenLabel(d(2026, 10, 2, 8, 0), NOW, false), 'tmrw 8:00 AM');
    assert.equal(more.whenLabel(d(2026, 10, 2, 8, 0), NOW, true), 'tmrw 08:00');
});

const row = (name, kind, next, startedAt = '') => ({ name, kind, next, startedAt });

test('visibleRows drops hidden DAG names', () => {
    const rows = [row('a', 'ok'), row('b', 'ok'), row('c', 'ok')];
    assert.deepEqual(more.visibleRows(rows, ['b']).map(r => r.name), ['a', 'c']);
    assert.deepEqual(more.visibleRows(rows, []).map(r => r.name), ['a', 'b', 'c']);
    assert.deepEqual(more.visibleRows(rows, undefined).map(r => r.name), ['a', 'b', 'c']);
});

test('sortRows by name, next run, status', () => {
    const rows = [
        row('c', 'ok', d(2026, 10, 1, 12, 0)),
        row('a', 'failed', null),
        row('b', 'running', d(2026, 10, 1, 11, 0)),
        row('d', 'none', d(2026, 10, 1, 11, 0)),
    ];
    assert.deepEqual(more.sortRows(rows, 'name').map(r => r.name), ['a', 'b', 'c', 'd']);
    // no next run goes last; ties by name
    assert.deepEqual(more.sortRows(rows, 'nextRun').map(r => r.name), ['b', 'd', 'c', 'a']);
    assert.deepEqual(more.sortRows(rows, 'status').map(r => r.name), ['a', 'b', 'd', 'c']);
    // does not mutate the input
    assert.deepEqual(rows.map(r => r.name), ['c', 'a', 'b', 'd']);
});

test('newFailures only reports failures that are new since the previous fetch', () => {
    const t1 = '2026-10-01T08:00:00+02:00';
    const t2 = '2026-10-01T14:00:00+02:00';
    // first fetch never notifies
    assert.deepEqual(more.newFailures(null, [row('a', 'failed', null, t1)]), []);
    // same failed run again: nothing new
    assert.deepEqual(more.newFailures([row('a', 'failed', null, t1)], [row('a', 'failed', null, t1)]), []);
    // ok -> failed
    assert.deepEqual(
        more.newFailures([row('a', 'ok', null, t1)], [row('a', 'failed', null, t2)]).map(r => r.name), ['a']);
    // failed -> a later failed run
    assert.deepEqual(
        more.newFailures([row('a', 'failed', null, t1)], [row('a', 'failed', null, t2)]).map(r => r.name), ['a']);
    // new DAG that already failed
    assert.deepEqual(more.newFailures([], [row('b', 'failed', null, t1)]).map(r => r.name), ['b']);
    // warning counts as a failure
    assert.deepEqual(
        more.newFailures([row('a', 'running', null, t1)], [row('a', 'warning', null, t1)]).map(r => r.name), ['a']);
});

const tip = loadQmlJs('format.js', ['expandVars', 'shortPath', 'stepInputs', 'escapeHtml', 'nextTooltipHtml', 'lastTooltipHtml']);

test('expandVars substitutes ${VAR} and $VAR from a KEY=VALUE env list', () => {
    const env = ['NODE_BIN=/opt/node/bin/node', 'PROJECT_DIR=/home/x/p'];
    assert.equal(tip.expandVars('${NODE_BIN} run', env), '/opt/node/bin/node run');
    assert.equal(tip.expandVars('cd $PROJECT_DIR', env), 'cd /home/x/p');
    assert.equal(tip.expandVars('${MISSING}', env), '${MISSING}');
    assert.equal(tip.expandVars('a=b', undefined), 'a=b');
});

test('shortPath abbreviates the home directory', () => {
    assert.equal(tip.shortPath('/home/maros/Projects/x'), '~/Projects/x');
    assert.equal(tip.shortPath('/opt/x'), '/opt/x');
    assert.equal(tip.shortPath(''), '');
});

const DETAIL = {
    env: ['NODE_BIN=/home/maros/.nvm/versions/node/v22/bin/node', 'PROJECT_DIR=/home/maros/p'],
    steps: [
        {
            name: 'run-daily-report',
            dir: '${PROJECT_DIR}',
            commands: [{ command: '${NODE_BIN}', args: ['--env-file=.env.local', 'scripts/daily-report.js'] }],
        },
        { name: 'shell', command: 'echo hi' },
    ],
};

test('stepInputs expands commands, shortens the program to its name, keeps dir', () => {
    assert.deepEqual(tip.stepInputs(DETAIL), [
        { name: 'run-daily-report', dir: '~/p', command: 'node --env-file=.env.local scripts/daily-report.js' },
        { name: 'shell', dir: '', command: 'echo hi' },
    ]);
    assert.deepEqual(tip.stepInputs({}), []);
});

test('escapeHtml', () => {
    assert.equal(tip.escapeHtml('<a & "b">'), '&lt;a &amp; &quot;b&quot;&gt;');
});

test('nextTooltipHtml shows schedule, upcoming runs and inputs', () => {
    const html = tip.nextTooltipHtml({ schedules: ['0 1/6 * * *'] }, ['13:00', '19:00'], DETAIL);
    assert.match(html, /0 1\/6 \* \* \*/);
    assert.match(html, /13:00 · 19:00/);
    assert.match(html, /node --env-file=.env.local scripts\/daily-report.js/);
    assert.match(html, /~\/p/);
    assert.match(tip.nextTooltipHtml({ schedules: [] }, [], null), /no schedule/);
});

test('lastTooltipHtml shows status, steps and escaped output tails', () => {
    const run = {
        statusLabel: 'failed',
        nodes: [{ step: { name: 'a' }, statusLabel: 'failed', startedAt: '2026-10-01T08:00:00+02:00', finishedAt: '2026-10-01T08:00:05+02:00' }],
    };
    const logs = { a: { stdout: 'line <1>\nline 2', stderr: 'boom', stdoutTotal: 30, stderrTotal: 1 } };
    const html = tip.lastTooltipHtml(run, logs, '08:00 → 08:00 (5s)');
    assert.match(html, /failed/);
    assert.match(html, /08:00 → 08:00 \(5s\)/);
    assert.match(html, /line &lt;1&gt;/);
    assert.match(html, /boom/);
    assert.match(html, /last 2 of 30 lines/);
    assert.match(tip.lastTooltipHtml(null, {}, ''), /never run/);
});

const extra = loadQmlJs('format.js', ['countdownLabel', 'historyItems']);

test('countdownLabel for runs within 24h, null otherwise', () => {
    assert.equal(extra.countdownLabel(d(2026, 10, 1, 10, 40, ) , NOW), 'in <1m');
    assert.equal(extra.countdownLabel(new Date(NOW.getTime() + 30 * 1000), NOW), 'in <1m');
    assert.equal(extra.countdownLabel(d(2026, 10, 1, 11, 25), NOW), 'in 45m');
    assert.equal(extra.countdownLabel(d(2026, 10, 1, 13, 0), NOW), 'in 2h 20m');
    assert.equal(extra.countdownLabel(d(2026, 10, 1, 12, 40), NOW), 'in 2h');
    assert.equal(extra.countdownLabel(d(2026, 10, 2, 10, 39), NOW), 'in 23h 59m');
    assert.equal(extra.countdownLabel(d(2026, 10, 2, 10, 41), NOW), null);
    assert.equal(extra.countdownLabel(null, NOW), null);
});

test('historyItems turns newest-first dag-runs into oldest-first items, capped', () => {
    const runs = [
        { dagRunId: 'c', statusLabel: 'failed', startedAt: 't3' },
        { dagRunId: 'b', statusLabel: 'succeeded', startedAt: 't2' },
        { dagRunId: 'a', statusLabel: 'running', startedAt: 't1' },
    ];
    assert.deepEqual(extra.historyItems({ dagRuns: runs }, 2), [
        { runId: 'b', status: 'succeeded', kind: 'ok', startedAt: 't2' },
        { runId: 'c', status: 'failed', kind: 'failed', startedAt: 't3' },
    ]);
    assert.deepEqual(extra.historyItems({}, 10), []);
    assert.deepEqual(extra.historyItems(null, 10), []);
});

test('historySummary counts ok and failed runs', () => {
    const { historySummary } = loadQmlJs('format.js', ['historySummary']);
    const h = kinds => kinds.map(kind => ({ kind }));
    assert.equal(historySummary(h(['ok', 'ok', 'ok'])), '3/3 ok');
    assert.equal(historySummary(h(['ok', 'failed', 'warning', 'ok'])), '2/4 ok · 2 failed');
    assert.equal(historySummary(h(['ok', 'running'])), '1/2 ok');
    assert.equal(historySummary([]), 'no runs');
    assert.equal(historySummary(undefined), 'no runs');
});

const auth = loadQmlJs('format.js', ['authHeader', 'requestError']);

test('authHeader builds Basic / Bearer headers, empty when off or incomplete', () => {
    const b64 = s => Buffer.from(s, 'utf8').toString('base64');
    assert.equal(auth.authHeader('basic', 'tester', 's3cret', '', b64), 'Basic dGVzdGVyOnMzY3JldA==');
    assert.equal(auth.authHeader('token', '', '', 'abc123', b64), 'Bearer abc123');
    assert.equal(auth.authHeader('token', '', '', '  abc123 \n', b64), 'Bearer abc123');
    assert.equal(auth.authHeader('none', 'u', 'p', 't', b64), '');
    assert.equal(auth.authHeader('basic', '', 'p', '', b64), '');
    assert.equal(auth.authHeader('token', '', '', '', b64), '');
    assert.equal(auth.authHeader(undefined, '', '', '', b64), '');
});

test('requestError explains a failed request', () => {
    assert.equal(auth.requestError(0, 'http://x'), 'Dagu not reachable at http://x.');
    assert.equal(auth.requestError(401, 'http://x'), 'Dagu rejected the credentials (HTTP 401). Check the widget settings.');
    assert.equal(auth.requestError(403, 'http://x'), 'Dagu rejected the credentials (HTTP 403). Check the widget settings.');
    assert.equal(auth.requestError(500, 'http://x'), 'Dagu returned HTTP 500.');
    assert.equal(auth.requestError(200, 'http://x'), '');
});

test('walletKey identifies the secret per mode, server and user', () => {
    const { walletKey } = loadQmlJs('format.js', ['walletKey']);
    assert.equal(walletKey('basic', 'http://localhost:8085/', 'tester'), 'basic tester@http://localhost:8085');
    assert.equal(walletKey('token', 'http://localhost:8085', 'ignored'), 'token @http://localhost:8085');
    assert.equal(walletKey('none', 'http://x', 'u'), '');
    assert.equal(walletKey('basic', 'http://x', ''), '');
});
