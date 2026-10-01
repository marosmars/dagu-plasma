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
        status: 'not_started', kind: 'none', startedAt: '', finishedAt: '', error: 'bad yaml',
    });
    assert.deepEqual(rows[1], {
        name: 'zeta', fileName: 'zeta', schedules: ['0 8 * * *'], suspended: true,
        status: 'failed', kind: 'failed', startedAt: '2026-10-01T08:00:00+02:00',
        finishedAt: '2026-10-01T08:01:00+02:00', error: '',
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
