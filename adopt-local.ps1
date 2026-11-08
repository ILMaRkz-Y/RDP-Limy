#Requires -Version 5.1
<#
  One-time: move your existing game folders to E: and leave a junction behind,
  so your pc and the rdp session read and write the same files.
  Your pc keeps working exactly as before - the path does not change.

  Close Minecraft / Modrinth / Horizon first.

  See what would happen:   powershell -File E:\rdp-kit\adopt-local.ps1 -DryRun
  Actually do it:          powershell -File E:\rdp-kit\adopt-local.ps1

  Big personal folders are opt-in, because they are 122 GB and a million files:
                           powershell -File E:\rdp-kit\adopt-local.ps1 -IncludeDesktop -IncludePictures -IncludeVideos
#>
param(
    [string]$Root = 'E:\RDP\files',
    [string]$ProfileRoot = 'E:\RDP\profile',
    [switch]$DryRun,
    [switch]$IncludeDesktop,
    [switch]$IncludePictures,
    [switch]$IncludeVideos
)

$ErrorActionPreference = 'Stop'

$pairs = @(
    @{ Label = 'Minecraft .minecraft'
       Src   = Join-Path $env:APPDATA '.minecraft'
       Dst   = Join-Path $Root 'minecraft' }
    @{ Label = 'Modrinth instances'
       Src   = Join-Path $env:APPDATA 'ModrinthApp\profiles'
       Dst   = Join-Path $Root 'modrinth\profiles' }
    @{ Label = 'Modrinth metadata cache'
       Src   = Join-Path $env:APPDATA 'ModrinthApp\meta'
       Dst   = Join-Path $Root 'modrinth\meta' }
    @{ Label = 'Modrinth jar store'
       Src   = Join-Path $env:APPDATA 'ModrinthApp\store'
       Dst   = Join-Path $Root 'modrinth\store' }
    @{ Label = 'Horizon launcher'
       Src   = Join-Path $env:APPDATA 'horizon-launcher'
       Dst   = Join-Path $Root 'horizon-launcher' }
)

$running = Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -match 'minecraft|modrinth|horizon|java|limyrx' }
if ($running) {
    Write-Host "these look open - close them first:" -ForegroundColor Yellow
    $running | Select-Object -Unique ProcessName | ForEach-Object { "  $($_.ProcessName)" }
    if (-not $DryRun) { throw 'aborted, nothing was moved' }
}

function Move-AndJunction([string]$Src, [string]$Dst) {
    $item = Get-Item -LiteralPath $Src -Force
    if ($item.LinkType -eq 'Junction') {
        Write-Host "   already a junction -> $($item.Target)"
        return
    }
    $size = (Get-ChildItem -LiteralPath $Src -Recurse -File -ErrorAction SilentlyContinue |
             Measure-Object Length -Sum).Sum
    Write-Host ('   {0:N0} MB  {1}  ->  {2}' -f ($size / 1MB), $Src, $Dst)
    if ($DryRun) { return }

    New-Item -ItemType Directory $Dst -Force | Out-Null
    robocopy $Src $Dst /E /MOVE /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed on $Src ($LASTEXITCODE)" }
    $global:LASTEXITCODE = 0

    if (Test-Path -LiteralPath $Src) { Remove-Item -LiteralPath $Src -Recurse -Force }
    cmd /c mklink /J "$Src" "$Dst" | Out-Null
    if ((Get-Item -LiteralPath $Src -Force).LinkType -ne 'Junction') { throw "link was not created for $Src" }
    Write-Host '   done, path unchanged' -ForegroundColor Green
}

foreach ($p in $pairs) {
    Write-Host ""
    Write-Host "== $($p.Label)" -ForegroundColor Cyan

    if (-not (Test-Path -LiteralPath $p.Src)) { Write-Host '   not present, skipped'; continue }
    Move-AndJunction $p.Src $p.Dst
}

# opted-in big folders: move each item inside and leave one junction per item,
# so explorer keeps its handle on the folder itself and nothing has to close.
$big = @()
if ($IncludeDesktop)  { $big += 'Desktop'  }
if ($IncludePictures) { $big += 'Pictures' }
if ($IncludeVideos)   { $big += 'Videos'   }

foreach ($name in $big) {
    $srcRoot = Join-Path $env:USERPROFILE $name
    $dstRoot = Join-Path $ProfileRoot $name
    Write-Host ""
    Write-Host "== $name (one junction per item inside)" -ForegroundColor Cyan
    if (-not (Test-Path -LiteralPath $srcRoot)) { Write-Host '   not present, skipped'; continue }
    if (-not $DryRun) { New-Item -ItemType Directory $dstRoot -Force | Out-Null }

    foreach ($child in Get-ChildItem -LiteralPath $srcRoot -Force -Directory) {
        if ($child.LinkType -eq 'Junction') { continue }
        Write-Host "  -- $($child.Name)"
        Move-AndJunction $child.FullName (Join-Path $dstRoot $child.Name)
    }
}

Write-Host ""
Write-Host 'Finished. Both your pc and the rdp session now use E: directly.' -ForegroundColor Green
Write-Host ''
Write-Host 'To undo one of them (example, .minecraft):'
Write-Host ('  cmd /c rmdir "{0}"' -f (Join-Path $env:APPDATA '.minecraft'))
Write-Host ('  robocopy "E:\RDP\files\minecraft" "{0}" /E /MOVE' -f (Join-Path $env:APPDATA '.minecraft'))
