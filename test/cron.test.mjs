import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadQmlJs } from './load.mjs';

const { parseCron, nextRun, nextRunAny } = loadQmlJs('cron.js', ['parseCron', 'nextRun', 'nextRunAny']);

// Local-time helper: d(2026, 10, 1, 10, 40) = 2026-10-01 10:40 local
const d = (y, mo, day, h, mi) => new Date(y, mo - 1, day, h, mi, 0, 0);

test('hour step from offset: 0 1/6 * * *', () => {
    assert.deepEqual(nextRun('0 1/6 * * *', d(2026, 10, 1, 10, 40)), d(2026, 10, 1, 13, 0));
    assert.deepEqual(nextRun('0 1/6 * * *', d(2026, 10, 1, 19, 0)), d(2026, 10, 2, 1, 0));
});

test('daily fixed time rolls to tomorrow once passed', () => {
    assert.deepEqual(nextRun('0 8 * * *', d(2026, 10, 1, 10, 40)), d(2026, 10, 2, 8, 0));
    assert.deepEqual(nextRun('30 9 * * *', d(2026, 10, 1, 9, 29)), d(2026, 10, 1, 9, 30));
});

test('strictly after the reference minute', () => {
    assert.deepEqual(nextRun('30 9 * * *', d(2026, 10, 1, 9, 30)), d(2026, 10, 2, 9, 30));
});

test('month and year rollover', () => {
    assert.deepEqual(nextRun('0 0 1 * *', d(2026, 12, 15, 0, 0)), d(2027, 1, 1, 0, 0));
});

test('ranges, lists and stepped ranges', () => {
    // weekdays 9-17 every 2h on :15 -> from Fri 2026-10-02 17:20 next is Mon 09:15
    assert.deepEqual(nextRun('15 9-17/2 * * 1-5', d(2026, 10, 2, 17, 20)), d(2026, 10, 5, 9, 15));
    assert.deepEqual(nextRun('0,30 * * * *', d(2026, 10, 1, 10, 5)), d(2026, 10, 1, 10, 30));
    assert.deepEqual(nextRun('*/15 * * * *', d(2026, 10, 1, 10, 46)), d(2026, 10, 1, 11, 0));
});

test('day-of-week 7 means Sunday', () => {
    // 2026-10-04 is a Sunday
    assert.deepEqual(nextRun('0 12 * * 7', d(2026, 10, 1, 0, 0)), d(2026, 10, 4, 12, 0));
});

test('DOM and DOW both restricted use OR semantics', () => {
    // 15th of month OR Monday; from Thu 2026-10-01 the next Monday is 10-05
    assert.deepEqual(nextRun('0 0 15 * 1', d(2026, 10, 1, 0, 0)), d(2026, 10, 5, 0, 0));
});

test('unsupported or invalid expressions return null', () => {
    for (const expr of ['@daily', '0 0 * * * *', '61 * * * *', 'x * * * *', '', '0 0 31 2 *']) {
        assert.equal(nextRun(expr, d(2026, 10, 1, 0, 0)), null, expr);
    }
    assert.equal(parseCron('@daily'), null);
});

test('nextRunAny picks the earliest of several schedules', () => {
    assert.deepEqual(nextRunAny(['0 8 * * *', '0 12 * * *'], d(2026, 10, 1, 10, 0)), d(2026, 10, 1, 12, 0));
    assert.equal(nextRunAny([], d(2026, 10, 1, 10, 0)), null);
    assert.equal(nextRunAny(['@daily'], d(2026, 10, 1, 10, 0)), null);
});
