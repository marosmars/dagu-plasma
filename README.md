# dagu-plasma

KDE Plasma 6 widget showing local [Dagu](https://github.com/dagu-org/dagu) workflows:
schedule, next run, and last run status. Click a row to open it in the Dagu web UI.

- On the desktop (or any size above ~14×6 grid units) it shows the list.
- In a panel it shows an icon with a status dot: green = all OK, red = a last run
  failed, blue = something running, grey = Dagu unreachable.

Reads `GET <serverUrl>/api/v2/dags` and computes next runs locally from the cron
expressions.

## Settings

Right-click the widget → *Configure Dagu Workflows…*

| Setting | Default |
|---|---|
| Dagu server URL | `http://localhost:8085` |
| Refresh interval | 30 s |
| Workflows to show | all |
| Sort by | name (or next run, or status with failures first) |
| Compact layout (one line per workflow) | off |
| Show cron schedule / last run duration | on / on |
| Time format | 24-hour |
| Notify when a run fails | on |

## Install

```bash
./install.sh                              # install or upgrade
plasmawindowed org.maros.daguwidget       # try it in a window
```

Then right-click the desktop or panel → *Add Widgets…* → **Dagu Workflows**.

## Test

```bash
node --test 'test/*.test.mjs'
```
