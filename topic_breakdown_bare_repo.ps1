# topic_breakdown_bare_repo.ps1
# Themen-Übersicht je Topic (Added/Deleted/Net, Anteile) für EINEN Branch im BARE-Repo.
# PS5-kompatibel, behandelt Git-Rename-Pfade (old => new, {old=>new}), pausiert am Ende.

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

function Pause-ForUser {
  try {
    if ($Host.Name -match 'ConsoleHost') {
      Write-Host ""
      Write-Host "Press any key to close..."
      $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    } else {
      Read-Host "`nPress Enter to close"
    }
  } catch {}
}

# -------- Helpers: Rename-sichere Pfadbehandlung --------
function Normalize-GitPath([string]$path) {
  if (-not $path) { return "" }
  $p = $path.Trim('"')
  # Braced rename: src/{old=>new}/file.ext  -> src/new/file.ext
  $p = [regex]::Replace($p, '\{[^{}]*=>([^{}]*)\}', '$1')
  # Plain rename:  old/path => new/path     -> new/path
  if ($p -match '^(.*)\s=>\s(.*)$') { $p = $Matches[2] }
  return $p
}
function Has-AllowedExt([string]$path, [string[]]$validExt) {
  if ($null -eq $validExt -or $validExt.Count -eq 0) { return $true }
  $pp = (Normalize-GitPath $path).ToLower()
  foreach ($ext in $validExt) {
    if ($pp.EndsWith($ext.ToLower())) { return $true }
  }
  return $false
}
function Should-SkipPath([string]$path, [string[]]$skipDirs) {
  if (-not $path) { return $false }
  $p = (Normalize-GitPath $path) -replace '/','\'
  $p = $p.ToLower()
  foreach ($d in $skipDirs) {
    $dLow = $d.ToLower()
    if ($p.Contains("\$dLow\")) { return $true }
    if ($p.EndsWith("\$dLow"))  { return $true }
  }
  return $false
}

try {
  # ==== KONFIG ====
  $gitDir   = "C:\NET\working\Git\RS2.git"                # BARE repo
  $branchIn = "user/mkuehtreiber/530/20250929_QM"         # exakt wie in heads-Liste
  $since    = "2025-07-01"
  $until    = "2025-09-30 23:59:59"

  # Autor*innen (Author ODER Committer)
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

  # Dateitypen/Ordner filtern
  $validExt = @(".cs",".cshtml",".sql",".ts",".tsx",".js",".jsx",".css",".scss",".xml",".json",".yaml",".yml",".ps1")
  $skipDirs = @("bin","obj","dist","node_modules","wwwroot\lib","packages","generated","migrations")

  # Topic-Modus
  $topicMode   = "byRules"   # "byRules" oder "byFolder"
  $folderDepth = 2

  # Regel-Mapping (editierbar)
  $topicRules = @(
    @{ Name = "Payroll";              PathMatch = @("Payroll","PayrollConsole");      MsgMatch = @("Payroll") }
    @{ Name = "BUAK";                 PathMatch = @("BUAK");                          MsgMatch = @("BUAK") }
    @{ Name = "L16";                  PathMatch = @("L16");                           MsgMatch = @("L16") }
    @{ Name = "Budget";               PathMatch = @("BudgetFZ","Bud");                MsgMatch = @("Budget") }
    @{ Name = "ZVAG";                 PathMatch = @("ZVAG");                          MsgMatch = @("ZVAG") }
    @{ Name = "EDUHR";                PathMatch = @("EDUHR");                         MsgMatch = @("EDUHR") }
    @{ Name = "mBGM";                 PathMatch = @("mBGM","BGM");                    MsgMatch = @("mBGM") }
    @{ Name = "ELDA";                 PathMatch = @("ELDA");                          MsgMatch = @("ELDA") }
    @{ Name = "IAreaAccountService";  PathMatch = @("IAreaAccountService");           MsgMatch = @("IAreaAccountService") }
  )

  # ==== weitere Helper ====
  function Topic-FromRules([string]$path, [string]$msg) {
    $p = if ($null -ne $path) { $path.ToLower() } else { "" }
    $m = if ($null -ne $msg)  { $msg.ToLower() }  else { "" }
    foreach ($r in $topicRules) {
      foreach ($pat in $r.PathMatch) { if ($pat -and $p.Contains($pat.ToLower())) { return $r.Name } }
      foreach ($pat in $r.MsgMatch)  { if ($pat -and $m.Contains($pat.ToLower())) { return $r.Name } }
    }
    return $null
  }
  function Topic-FromFolder([string]$path, [int]$depth) {
    if (-not $path) { return "ROOT" }
    $norm  = (Normalize-GitPath $path) -replace '\\','/'
    $parts = $norm.Split('/') | Where-Object { $_ -ne "" }
    if ($parts.Count -eq 0) { return "ROOT" }
    $take = [Math]::Min($parts.Count, [Math]::Max(1,$depth))
    return ($parts[0..($take-1)] -join "/")
  }
  function Resolve-HeadRef([string]$gitDir, [string]$name) {
    function _exists($short) {
      & git --git-dir=$gitDir rev-parse --verify --quiet $short *> $null
      return ($LASTEXITCODE -eq 0)
    }
    if (-not [string]::IsNullOrWhiteSpace($name)) {
      $exact = "refs/heads/$name"
      if (_exists $exact) { return $exact }
      $heads = & git --git-dir=$gitDir for-each-ref --format="%(refname:short)" refs/heads 2>$null
      $cands = @($heads | Where-Object { $_ -like "*$name*" })
      if ($cands.Count -eq 1) { return ("refs/heads/" + $cands[0]) }
      if ($cands.Count -gt 1) {
        Write-Host "Mehrere passende heads für '$name':" -ForegroundColor Yellow
        $cands | ForEach-Object { Write-Host "  $_" }
        throw "Bitte exakten Branchnamen setzen (s. Liste)."
      }
    }
    foreach ($def in @("refs/heads/main","refs/heads/master")) { if (_exists $def) { return $def } }
    & git --git-dir=$gitDir rev-parse --verify --quiet HEAD *> $null
    if ($LASTEXITCODE -eq 0) { return "HEAD" }
    throw "Kein geeigneter Branch gefunden (heads/main/master/HEAD)."
  }

  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Git nicht im PATH." }
  if (-not (Test-Path $gitDir)) { throw "gitDir nicht gefunden: $gitDir" }

  $resolved   = Resolve-HeadRef $gitDir $branchIn
  $branchArgs = @(); if ($resolved -ne "HEAD") { $branchArgs = @($resolved) }

  Write-Host "Repo (bare): $gitDir"
  Write-Host "Branch:      $resolved"
  Write-Host "Range:       $since .. $until`n"

  # ==== LOG EINLESEN ====
  $mergeFlag = @()
  $lines = & git --git-dir=$gitDir log @branchArgs `
            --since="$since" --until="$until" -w -M --date=short `
            @mergeFlag --pretty=format:"@%H|%ad|%ae|%ce|%s" --numstat 2>$null

  # ==== AGGREGATION ====
  $authorSet = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($a in $authorEmails) { [void]$authorSet.Add($a) }

  $byTopic = @{}           # topic -> @{Added;Deleted;Files}
  $commitTopics = @{}      # commitSha -> HashSet[topic]
  $totalCommits = 0; $matchedCommits = 0

  $currDate=$null; $currAuth=$null; $currComm=$null; $currMsg=$null; $currSha=$null

  foreach ($line in $lines) {
    if ($line.StartsWith("@")) {
      $totalCommits++
      $currDate=$null; $currAuth=$null; $currComm=$null; $currMsg=$null; $currSha=$null
      $parts = $line.Substring(1).Split("|",5,[System.StringSplitOptions]::None)
      if ($parts.Count -ge 4) {
        $currSha = $parts[0].Trim()
        try { $currDate = [datetime]::ParseExact($parts[1].Trim(),"yyyy-MM-dd",$null) } catch {}
        $currAuth = $parts[2].Trim().ToLower()
        $currComm = $parts[3].Trim().ToLower()
        $currMsg  = if ($parts.Count -ge 5) { $parts[4] } else { "" }
        if ($authorSet.Contains($currAuth) -or $authorSet.Contains($currComm)) { $matchedCommits++ }
      }
      continue
    }

    # numstat-Zeile: <added>\t<deleted>\t<path>
    $p = $line -split "`t"
    if ($p.Length -lt 3) { $p = $line -split "\s+" }  # Fallback
    if ($p.Length -ge 3 -and $p[0] -match '^\d+$' -and $p[1] -match '^\d+$') {
      if ($null -eq $currDate) { continue }
      if (-not ($authorSet.Contains($currAuth) -or $authorSet.Contains($currComm))) { continue }

      $added = [int]$p[0]; $deleted = [int]$p[1]
      $path  = $p[2]

      if (-not (Has-AllowedExt $path $validExt)) { continue }
      if (Should-SkipPath $path $skipDirs) { continue }

      $topic = $null
      if ($topicMode -eq "byRules" -and $topicRules.Count -gt 0) { $topic = Topic-FromRules $path $currMsg }
      if (-not $topic) { $topic = Topic-FromFolder $path $folderDepth }

      if (-not $byTopic.ContainsKey($topic)) { $byTopic[$topic] = @{ Added = 0; Deleted = 0; Files = 0 } }
      $byTopic[$topic].Added   += $added
      $byTopic[$topic].Deleted += $deleted
      $byTopic[$topic].Files   += 1

      if ($currSha) {
        if (-not $commitTopics.ContainsKey($currSha)) {
          $commitTopics[$currSha] = New-Object 'System.Collections.Generic.HashSet[string]'
        }
        [void]$commitTopics[$currSha].Add($topic)
      }
    }
  }

  # Summen & Anteile
  $totalAdded = 0; $totalDeleted = 0
  foreach ($t in $byTopic.Keys) {
    $totalAdded   += $byTopic[$t].Added
    $totalDeleted += $byTopic[$t].Deleted
  }
  $totalChanges = $totalAdded + $totalDeleted
  $totalNet     = $totalAdded - $totalDeleted

  # Commit-Touch je Topic
  $topicCommitCounts = @{}
  foreach ($kv in $commitTopics.GetEnumerator()) {
    foreach ($t in $kv.Value) {
      if (-not $topicCommitCounts.ContainsKey($t)) { $topicCommitCounts[$t] = 0 }
      $topicCommitCounts[$t]++
    }
  }

  # Ausgabe vorbereiten
  $rows = @()
  $order = $byTopic.Keys | Sort-Object { ($byTopic[$_].Added - $byTopic[$_].Deleted) } -Descending
  foreach ($t in $order) {
    $a = $byTopic[$t].Added; $d = $byTopic[$t].Deleted; $n = $a - $d
    $chg = $a + $d
    $shareChg = if ($totalChanges -gt 0) { [Math]::Round(100.0 * $chg / $totalChanges, 2) } else { 0 }
    $shareAdd = if ($totalAdded   -gt 0) { [Math]::Round(100.0 * $a   / $totalAdded,   2) } else { 0 }
    $shareNet = if ($totalNet     -ne 0) { [Math]::Round(100.0 * $n   / $totalNet,     2) } else { 0 }
    $commitsTouched = if ($topicCommitCounts.ContainsKey($t)) { $topicCommitCounts[$t] } else { 0 }

    $rows += [pscustomobject]@{
      Topic          = $t
      Added          = $a
      Deleted        = $d
      Net            = $n
      Changes        = $chg
      ShareChangesPc = $shareChg
      ShareAddedPc   = $shareAdd
      ShareNetPc     = $shareNet
      FilesChanged   = $byTopic[$t].Files
      CommitsTouched = $commitsTouched
    }
  }

  # Output
  $scriptDir  = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
  $sinceDate  = ($since -split '\s+')[0]; $untilDate = ($until -split '\s+')[0]
  $branchSafe = ($resolved -replace '[^A-Za-z0-9._-]','_')
  $outCsv     = Join-Path $scriptDir "topic_breakdown_${branchSafe}_${sinceDate}_to_${untilDate}.csv"

  if ($rows.Count -gt 0) {
    $rows | Export-Csv -Path $outCsv -NoTypeInformation -Encoding UTF8
    Write-Host ""
    Write-Host ("TOTAL  Added={0}  Deleted={1}  Net={2}" -f $totalAdded,$totalDeleted,$totalNet) -ForegroundColor Cyan
    $rows | Select-Object Topic, Net, ShareChangesPc, CommitsTouched | Format-Table -AutoSize
    Write-Host "`nWritten: $outCsv"
  } else {
    Write-Host "??  Keine passenden Änderungen gefunden."
    Write-Host "Tipps:"
    Write-Host "  • Zeitraum/Branch korrekt?"
    Write-Host "  • E-Mail-Filter zu streng?"
    Write-Host "  • topicMode=""byFolder"" testen (automatisch gruppieren)."
    Write-Host "  • `$validExt / `$skipDirs leeren, um alles mitzunehmen."
  }
}
catch {
  Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
  if ($_.InvocationInfo) { Write-Host $_.InvocationInfo.PositionMessage }
}
finally {
  Pause-ForUser
}
