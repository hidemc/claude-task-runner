# claude-task-runner

Run Claude Code on a schedule on Windows — and **always find out when a run fails, and why.**

Task Scheduler only sees how the wrapper process ended. A `claude -p` run whose login had expired stopped after 0.2 seconds, and Task Scheduler still said *"The operation completed successfully"*. This runner reads Claude's own final `result` line instead, and tells you what actually happened.

## What it does

- Runs `claude -p` once with a prompt file and **only the tools you allow** (default: `Read,Glob,Grep,Write,Edit` — nobody is watching a scheduled run)
- Logs every run as one line in `logs\runs.csv`: status, exit code, cost (USD equivalent), turns, seconds
- Status is one of **OK / LOGIN / LIMIT / TIMEOUT / ERROR / SKIPPED**, taken from the `stream-json` result line, not from the exit code
- On failure: a Windows notification with what to do next, and a line in `logs\failed.txt`
- After a usage-limit failure, later runs of the same task **wait** (`-LimitCooldownHours`, default 6) instead of hitting the limit again and again
- `Register-ClaudeTask.ps1` adds it to Task Scheduler: runs as you, starts late if the PC was off, no console window (`conhost --headless`)

Plain Windows PowerShell 5.1. No modules, nothing to install besides Claude Code.

## Requirements

- Windows 10 (1809+) or 11
- Claude Code installed and logged in once in a normal terminal

## Quick start

1. Put this folder anywhere, e.g. `C:\work\runner`.
2. Run it once by hand from a normal PowerShell window:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\work\runner\Run-ClaudeTask.ps1 `
  -Name DailyNote -PromptFile C:\work\runner\prompts\example-daily-note.md -WorkDir C:\work
```

3. Check that `logs\runs.csv` got an `OK` line.
4. Register it (add `-DryRun` first to see what would be registered):

```powershell
C:\work\runner\Register-ClaudeTask.ps1 -Name DailyNote `
  -PromptFile C:\work\runner\prompts\example-daily-note.md -WorkDir C:\work -Time 09:00
```

Remove it with `Register-ClaudeTask.ps1 -Name DailyNote -Remove`.

Note: run it from a normal PowerShell window, not by asking Claude inside a Claude Code conversation — that ends as `ERROR` ("Claude Code cannot be launched inside another Claude Code session").

## Options (Run-ClaudeTask.ps1)

| Option | Default | Meaning |
|---|---|---|
| `-Model` | `sonnet` | Model for the run |
| `-MaxTurns` | `40` | Stop after this many turns |
| `-AllowedTools` | `Read,Glob,Grep,Write,Edit` | The only tools the run can use |
| `-TimeoutMinutes` | `30` | Kill the run after this long (status `TIMEOUT`) |
| `-LimitCooldownHours` | `6` | Skip runs for this long after a `LIMIT` |
| `-NoToast` | off | No Windows notification |
| `-ClaudePath` | auto | Path to `claude.exe` / `claude.cmd` if it is not found |

## Example log

```
date,start,name,status,exit,cost_usd,turns,seconds,note
2026-10-20,09:00,DailyNote,OK,0,0.412,9,48,
2026-10-21,09:00,DailyNote,LOGIN,1,0,1,0,Failed to authenticate: OAuth session expired ...
```

Cost is the USD equivalent Claude Code reports. On a subscription plan it is not what you are billed.

## The full kit

This runner is one part of the **Claude Code Workshop Kit for Windows** — the workspace I use every day: an entry-only `CLAUDE.md` with a file catalog, a one-line-per-fact memory pattern, 2 hooks that warn when `CLAUDE.md` / `MEMORY.md` grow too big or a conversation gets long, 2 skills, a privacy checker for anything you publish, and an installer.

→ https://hidemc.gumroad.com/l/claude-code-workshop-kit

## License

MIT (this repository). Not affiliated with or endorsed by Anthropic. "Claude" and "Claude Code" are used only to describe what this works with.
