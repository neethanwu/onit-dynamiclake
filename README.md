<p align="center">
  <img src="Package/Onit.dynamiclakeplugin/icon.png" width="96" alt="onit icon">
</p>

<h1 align="center">onit for DynamicLake</h1>

<p align="center">
  everything your mac does on a schedule, in <a href="https://dynamiclake.com">DynamicLake</a>'s notch.
</p>

This is [onit](https://github.com/neethanwu/onit) as a DynamicLake plugin. It reads your launchd agents and crontab entries the same way onit does, and shows them with DynamicLake's own live activity, sneak peek and lake.

## What it shows

- **Only when there's something to say.** A task running, one that just finished, one that didn't finish, or a schedule that runs more than you think. When all is well the notch stays yours. Turn on **Show the Next Run** if you want a quiet countdown anyway.
- **Failures, explained.** The sneak peek opens for a moment when a task fails and says why in plain words ("A file or folder it needs is missing"), with a button to try again.
- **The full list in the lake.** Every task with its schedule in words and when it runs next. Click a task for its detail: what went wrong, the schedule, recent runs, and Run Now, Pause, Copy for Your Agent and Open Log.
- **Drag a fix to your agent.** Drag a failing task out of the lake and drop it into Claude Code, Codex or any chat: you get a ready prompt with the task's definition, schedule, exit code and the end of its log.
- **Right-click a task** to run it, pause it, copy the fix prompt, open its log, show its plist in Finder, or hide it.
- **DynaGlance.** onit has a button in the DynaGlance pill with the headline and the next three tasks.
- **Bead.** onit's little character, drawn frame by frame: it blinks, hops when something needs a look, shivers and sweats when something failed, and runs while the lake is open and a task is running.

## Install

1. Download `Onit-x.y.z.zip` from the [latest release](https://github.com/neethanwu/onit-dynamiclake/releases/latest) and unzip it.
2. In DynamicLake, open **Settings › Plugins › Install Local** and choose `Onit.dynamiclakeplugin`.

Needs DynamicLake with plugin lakes (Pro 2.0 or later) on macOS 14 or later.

**Using the onit app too?** Both live in the notch. Switch onit to the menu bar from its ··· menu so they don't overlap.

## What it reads

The same as onit, and nothing leaves your Mac. It never edits your plists or your crontab.

| Source | What it uses it for |
| --- | --- |
| `~/Library/LaunchAgents/*.plist` | Your launchd agents: label, program, schedule, log paths |
| `launchctl list`, `launchctl print`, `launchctl print-disabled` | Whether each agent is loaded, running or paused, its last exit code and run count |
| `crontab -l` | Your cron entries |
| The unified log | Recent runs from before the plugin started |
| Each task's log file | The last lines, to explain a failure |

Actions use `launchctl kickstart`, `disable` / `bootout` and `enable` / `bootstrap` in your own user domain. Run history and hidden tasks are kept in `~/Library/Application Support/onit-dynamiclake/`, separate from the onit app. A log of what DynamicLake refused, if anything, is in `~/Library/Logs/onit-dynamiclake.log`.

## Development

```bash
make            # universal binary + dist/Onit.dynamiclakeplugin
make zip        # dist/Onit-x.y.z.zip for DynamicLake Market, with its SHA-256
make demo       # print what the plugin would send for the tasks on this Mac
make test       # unit tests
make bead       # redraw Bead's frames (Tools/render-bead.swift)
make icon       # redraw the icon (Tools/render-icon.swift)
Tools/test-agent.sh          # install a throwaway agent that runs, succeeds and fails
Tools/test-agent.sh remove   # and remove it
```

After a change, reinstall the package in DynamicLake: it checks the files haven't changed since install.

```
Sources/OnitLake/
  Onit/      Copied from onit: launchd and cron scanning, schedule words, failure reasons, fix prompts
  Lake/      The DynamicLake socket, JSON and component builders
  Plugin/    Store, Bead's frame player, and the presenter that turns state into surfaces
Package/Onit.dynamiclakeplugin/
             plugin.json, icon and Bead's frames; make adds the binary
```

The code in `Sources/OnitLake/Onit` is copied from onit rather than shared, so the two can change on their own.

## License

MIT
