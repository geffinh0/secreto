
param()

$Key = "$env:USERPROFILE\.ssh\notebook_to_vps"
$LogDir = "$env:LOCALAPPDATA\AtilaTunnel"
$LogFile = "$LogDir\tunnel.log"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

$sshArgs = @(
    "-N",
    "-R", "127.0.0.1:2222:127.0.0.1:22",
    "-i", $Key,
    "-o", "ServerAliveInterval=30",
    "-o", "ServerAliveCountMax=3",
    "-o", "ExitOnForwardFailure=yes",
    "-o", "StrictHostKeyChecking=accept-new",
    "tunnel@187.77.235.245"
)

function Log($msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $msg" | Out-File -FilePath $LogFile -Append -Encoding utf8
}

while ($true) {
    Log "(re)conectando o tunel..."
    & ssh @sshArgs 2>&1 | Out-File -FilePath $LogFile -Append -Encoding utf8
    Log "tunel caiu, tentando de novo em 10s"
    Start-Sleep -Seconds 10
}
