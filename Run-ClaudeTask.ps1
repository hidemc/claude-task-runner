# Run-ClaudeTask.ps1  (claude-task-runner v1.0)
# Runs Claude Code once in headless mode (claude -p) with a prompt file.
# - Only the tools in -AllowedTools can be used (nobody is watching a scheduled run).
# - Every run is one line in logs\runs.csv (status, exit code, cost in USD, turns, seconds).
# - A failed run (login expired / usage limit / timeout / other) shows a Windows
#   notification and is appended to logs\failed.txt, so it never fails silently.
# - After a usage-limit failure, later runs of the same task are skipped for
#   -LimitCooldownHours instead of hitting the limit again and again.
# Comments and strings are ASCII only (Windows PowerShell 5.1 misreads UTF-8 without BOM).
#
# Example:
#   powershell -NoProfile -ExecutionPolicy Bypass -File Run-ClaudeTask.ps1 `
#     -Name DailyNote -PromptFile C:\work\prompts\daily-note.md -WorkDir C:\work
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$PromptFile,
    [string]$WorkDir = '',
    [string]$Model = 'sonnet',
    [int]$MaxTurns = 40,
    [string[]]$AllowedTools = @('Read', 'Glob', 'Grep', 'Write', 'Edit'),
    [int]$TimeoutMinutes = 30,
    [int]$LimitCooldownHours = 6,
    [switch]$NoToast,
    [string]$ClaudePath = '',
    [string]$LogDir = (Join-Path $PSScriptRoot 'logs')
)

$ErrorActionPreference = 'Stop'

function Find-Claude {
    # Only a real program (.exe / .cmd); an npm install also puts a claude.ps1 first on PATH
    $cmd = Get-Command claude -CommandType Application -All -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -match '\.(exe|cmd)$' } | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $pats = @(
        (Join-Path $env:USERPROFILE '.local\bin\claude.exe'),
        (Join-Path $env:APPDATA 'npm\claude.cmd'),
        (Join-Path $env:USERPROFILE '.vscode\extensions\anthropic.claude-code-*\resources\native-binary\claude.exe')
    )
    foreach ($p in $pats) {
        $found = Get-ChildItem -Path $p -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if ($found) { return $found[0].FullName }
    }
    throw 'claude was not found. Install Claude Code and log in once in a normal terminal.'
}

function Show-Toast([string]$title, [string]$text) {
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        $t = [Security.SecurityElement]::Escape($title)
        $b = [Security.SecurityElement]::Escape($text)
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml("<toast><visual><binding template='ToastGeneric'><text>$t</text><text>$b</text></binding></visual></toast>")
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show(
            [Windows.UI.Notifications.ToastNotification]::new($xml))
    } catch { }
}

function Write-Run($row) {
    $csv = Join-Path $LogDir 'runs.csv'
    if (-not (Test-Path $csv)) {
        Add-Content -Path $csv -Encoding UTF8 -Value 'date,start,name,status,exit,cost_usd,turns,seconds,note'
    }
    $note = ($row.note -replace '[\r\n,"]', ' ')
    if ($note.Length -gt 200) { $note = $note.Substring(0, 200) }
    $line = '{0},{1},{2},{3},{4},{5},{6},{7},{8}' -f $row.date, $row.start, $Name, $row.status, $row.exit,
        $row.cost, $row.turns, $row.seconds, $note
    Add-Content -Path $csv -Encoding UTF8 -Value $line
}

