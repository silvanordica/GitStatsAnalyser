# timeseries_bare_branch_authors.ps1
# Autor-gefilterte Zeitreihe (täglich, kumuliert) für EINEN Branch in einem BARE repo.
# Output-CSV liegt im selben Ordner wie dieses Skript. Hält das Fenster am Ende offen.

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

function Pause-ForUser {
  try {
    if ($Host.Name -match 'ConsoleHost') {
      Write-Host "`nPress any key to close..."
      $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    } else {
      Read-Host "`nPress Enter to close"
    }
  } catch {}
}

try {
  # === Konfiguration ===
  $gitDir   = "C:\NET\working\Git\RS2.git"                    # BARE repository
  $branchIn = "user/mkuehtreiber/530/20250929_QM"             # EXAKT wie in deiner heads-Liste
  $since    = "2025-07-01"
  $until    = "2025-09-30 23:59:59"

  # PR-Merges mitzählen (empfohlen: $true; Merge-Commits selbst tragen idR keine Numstat-Zeilen)
  $includeMerges = $true

  # Nur diese Autor:innen (Match gegen Author- ODER Committer-E-Mail)
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

  # Dateitypen/Ordner einschränken (leer = alles zählen)
  $validExt = @(".cs",".cshtml",".sql",".ts",".tsx",".js",".jsx",".css",".scss",".xml")
  $skipDirs = @("bin","obj","dist","node_modules","wwwroot\lib","packages","generated","migrations")

  function Should-SkipPath([string]$path) {
    if (-not $path) { return $false }
    $p = $path -replace '/','\'
    foreach ($d in $skipDirs) {
      $dLow = $d.ToLower()
      if ($p.ToLower().Contains("\$dLow\")) { return $true }
      if ($p.ToLower().EndsWith("\$dLow"))  { return $true }
    }
    return $false
  }

  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Git not found in PATH." }
  if (-not (Test-Path $gitDir)) { throw "gitDir not found: $gitDir" }

  # === Branch-Auflösung für BARE repo: refs/heads/<name>, fallback main/master, sonst HEAD ===
  function Resolve-HeadRef([string]$gitDir, [string]$name) {
    function _exists($short) {
      & git --git-dir=$gitDir rev-parse --verify --quiet $short *> $null
      return ($LASTEXITCODE -eq 0)
    }
    if (-not [string]::IsNullOrWhiteSpace($name)) {
      $exact = "refs/heads/$name"
      if (_exists $exact) { return $exact }
      # Teilstring-Suche über alle heads; wenn nur ein Treffer -> nimm den
      $heads = & git --git-dir=$gitDir for-each-ref --format="%(refname:short)" refs/heads 2>$null
      $cands = @($heads | Where-Object { $_ -like "*$name*" })
      if ($cands.Count -eq 1) { return "refs/heads/$($cands[0])" }
      if ($cands.Count -gt 1) {
        Write-Host "Multiple matching heads found for '$name':" -ForegroundColor Yellow
        $cands | ForEach-Object { Write-Host "  $_" }
        throw "Please set an exact branch name (one of the above)."
      }
    }
    foreach ($def in @("refs/heads/main","refs/heads/master")) {
      if (_exists $def) { return $def }
    }
    & git --git-dir=$gitDir rev-parse --verify --quiet HEAD *> $null
    if ($LASTEXITCODE -eq 0) { return "HEAD" }
    throw "No suitable branch found (no heads/main/master/HEAD)."
  }

  $resolved = Resolve-HeadRef $gitDir $branchIn
  $branchArgs = @()
  if ($resolved -ne "HEAD") { $branchArgs = @($resolved) }

  # === Output-Datei im Skriptordner ===
  $scriptDir  = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
  $sinceDate  = ($since -split '\s+')[0]; $untilDate = ($until -split '\s+')[0]
  $branchSafe = ($resolved -replace '[^A-Za-z0-9._-]','_')
  $outCsv     = Join-Path $scriptDir "timeseries_${branchSafe}_authors_${sinceDate}_to_${untilDate}.csv"

  Write-Host "Repo (bare): $gitDir"
  Write-Host "Branch:      $resolved"
  Write-Host "Range:       $since .. $until"
  Write-Host "Output:      $outCsv`n"

  # === Git-Log abrufen: -w (ignore whitespace), -M (renames), optional --no-merges
  $mergeFlag = if ($includeMerges) { @() } else { @("--no-merges") }
  $lines = & git --git-dir=$gitDir log @branchArgs `
            --since="$since" --until="$until" -w -M --date=short `
            @mergeFlag --pretty=format:"@%ad|%ae|%ce|%s" --numstat 2>$null

  # === Parsen & aggregieren (nur Author/Committer in $authorEmails) ===
  $agg = @{}; $cumAdd = 0; $cumDel = 0
  $currentDate=$null; $currAuth=$null; $currComm=$null
  $totalCommits=0; $matchedCommits=0; $samples=@()

  foreach ($line in $lines) {
    if ($line.StartsWith("@")) {
      $totalCommits++
      $currentDate=$null; $currAuth=$null; $currComm=$null
      # Header: @<date>|<authorEmail>|<committerEmail>|<subject>
      $parts = $line.Substring(1).Split("|",4,[System.StringSplitOptions]::None)
      if ($parts.Count -ge 3) {
        try { $currentDate = [datetime]::ParseExact($parts[0].Trim(),"yyyy-MM-dd",$null) } catch {}
        $ae = $parts[1].Trim().ToLower()
        $ce = $parts[2].Trim().ToLower()
        if (($authorEmails -contains $ae) -or ($authorEmails -contains $ce)) {
          $currAuth=$ae; $currComm=$ce
          $matchedCommits++
          if ($samples.Count -lt 5) { $samples += $line.Substring(1) }
        }
      }
      continue
    }

    # numstat-Zeilen sind TAB-getrennt: <added>\t<deleted>\t<path>
    $p = $line -split "`t"
    if ($p.Length -lt 3) { $p = $line -split "\s+" }  # Fallback, falls Tabs fehlten
    if ($p.Length -ge 3 -and $p[0] -match '^\d+$' -and $p[1] -match '^\d+$') {
      if ($null -eq $currentDate) { continue }
      if ($null -eq $currAuth -and $null -eq $currComm) { continue }

      $path = $p[2]
      if ($validExt.Count -gt 0) {
        $ext = [IO.Path]::GetExtension($path)
        if (-not ($validExt -contains $ext)) { continue }
      }
      if (Should-SkipPath $path) { continue }

      $key = $currentDate.ToString("yyyy-MM-dd")
      if (-not $agg.ContainsKey($key)) { $agg[$key] = @{Added=0;Deleted=0} }
      $agg[$key].Added   += [int]$p[0]
      $agg[$key].Deleted += [int]$p[1]
    }
  }

  # === Zeitreihe bauen (täglich + kumulativ) ===
  $rows=@()
  foreach ($k in ($agg.Keys | Sort-Object)) {
    $a=$agg[$k].Added; $d=$agg[$k].Deleted
    $cumAdd += $a; $cumDel += $d
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

  # — kleine Diagnose —
  # (zur Einordnung: Gesamt-Commits vs. Commits die zu euren Mails passen)
  $countAll = (& git --git-dir=$gitDir rev-list --count @branchArgs --since=$since --until="$until" 2>$null).Trim()
  Write-Host ("Commits in range (all):        {0}" -f ($countAll -as [int]))
  Write-Host ("Commits matched (A/C emails):  {0}" -f $matchedCommits)
  if ($samples.Count -gt 0) {
    Write-Host "Sample matches:"
    $samples | ForEach-Object { Write-Host "  $_" }
  }
  Write-Host ""

  if ($rows.Count -gt 0) {
    $rows | Export-Csv -Path $outCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Written: $outCsv"
  } else {
    Write-Host "??  No matching changes found."
    Write-Host "Hints:"
    Write-Host "  • List heads:  git --git-dir=""$gitDir"" for-each-ref --format=""%(refname:short)"" refs/heads"
    Write-Host "  • Set `$branchIn exactly as in the list."
    Write-Host "  • Set `$includeMerges = `$true for PR merges."
    Write-Host "  • Relax `$validExt / `$skipDirs (empty lists count everything)."
  }
}
catch {
  Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
  if ($_.InvocationInfo) { Write-Host $_.InvocationInfo.PositionMessage }
}
finally {
  Pause-ForUser
}
