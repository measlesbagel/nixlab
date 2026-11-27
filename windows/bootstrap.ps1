# Idempotent provisioning script for chilense's `win11` VM.
# Run automatically on first logon from the WIN11BOOT ISO, and re-run anytime
# from Linux via `win11-apply` (over QEMU Guest Agent).
[CmdletBinding()]
param(
    [string]$ConfigDir = ""
)

$ErrorActionPreference = "Stop"

# 1. Disable sleep/hibernation so Windows never suspends a passed-through GPU.
powercfg /hibernate off | Out-Null
powercfg /change standby-timeout-ac 0 | Out-Null
powercfg /change monitor-timeout-ac 0 | Out-Null
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue

# 2. If the WIN11BOOT ISO is attached (first install), install VirtIO guest tools
#    and QEMU Guest Agent silently.
$bootDrive = Get-Volume -FileSystemLabel "WIN11BOOT" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($bootDrive) {
    $root = "$($bootDrive.DriveLetter):\"
    $guestTools = Join-Path $root "virtio-win-guest-tools.exe"
    if (Test-Path $guestTools) {
        Write-Host "Installing VirtIO guest tools..."
        Start-Process -FilePath $guestTools -ArgumentList "/install", "/passive", "/norestart" -Wait
    }
    $qemuGa = Join-Path $root "qemu-ga-x86_64.msi"
    if (Test-Path $qemuGa) {
        Write-Host "Installing QEMU Guest Agent..."
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", $qemuGa, "/qn", "/norestart" -Wait
    }
}

# 3. Locate win11.dsc.yaml (prefer the live read-only virtiofs mount Y:\,
#    falling back to the bootstrap ISO during initial setup).
if (-not $ConfigDir) {
    foreach ($candidate in @("Y:", (Split-Path -Parent $MyInvocation.MyCommand.Path))) {
        if ($candidate -and (Test-Path (Join-Path $candidate "win11.dsc.yaml"))) {
            $ConfigDir = $candidate
            break
        }
    }
}

# 4. Apply declarative WinGet Configuration (DSC v3).
$dscFile = if ($ConfigDir) { Join-Path $ConfigDir "win11.dsc.yaml" } else { "" }
if ($dscFile -and (Test-Path $dscFile)) {
    Write-Host "Applying WinGet configuration from $dscFile..."
    winget configure --enable 2>$null | Out-Null
    winget configure --accept-configuration-agreements --disable-interactivity -f $dscFile
} else {
    Write-Warning "win11.dsc.yaml not found; skipping winget configure."
}

# 5. Ensure VirtIO-FS service auto-starts once WinFsp is installed so `win-share`
#    and `win-config` mount automatically on boot.
if (Get-Service -Name "VirtioFsSvc" -ErrorAction SilentlyContinue) {
    Set-Service -Name "VirtioFsSvc" -StartupType Automatic
    Start-Service -Name "VirtioFsSvc" -ErrorAction SilentlyContinue
}

# 6. Enable OpenSSH Server (bound to the local NAT/guest network).
$sshCap = Get-WindowsCapability -Online -Name "OpenSSH.Server*" -ErrorAction SilentlyContinue
if ($sshCap -and $sshCap.State -ne "Installed") {
    Add-WindowsCapability -Online -Name $sshCap.Name | Out-Null
}
if (Get-Service -Name "sshd" -ErrorAction SilentlyContinue) {
    Set-Service -Name "sshd" -StartupType Automatic
    Start-Service -Name "sshd" -ErrorAction SilentlyContinue
}

Write-Host "win11 bootstrap complete."