# -AllowedTools may arrive as one string "Read,Glob" when called with -File
$tools = @($AllowedTools | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if (-not $WorkDir) { $WorkDir = Split-Path -Parent (Resolve-Path $PromptFile) }
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
$now = Get-Date
$row = @{ date = $now.ToString('yyyy-MM-dd'); start = $now.ToString('HH:mm'); status = ''; exit = '';
          cost = ''; turns = ''; seconds = ''; note = '' }

# Skip while a recent usage-limit failure of this task is still cooling down
$csvPath = Join-Path $LogDir 'runs.csv'
if ((Test-Path $csvPath) -and $LimitCooldownHours -gt 0) {
    $last = Import-Csv $csvPath -Encoding UTF8 | Where-Object { $_.name -eq $Name -and $_.status -ne 'SKIPPED' } |
        Select-Object -Last 1
    if ($last -and $last.status -eq 'LIMIT') {
        $at = [datetime]::ParseExact($last.date + ' ' + $last.start, 'yyyy-MM-dd HH:mm', $null)
        if (($now - $at).TotalHours -lt $LimitCooldownHours) {
            $row.status = 'SKIPPED'; $row.note = 'usage limit at ' + $last.date + ' ' + $last.start
            Write-Run $row
            exit 0
        }
    }
}

$stamp = $now.ToString('yyyyMMdd-HHmmss')
$outFile = Join-Path $LogDir ($Name + '_' + $stamp + '.jsonl')
$errFile = Join-Path $LogDir ($Name + '_' + $stamp + '.err.txt')
$argList = @('-p', '--model', $Model, '--max-turns', $MaxTurns, '--output-format', 'stream-json', '--verbose',
             '--allowedTools') + $tools

$err = ''
$timedOut = $false
try {
    $claude = if ($ClaudePath) { $ClaudePath } else { Find-Claude }
    $p = Start-Process -FilePath $claude -ArgumentList $argList -WorkingDirectory $WorkDir -NoNewWindow -PassThru `
        -RedirectStandardInput (Resolve-Path $PromptFile) -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $null = $p.Handle  # without this, ExitCode stays empty in Windows PowerShell 5.1
    $timedOut = -not $p.WaitForExit($TimeoutMinutes * 60 * 1000)
    if ($timedOut) { try { $p.Kill() } catch { } }
    $row.exit = if ($timedOut) { 'timeout' } else { $p.ExitCode }
} catch {
    $err = 'could not start claude: ' + $_.Exception.Message
    $row.exit = 'start'
}
$row.seconds = [int]((Get-Date) - $now).TotalSeconds

# The last "result" line of stream-json carries cost, turns and the error text
foreach ($l in (Get-Content $outFile -Encoding UTF8 -ErrorAction SilentlyContinue)) {
    if ($l -notmatch '"type"\s*:\s*"result"') { continue }
    try { $o = $l | ConvertFrom-Json } catch { continue }
    if ($null -ne $o.total_cost_usd) { $row.cost = [math]::Round([double]$o.total_cost_usd, 4) }
    $row.turns = $o.num_turns
    if ($o.is_error) { $err = [string]$o.result; if (-not $err) { $err = [string]$o.subtype } }
}
if (-not $err -and (Test-Path $errFile)) {
    $e = (Get-Content $errFile -Raw -ErrorAction SilentlyContinue)
    if ($e -and $row.exit -ne 0) { $err = $e.Trim() }
}

if ($timedOut) { $row.status = 'TIMEOUT'; $err = 'no answer in ' + $TimeoutMinutes + ' minutes' }
elseif ($err -match 'authenticat|oauth|log ?in|credential') { $row.status = 'LOGIN' }
elseif ($err -match 'hit your .*limit|weekly limit|usage limit|session limit|rate limit|limit reached|resets at') { $row.status = 'LIMIT' }
elseif ($err -or $row.exit -ne 0) { $row.status = 'ERROR'; if (-not $err) { $err = 'exit ' + $row.exit } }
else { $row.status = 'OK' }
$row.note = $err
Write-Run $row
if ((Test-Path $errFile) -and (Get-Item $errFile).Length -eq 0) { Remove-Item $errFile }

if ($row.status -ne 'OK') {
    $hint = switch ($row.status) {
        'LOGIN'   { 'Claude login expired. Open Claude Code once and log in again.' }
        'LIMIT'   { 'Plan usage limit reached. Later runs wait ' + $LimitCooldownHours + ' h.' }
        'TIMEOUT' { 'No answer in time. See the .jsonl log.' }
        default   { 'Failed. See logs\failed.txt.' }
    }
    $msg = '{0} {1} [{2}] {3} | {4}' -f $row.date, $row.start, $row.status, $Name, ($err -replace '\s+', ' ')
    Add-Content -Path (Join-Path $LogDir 'failed.txt') -Encoding UTF8 -Value $msg
    if (-not $NoToast) { Show-Toast ('Claude task stopped: ' + $Name) $hint }
    exit 1
}
exit 0
