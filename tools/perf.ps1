# Sums up the "[parcel_delivery] perf" lines of the game log (written by the game script every 60 s of game time), to
# compare the optimizations. The update runs in several Lua states (the simulation threads of the game), each writes its
# own lines: they are added up over the real time the lines cover (the time stamps of the log).
#   (no parameter): the summary of the current log
#   -Save <name>:   also stores it as perf\<name>.csv (e.g. -Save 0-baseline)
#   -Compare:       the stored summaries side by side
#   -Log <path>:    another log file
# Usage: powershell -ExecutionPolicy Bypass -File tools\perf.ps1 [-Save <name>] [-Compare] [-Log <path>]
param(
    [string]$Save,
    [switch]$Compare,
    [string]$Log
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$perfDir = Join-Path $project "perf"

if ($Compare) {
    $files = Get-ChildItem $perfDir -Filter *.csv -ErrorAction SilentlyContinue | Sort-Object Name
    if (-not $files) { throw "no stored summaries in $perfDir" }
    $table = [ordered]@{}
    foreach ($file in $files) {
        foreach ($row in Import-Csv $file.FullName) {
            if (-not $table.Contains($row.Metric)) { $table[$row.Metric] = [ordered]@{ Metric = $row.Metric } }
            $table[$row.Metric][$file.BaseName] = $row.Value
        }
    }
    $table.Values | ForEach-Object { [pscustomobject]$_ } | Format-Table -AutoSize
    return
}

if (-not $Log) {
    $steam = (Get-ItemProperty "HKCU:\Software\Valve\Steam").SteamPath
    $Log = Get-ChildItem (Join-Path $steam "userdata") -Directory |
        ForEach-Object { Join-Path $_.FullName "3493540\local\crash_dump\stdout.txt" } |
        Where-Object { Test-Path $_ } | Select-Object -First 1
}
$lines = Select-String -Path $Log -Pattern "\[parcel_delivery\] perf " -Encoding UTF8 | ForEach-Object { $_.Line }
if (-not $lines) { throw "no perf lines in $Log" }

$first = $null; $last = $null
$updates = 0; $totalMs = 0.0; $longest = 0.0
$parts = [ordered]@{}   # part -> runs, total ms, longest ms
$counts = [ordered]@{}  # name -> values
foreach ($line in $lines) {
    if ($line -match "^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)Z") {
        $time = [datetime]::ParseExact($Matches[1], "yyyy-MM-dd HH:mm:ss", $null)
        if ($null -eq $first -or $time -lt $first) { $first = $time }
        if ($null -eq $last -or $time -gt $last) { $last = $time }
    }
    $text = $line.Substring($line.IndexOf("perf "))
    if ($text -match "total=([\d.]+)ms") { $totalMs += [double]$Matches[1] }
    foreach ($m in [regex]::Matches($text, "(\w+)=(\d+)x/([\d.]+)ms/([\d.]+)ms")) {
        $part = $m.Groups[1].Value
        $runs = [double]$m.Groups[2].Value
        if (-not $parts.Contains($part)) { $parts[$part] = @(0.0, 0.0, 0.0) }
        $parts[$part][0] += $runs
        $parts[$part][1] += $runs * [double]$m.Groups[3].Value
        $parts[$part][2] = [math]::Max($parts[$part][2], [double]$m.Groups[4].Value)
    }
    $tail = $text.Substring($text.LastIndexOf("|") + 1)
    foreach ($m in [regex]::Matches($tail, "(\w+)=(\d+)")) {
        $name = $m.Groups[1].Value
        if (-not $counts.Contains($name)) { $counts[$name] = New-Object System.Collections.Generic.List[double] }
        $counts[$name].Add([double]$m.Groups[2].Value)
    }
}
# the lines are written at the end of their period: the first one covers about a minute before its time stamp
$realS = [math]::Max(1, ($last - $first).TotalSeconds + 60)
$minutes = $realS / 60

$rows = New-Object System.Collections.Generic.List[object]
function Add-Row([string]$metric, [double]$value) { $rows.Add([pscustomobject]@{ Metric = $metric; Value = [math]::Round($value, 3) }) }
Add-Row "real minutes" $minutes
Add-Row "perf lines" $lines.Count
Add-Row "script ms per real s" ($totalMs / $realS)
Add-Row "script share %" ($totalMs / ($realS * 1000) * 100)
foreach ($part in $parts.Keys) {
    $p = $parts[$part]
    Add-Row "$part runs per min" ($p[0] / $minutes)
    Add-Row "$part avg ms" ($p[1] / [math]::Max(1, $p[0]))
    Add-Row "$part max ms" $p[2]
    Add-Row "$part ms per min" ($p[1] / $minutes)
}
foreach ($name in $counts.Keys) { Add-Row "count $name" (($counts[$name] | Measure-Object -Maximum).Maximum) }

Write-Output ("{0} perf lines, {1:N1} real minutes ({2} - {3} UTC), {4}" -f $lines.Count, $minutes, $first, $last, $Log)
$rows | Format-Table -AutoSize

if ($Save) {
    New-Item -ItemType Directory -Force $perfDir | Out-Null
    $rows | Export-Csv (Join-Path $perfDir "$Save.csv") -NoTypeInformation -Encoding UTF8
    Write-Output "Saved perf\$Save.csv"
}
