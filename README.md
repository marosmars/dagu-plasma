# dagu-plasma

KDE Plasma 6 widget showing local [Dagu](https://github.com/dagu-org/dagu) workflows:
schedule, next run, and last run status. Click a row to open it in the Dagu web UI.

- On the desktop (or any size above ~14×6 grid units) it shows the list.
- In a panel it shows an icon with a status dot: green = all OK, red = a last run
  failed, blue = something running, grey = Dagu unreachable.

Reads `GET <serverUrl>/api/v2/dags` (default `http://localhost:8085`, every 30 s;
both configurable). Next runs are computed locally from the cron expressions.

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
