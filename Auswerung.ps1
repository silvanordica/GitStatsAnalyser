# q3_timeseries.ps1
# Zeitlicher Verlauf (täglich/wochenweise) + Totals je Autor aus bare repo

[Console]::OutputEncoding = [Text.Encoding]::UTF8

# ===== Konfiguration =====
$gitDir   = "C:\NET\working\Git\RS2.git"     # bare repo
$since    = "2025-07-01"
$until    = "2025-09-30 23:59:59"
$granularity = "Day"                         # "Day" oder "Week"

# Haupt-Branch-Präferenz (Reihenfolge)
$preferredBranches = @("origin/main","origin/master")

# Als "Code" werten:
$validExt = @(
  ".cs",
  ".ts",".tsx",".js",".jsx"#,
  #".css",".scss",
  #".xml"  # ggf. rausnehmen, falls zu laut
)

# Ordner ausschließen (Teilpfade, case-insensitive)
$skipDirs = @("bin","obj","dist","node_modules","wwwroot\lib","packages","generated","migrations")

# Ausgabedateien
$outCsvTimeseries = "C:\NET\working\Git\q3_lines_timeseries_filtered.csv"
$outCsvPerAuthor  = "C:\NET\working\Git\q3_lines_per_author_filtered.csv"

# Exakte Autoren (per E-Mail)
$authorEmails = @(
  "Pavol.Martiniak@aptean.com",
  "Sebastian.Arnauer@aptean.com",
  "Matthias.Kuehtreiber@aptean.com",
  "Peter.Erlsbacher@aptean.com",
  "Peter.Haubenburger@aptean.com",
  "Michaela.Prichocka@ezmid.com",
  "nnell@aptean.com",
  "Fabian.Rausch-Schott@aptean.com"
) | ForEach-Object { $_.ToLower() }
# =========================

function Get-ExistingBranches {
  param([string[]]$prefs)
  $allRefs = git --git-dir="$gitDir" show-ref --heads --remotes 2>$null
  $found = @()
  foreach ($p in $prefs) {
    if ($allRefs -match [regex]::Escape($p)) { $found += $p }
  }
  if ($found.Count -gt 0) { return $found }

  # Fallback: übliche Main-Refs
  $candidates = @()
  foreach ($line in $allRefs) {
    if ($line -match 'refs/remotes/.+') {
      $ref = ($line -split '\s+')[1]
      if ($ref -match '/(main|master|develop)$') { $candidates += $ref }
    }
  }
  if ($candidates.Count -gt 0) { return $candidates }

  return @("--all")
}

function Get-GroupKey([datetime]$dt, [string]$gran) {
  if ($null -eq $dt) { return $null }
  switch ($gran) {
    "Week" {
      $offset = (([int]$dt.DayOfWeek + 6) % 7)  # Montag als Start
      return $dt.Date.AddDays(-$offset).ToString("yyyy-MM-dd")
    }
    default { return $dt.Date.ToString("yyyy-MM-dd") }
  }
}

