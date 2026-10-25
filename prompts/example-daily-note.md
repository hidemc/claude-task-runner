# Daily note (example prompt for a scheduled run)

You are running as a scheduled job. Nobody is watching. Do the following once and stop.

## Allowed and not allowed
- You may read anything inside this work folder.
- You may write only inside `daily/`. Do not change any other file.
- Do not send, publish, delete or pay (you have not been given tools for that).
- If unsure, do not widen the task: write what you were unsure about at the end of the note and stop.

## Task
1. List the files in this folder that changed in the last 24 hours (name and one line on what changed, if you can tell).
2. If `logs/failed.txt` next to the runner has lines from yesterday or today, copy them.
3. Write `daily/YYYY-MM-DD.md` (today's date) in this form:

```
# Daily YYYY-MM-DD
- Changed files: (one line each, or "none")
- Failed scheduled runs: none / (copied lines)
```

4. Print the name of the file you wrote on the last line and stop.
