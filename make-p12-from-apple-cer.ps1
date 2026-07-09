param(
    [Parameter(Mandatory=$true)]
    [string]$CerPath,

    [Parameter(Mandatory=$true)]
    [string]$PrivateKeyPath,

    [Parameter(Mandatory=$true)]
    [string]$P12Password,

    [string]$OutPath = ".\ios_distribution.p12"
)

$openssl = Get-Command openssl -ErrorAction SilentlyContinue
if (-not $openssl) {
    throw "OpenSSL was not found. Install Git for Windows or OpenSSL, then run this script from a shell where 'openssl' works."
}

$tempPem = [System.IO.Path]::GetTempFileName()
try {
    openssl x509 -inform DER -in $CerPath -out $tempPem
    openssl pkcs12 -export -out $OutPath -inkey $PrivateKeyPath -in $tempPem -password pass:$P12Password
    Write-Host "Created P12: $OutPath"
} finally {
    Remove-Item $tempPem -ErrorAction SilentlyContinue
}