function Should-SkipPath([string]$path) {
  $p = $path -replace '/','\'  # normalisieren
  foreach ($d in $skipDirs) {
    if ($p.ToLower().Contains("\$($d.ToLower())\")) { return $true }
    if ($p.ToLower().EndsWith("\$($d.ToLower())")) { return $true }
  }
  return $false
}

# --- Branch-Auswahl
$branches = Get-ExistingBranches -prefs $preferredBranches
Write-Host "Analysiere Branch(es): $($branches -join ', ')"
$branchArgs = $branches

# --- Git-Args korrekt als Array bauen
$logArgs = @(
  "--since=$since","--until=$until",
  "--no-merges","--date=short",
  '--pretty=format:@%H|%ad|%an|%ae','--numstat'
)

$gitArgs = @("--git-dir=$gitDir","log")
if ($branchArgs -ne @("--all")) {
  $gitArgs += $branchArgs
  $gitArgs += "--first-parent"
} else {
  $gitArgs += "--all"
}
$gitArgs += $logArgs

# Git vorhanden?
$gitPath = (Get-Command git -ErrorAction SilentlyContinue).Path
if (-not $gitPath) { Write-Host "Git nicht gefunden (PATH prüfen)." -ForegroundColor Red; return }
Write-Host "Verwende Git: $gitPath"

# --- Log abrufen
$lines = & git @gitArgs 2>$null

# --- Aggregation vorbereiten
$aggByDay = @{}     # yyyy-mm-dd -> @{Added;Deleted}
$aggByAuthor = @{}  # email -> @{Added;Deleted;Commits}

$currentDate  = $null
$currentEmail = $null

foreach ($line in $lines) {
  if ($line.StartsWith("@")) {
    # Header: @<hash>|<date>|<author>|<email>
    $rest  = $line.Substring(1)
    $parts = $rest.Split("|",4,[System.StringSplitOptions]::None)
    if ($parts.Count -ge 4) {
      $dateStr = $parts[1].Trim()
      $email   = $parts[3].Trim().ToLower()
      try { $currentDate = [datetime]::ParseExact($dateStr, "yyyy-MM-dd", $null) } catch { $currentDate = $null }

      if ($authorEmails -contains $email) {
        $currentEmail = $email
        if (-not $aggByAuthor.ContainsKey($currentEmail)) { $aggByAuthor[$currentEmail] = @{Added=0;Deleted=0;Commits=0} }
        $aggByAuthor[$currentEmail].Commits += 1
      } else {
        $currentEmail = $null
      }
    } else {
      $currentDate = $null
      $currentEmail = $null
    }
    continue
  }

  # numstat: "<added> <deleted> <path>" (binär: '-' '-')
  $p = $line -split "\s+"
  if ($p.Length -ge 3 -and $p[0] -match '^\d+$' -and $p[1] -match '^\d+$') {
    if ($null -eq $currentDate)  { continue }
    if ($null -eq $currentEmail) { continue }

    $added   = [int]$p[0]
    $deleted = [int]$p[1]
    $path    = $p[2]

    $ext = [IO.Path]::GetExtension($path)
    if (-not ($validExt -contains $ext)) { continue }
    if (Should-SkipPath $path) { continue }

    $key = Get-GroupKey -dt $currentDate -gran $granularity
    if ($null -eq $key) { continue }

    if (-not $aggByDay.ContainsKey($key)) { $aggByDay[$key] = @{Added=0;Deleted=0} }
    $aggByDay[$key].Added   += $added
    $aggByDay[$key].Deleted += $deleted

    $aggByAuthor[$currentEmail].Added   += $added
    $aggByAuthor[$currentEmail].Deleted += $deleted
  }
}

# --- Zeitreihe (das ist dein zeitlicher Verlauf)
$cumAdd = 0; $cumDel = 0
$rows = @()
$sortedKeys = $aggByDay.Keys | Sort-Object { [datetime]::ParseExact($_, "yyyy-MM-dd", $null) }
foreach ($k in $sortedKeys) {
  $a = $aggByDay[$k].Added
  $d = $aggByDay[$k].Deleted
  $cumAdd += $a
  $cumDel += $d
  $rows += [pscustomobject]@{
    Date       = $k
    Added      = $a
    Deleted    = $d
    Net        = $a - $d
    CumAdded   = $cumAdd
    CumDeleted = $cumDel
    CumNet     = $cumAdd - $cumDel
  }
}

if ($rows.Count -gt 0) {
  $rows | Export-Csv -Path $outCsvTimeseries -NoTypeInformation -Encoding UTF8
  Write-Host "Zeitreihe geschrieben: $outCsvTimeseries"
  Write-Host "Beispiel (erste 5 Zeilen):"
  $rows | Select-Object -First 5 | Format-Table -AutoSize
  Write-Host "… und letzte 5:"
  $rows | Select-Object -Last 5 | Format-Table -AutoSize
} else {
  Write-Host "Keine Zeitreihen-Daten nach Filtern gefunden." -ForegroundColor Yellow
}

# --- Per-Author Totals
$rowsAuthors = @()
foreach ($mail in $aggByAuthor.Keys | Sort-Object) {
  $A = $aggByAuthor[$mail]
  $rowsAuthors += [pscustomobject]@{
    AuthorEmail = $mail
    Commits     = $A.Commits
    Added       = $A.Added
    Deleted     = $A.Deleted
    Net         = $A.Added - $A.Deleted
  }
}
if ($rowsAuthors.Count -gt 0) {
  $rowsAuthors | Export-Csv -Path $outCsvPerAuthor -NoTypeInformation -Encoding UTF8
  Write-Host "Per-Autor-Übersicht geschrieben: $outCsvPerAuthor"
  Write-Host ""
  Write-Host "Totals:"
  $rowsAuthors | Sort-Object Net -Descending | Format-Table -AutoSize
}

Write-Host ""
Write-Host "Drück eine Taste zum Schließen…"
[void][System.Console]::ReadKey($true)
