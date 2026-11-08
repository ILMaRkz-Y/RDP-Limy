#Requires -RunAsAdministrator
<#
  One-time setup on YOUR pc.
  Turns E:\RDP into a share the GitHub runner can write to over Tailscale.

  Run:  right-click > Run with PowerShell   (or)
        powershell -ExecutionPolicy Bypass -File E:\rdp-kit\setup-my-pc.ps1

  Nothing is opened to the internet: port 445 is allowed only from 100.64.0.0/10,
  which is the Tailscale range. Your router is untouched.
#>
param(
    [string]$ShareName = 'RDP',
    [string]$Root      = 'E:\RDP',
    [string]$UserName  = 'rdpsync'
)

$ErrorActionPreference = 'Stop'

# --- random password that satisfies the local password policy -------------
$alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
$password = -join (1..18 | ForEach-Object { $alphabet[(Get-Random -Maximum $alphabet.Length)] })
$password += '!7aZ'

Write-Host "`n== preparing $Root ==" -ForegroundColor Cyan
foreach ($d in 'profile', 'files') {
    New-Item -ItemType Directory (Join-Path $Root $d) -Force | Out-Null
}

Write-Host "== local account $UserName ==" -ForegroundColor Cyan
$secure = ConvertTo-SecureString $password -AsPlainText -Force
if (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue) {
    Set-LocalUser -Name $UserName -Password $secure
} else {
    New-LocalUser -Name $UserName -Password $secure -PasswordNeverExpires `
        -AccountNeverExpires -Description 'used by the rdp runner' | Out-Null
}

Write-Host "== ntfs permissions ==" -ForegroundColor Cyan
$acl = Get-Acl $Root
$acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
    $UserName, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
Set-Acl $Root $acl

Write-Host "== smb share ==" -ForegroundColor Cyan
if (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue) {
    Revoke-SmbShareAccess -Name $ShareName -AccountName 'Everyone' -Force -ErrorAction SilentlyContinue
    Grant-SmbShareAccess  -Name $ShareName -AccountName $UserName -AccessRight Full -Force | Out-Null
} else {
    New-SmbShare -Name $ShareName -Path $Root -FullAccess $UserName `
        -Description 'rdp files for the runner' | Out-Null
}

Write-Host "== firewall: 445 from the tailnet only ==" -ForegroundColor Cyan
Remove-NetFirewallRule -DisplayName 'RDP share (tailnet only)' -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName 'RDP share (tailnet only)' -Direction Inbound `
    -Action Allow -Protocol TCP -LocalPort 445 -RemoteAddress 100.64.0.0/10 `
    -Profile Any | Out-Null

$ip = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -like '100.*' } |
        Select-Object -First 1).IPAddress

Write-Host ''
Write-Host '===================== DONE =====================' -ForegroundColor Green
Write-Host "  share path : \\$ip\$ShareName"
Write-Host "  SMB_USER   : $UserName"
Write-Host "  SMB_PASSWORD : $password"
Write-Host ''
Write-Host '  Put those two in Settings > Secrets and variables > Actions.'
Write-Host '  If the share path is not \\100.120.215.94\RDP, edit "PC:" in rdp-workflow.yml.'
Write-Host '================================================'

# so the values survive after the elevated window closes
@(
    "share=$ip\$ShareName",
    "user=$UserName",
    "password=$password"
) | Set-Content 'E:\rdp-kit\share-info.txt' -Encoding utf8

