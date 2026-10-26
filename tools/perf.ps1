# Sums up the "[parcel_delivery] perf" lines of the game log (written by the game script every 60 s of game time), to
# compare the optimizations.
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

# per metric: the values of all lines
$values = [ordered]@{}
function Add-Value([string]$metric, [double]$value) {
    if (-not $values.Contains($metric)) { $values[$metric] = New-Object System.Collections.Generic.List[double] }
    $values[$metric].Add($value)
}
foreach ($line in $lines) {
    $text = $line.Substring($line.IndexOf("perf "))
    if ($text -match "real=([\d.]+)s") { Add-Value "real s" $Matches[1] }
    if ($text -match "frames=(\d+)") { Add-Value "frames" $Matches[1] }
    if ($text -match "total=([\d.]+)ms") { Add-Value "total ms" $Matches[1] }
    if ($text -match "share=([\d.]+)%") { Add-Value "share %" $Matches[1] }
    foreach ($m in [regex]::Matches($text, "(\w+)=(\d+)x/([\d.]+)ms/([\d.]+)ms")) {
        $part = $m.Groups[1].Value
        Add-Value "$part runs" $m.Groups[2].Value
        Add-Value "$part avg ms" $m.Groups[3].Value
        Add-Value "$part max ms" $m.Groups[4].Value
    }
    $counts = $text.Substring($text.LastIndexOf("|") + 1)
    foreach ($m in [regex]::Matches($counts, "(\w+)=(\d+)")) { Add-Value "count $($m.Groups[1].Value)" $m.Groups[2].Value }
}

# the average of every metric over the lines, the largest for the longest times
$rows = foreach ($metric in $values.Keys) {
    $list = $values[$metric]
    $value = if ($metric -like "* max ms") { ($list | Measure-Object -Maximum).Maximum } else { ($list | Measure-Object -Average).Average }
    [pscustomobject]@{ Metric = $metric; Value = [math]::Round($value, 3) }
}
Write-Output ("{0} perf lines from {1}" -f $lines.Count, $Log)
$rows | Format-Table -AutoSize

if ($Save) {
    New-Item -ItemType Directory -Force $perfDir | Out-Null
    $rows | Export-Csv (Join-Path $perfDir "$Save.csv") -NoTypeInformation -Encoding UTF8
    Write-Output "Saved perf\$Save.csv"
}
