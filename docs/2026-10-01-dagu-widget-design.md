# Dagu Desktop Widget — Design

Date: 2026-10-01

## Goal

A KDE Plasma 6 widget that shows, at a glance, the Dagu workflows running on this
machine: each DAG's schedule, next run, and last run status. Read-only. Clicking
opens the Dagu web UI for details.

Environment: KDE Plasma 6.6 (Wayland), Dagu 1.30.3 running as a user systemd
service on `http://localhost:8085`.

## Non-goals

- Starting, stopping or suspending DAGs (use the Dagu web UI).
- Showing logs or step-level detail.
- Supporting remote Dagu servers with authentication.

## Layout

```
┌─ Dagu ───────────────────── ● 8085 ─┐
│ ✔ gd-daily-report     next 13:00    │
│   0 1/6 * * *         last 08:44 3m │
│ ✔ gd-sentry-digest    next tmrw 08:00│
│ ✖ gd-partial-backup   next 09:30    │
│   ⏸ suspended                       │
└─────────────────────────────────────┘
```

- Desktop: full list shown directly.
- Panel: compact icon; list opens as a popup on click.
- Compact icon colour: green when all last runs succeeded, red when any last run
  failed, blue when any DAG is running, grey when Dagu is unreachable.

## Components

| File | Purpose |
|---|---|
| `package/metadata.json` | Plasmoid metadata (id `org.maros.daguwidget`, Plasma 6 API). |
| `package/contents/ui/main.qml` | Root item: polling timer, data model, compact and full representations. |
| `package/contents/ui/DagRow.qml` | One DAG row: status icon, name, schedule, next run, last run + duration. |
| `package/contents/ui/configGeneral.qml` | Settings page: server URL, refresh interval. |
| `package/contents/config/main.xml` | Config schema (`serverUrl` default `http://localhost:8085`, `refreshSeconds` default 30). |
| `package/contents/config/config.qml` | Registers the settings page. |
| `package/contents/code/cron.js` | Pure JS cron parser + `nextRun(expr, fromDate)`. |
| `package/contents/code/format.js` | Pure JS helpers: relative time, durations, status → icon/colour. |
| `test/cron.test.mjs`, `test/format.test.mjs` | Node unit tests for the pure JS modules. |
| `install.sh` | `kpackagetool6 -t Plasma/Applet -i` or `-u` when already installed. |

## Data flow

1. A `Timer` fires every `refreshSeconds` (and once at load).
2. `XMLHttpRequest` GET `<serverUrl>/api/v2/dags`.
3. For each entry in `dags[]`, the widget reads `dag.name`, `dag.schedule[].expression`,
   `suspended`, `latestDAGRun.statusLabel`, `startedAt` and `finishedAt`.
4. `nextRun` is computed locally from each schedule expression (earliest across
   expressions). The Dagu API does not return it. Suspended DAGs show "suspended"
   in place of a next run.
5. The model is replaced with the new list; the view re-renders.

## Cron parser scope

- 5 fields: minute, hour, day-of-month, month, day-of-week.
- Syntax per field: `*`, `n`, `a-b`, `a,b,c`, `*/n`, `a/n`, `a-b/n`.
- Day-of-month and day-of-week follow standard cron OR semantics when both are
  restricted.
- Local time zone. Search steps forward minute by minute for up to 366 days;
  returns `null` if nothing matches.
- Unsupported expressions (e.g. `@daily`, 6-field) return `null`; the row shows
  the raw expression without a next run.

## Interaction

- Click a row: `Qt.openUrlExternally("<serverUrl>/dags/<fileName>")`.
- Click the header: opens `<serverUrl>`.

## Error handling

- Network error or non-200: show "Dagu not reachable" banner; keep the last known
  list, dimmed, with the time of the last successful fetch. Icon goes grey.
- Malformed JSON: treated the same as a network error.
- `errors` non-empty for a DAG: row shows a warning icon with the error as tooltip.

## Testing

- `node --test test/` for `cron.js` and `format.js`, including the three real
  schedules (`0 1/6 * * *`, `0 8 * * *`, `30 9 * * *`) and edge cases (month
  rollover, DOM/DOW OR rule, unsupported expressions).
- Manual: install with `install.sh`, add to desktop and panel, check
  each state. Stop `dagu.service` to verify the unreachable state.
- `plasmoidviewer` (package `plasma-sdk`) is not installed; optional for faster
  iteration.

## Repository

Standalone repo at `~/Projects/dagu-widget`, branch `main`. No remote yet.
