# Register-ClaudeTask.ps1  (claude-task-runner v1.0)
# Registers (or removes) a Windows Task Scheduler task that calls Run-ClaudeTask.ps1
# at a fixed time. The task runs as you, only while you are logged on (Claude Code
# needs your login), and starts late if the PC was off at the planned time.
# Comments and strings are ASCII only (Windows PowerShell 5.1 misreads UTF-8 without BOM).
#
# Examples:
#   .\Register-ClaudeTask.ps1 -Name DailyNote -PromptFile C:\work\prompts\daily-note.md -WorkDir C:\work -Time 09:00
#   .\Register-ClaudeTask.ps1 -Name DailyNote -Remove
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$PromptFile = '',
    [string]$WorkDir = '',
    [string]$Time = '09:00',
    [int]$EveryDays = 1,
    [string]$Model = 'sonnet',
    [int]$MaxTurns = 40,
    [string]$AllowedTools = 'Read,Glob,Grep,Write,Edit',
    [switch]$Remove,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$taskName = 'Claude - ' + $Name

if ($Remove) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host ('Removed: ' + $taskName)
    exit 0
}
if (-not $PromptFile -or -not (Test-Path $PromptFile)) { throw 'Give -PromptFile (an existing .md file).' }
$PromptFile = (Resolve-Path $PromptFile).Path
if (-not $WorkDir) { $WorkDir = Split-Path -Parent $PromptFile }

$runner = Join-Path $PSScriptRoot 'Run-ClaudeTask.ps1'
# conhost --headless keeps even the brief console flash off the screen (Windows 10 1809+ / 11)
$arg = ('--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}" -Name "{1}" -PromptFile "{2}" ' +
        '-WorkDir "{3}" -Model "{4}" -MaxTurns {5} -AllowedTools "{6}"') -f $runner, $Name, $PromptFile,
        $WorkDir, $Model, $MaxTurns, $AllowedTools

$action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument $arg -WorkingDirectory $WorkDir
$trigger = New-ScheduledTaskTrigger -Daily -DaysInterval $EveryDays -At $Time
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive

if ($DryRun) {
    Write-Host ('Task: ' + $taskName)
    Write-Host ('Run:  conhost.exe ' + $arg)
    Write-Host ('When: every ' + $EveryDays + ' day(s) at ' + $Time)
    exit 0
}
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings `
    -Principal $principal -Force | Out-Null
Write-Host ('Registered: ' + $taskName + ' every ' + $EveryDays + ' day(s) at ' + $Time)
Write-Host ('Try it now:  Start-ScheduledTask -TaskName "' + $taskName + '"')
