param(
    [Parameter(Mandatory=$true)]
    [string]$Path
)

if (!(Test-Path $Path)) {
    throw "File not found: $Path"
}

$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $Path))
$encoded = [Convert]::ToBase64String($bytes)
$encoded | Set-Clipboard
Write-Host "Base64 copied to clipboard. Paste it into the matching GitHub Actions secret."
