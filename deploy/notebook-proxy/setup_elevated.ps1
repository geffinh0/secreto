
# Rode este script numa janela de PowerShell ABERTA COMO ADMINISTRADOR
# (botao direito no PowerShell -> "Executar como administrador"), depois
# cole o conteudo inteiro e aperte Enter.
#
# O que ele faz:
#   1. Instala e liga o servidor OpenSSH do Windows
#   2. Restringe o acesso a ele so para 127.0.0.1 (loopback) - nada de fora
#      consegue se conectar, so o proprio processo do tunel nesta maquina
#   3. Autoriza a chave publica da VPS (gerada so para isso, sem shell,
#      so pode abrir tuneis - "restrict,port-forwarding")
#   4. Agenda o tunel reverso (tunnel.ps1) para rodar escondido sempre que
#      voce fizer login, reconectando sozinho se cair

$ErrorActionPreference = "Stop"

Write-Host "1/5 instalando OpenSSH Server..."
$cap = Get-WindowsCapability -Online -Name OpenSSH.Server*
if ($cap.State -ne "Installed") {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
}

Write-Host "2/5 ligando o servico sshd..."
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd

Write-Host "3/5 restringindo o firewall do sshd a loopback..."
$rule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
if ($rule) {
    Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -RemoteAddress "127.0.0.1"
}

Write-Host "4/5 autorizando a chave da VPS (so forwarding, sem shell)..."
$sshDir = "$env:ProgramData\ssh"
$authFile = "$sshDir\administrators_authorized_keys"
$pubKeyLine = 'restrict,port-forwarding ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEiCHvEH7G2wKwoXYjU7cRFE3lir8GLVY0eHEFlWRhP0 vps-to-notebook-proxy'

if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
if (-not (Test-Path $authFile)) { New-Item -ItemType File -Path $authFile -Force | Out-Null }
$existing = Get-Content $authFile -ErrorAction SilentlyContinue
if ($existing -notcontains $pubKeyLine) {
    Add-Content -Path $authFile -Value $pubKeyLine
}

# ACL exigida pelo sshd: so SYSTEM e Administradores podem ler/escrever
icacls $authFile /inheritance:r | Out-Null
icacls $authFile /grant "SYSTEM:F" | Out-Null
icacls $authFile /grant "Administradores:F" | Out-Null

Write-Host "5/5 agendando o tunel para rodar escondido no login..."
$taskDir = "$env:LOCALAPPDATA\AtilaTunnel"
New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
Copy-Item -Path "$PSScriptRoot\tunnel.ps1" -Destination "$taskDir\tunnel.ps1" -Force

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$taskDir\tunnel.ps1`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Days 0) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew

Unregister-ScheduledTask -TaskName "AtilaClientTunnel" -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName "AtilaClientTunnel" -Action $action -Trigger $trigger -Settings $settings `
    -Description "Tunel SSH reverso que deixa o robo do Atila's Client sair pela internet deste notebook."

Start-ScheduledTask -TaskName "AtilaClientTunnel"

Write-Host ""
Write-Host "Pronto. O tunel foi iniciado agora e vai subir sozinho em todo login."
Write-Host "Log em: $taskDir\tunnel.log"
