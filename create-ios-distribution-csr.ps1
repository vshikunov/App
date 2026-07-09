param(
    [string]$CommonName = "DimensionalScanner iOS Distribution",
    [string]$OutDir = ".\ios-signing"
)

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$openssl = Get-Command openssl -ErrorAction SilentlyContinue
if (-not $openssl) {
    throw "OpenSSL was not found. Install Git for Windows or OpenSSL, then run this script from a shell where 'openssl' works."
}

$keyPath = Join-Path $OutDir "ios_distribution.key"
$csrPath = Join-Path $OutDir "ios_distribution.csr"

openssl genrsa -out $keyPath 2048
openssl req -new -key $keyPath -out $csrPath -subj "/CN=$CommonName"

Write-Host "Created private key: $keyPath"
Write-Host "Created CSR:         $csrPath"
Write-Host "Upload the CSR to Apple Developer > Certificates, then download the Apple Distribution .cer file."
