<#
  Windows-side lifecycle checks for the WSL Edge bridge.
  This script never stops or replaces an existing listener. Port collisions are
  reported with ownership details so the operator can decide what to stop.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('EnsureEdge', 'EnsureForwarder')]
  [string]$Action,

  [int]$DebugPort = 9222,
  [int]$ForwardPort = 9223,
  [string]$ListenAddress,
  [string]$ForwarderPath,
  [string]$EdgeExe,
  [string]$UserDataDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class Win32CommandLine {
  [DllImport("shell32.dll", SetLastError = true)]
  static extern IntPtr CommandLineToArgvW(
    [MarshalAs(UnmanagedType.LPWStr)] string commandLine,
    out int argc
  );

  [DllImport("kernel32.dll")]
  static extern IntPtr LocalFree(IntPtr pointer);

  public static string[] Split(string commandLine) {
    int argc;
    var argv = CommandLineToArgvW(commandLine, out argc);
    if (argv == IntPtr.Zero) {
      throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }
    try {
      var values = new List<string>(argc);
      for (var i = 0; i < argc; i++) {
        var item = Marshal.ReadIntPtr(argv, i * IntPtr.Size);
        values.Add(Marshal.PtrToStringUni(item));
      }
      return values.ToArray();
    } finally {
      LocalFree(argv);
    }
  }
}
'@

function Fail([string]$Layer, [string]$Message) {
  throw "[$Layer] $Message"
}

function Get-PolicyValue([string]$Hive, [string]$Name) {
  $path = "$Hive\SOFTWARE\Policies\Microsoft\Edge"
  try {
    return (Get-ItemProperty -Path $path -Name $Name -ErrorAction Stop).$Name
  } catch [System.Management.Automation.ItemNotFoundException] {
    return $null
  } catch [System.Management.Automation.PSArgumentException] {
    return $null
  }
}

function Assert-RemoteDebuggingPolicy {
  foreach ($hive in @('HKLM:', 'HKCU:')) {
    $value = Get-PolicyValue $hive 'RemoteDebuggingAllowed'
    if ($null -ne $value -and [int]$value -eq 0) {
      Fail 'Edge policy' "RemoteDebuggingAllowed is disabled at $hive\SOFTWARE\Policies\Microsoft\Edge. Edge must be restarted after an administrator changes this policy."
    }
  }
}

function Resolve-EdgeExecutable {
  if ($EdgeExe) {
    if (-not (Test-Path -LiteralPath $EdgeExe -PathType Leaf)) {
      Fail 'Edge discovery' "WSL_BROWSER_EDGE_EXE does not exist: $EdgeExe"
    }
    return (Resolve-Path -LiteralPath $EdgeExe).Path
  }

  $candidates = @()
  try {
    $appPath = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe' -ErrorAction Stop).'(default)'
    if ($appPath) { $candidates += $appPath }
  } catch { }
  try {
    $appPath = (Get-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe' -ErrorAction Stop).'(default)'
    if ($appPath) { $candidates += $appPath }
  } catch { }
  if (${env:ProgramFiles(x86)}) {
    $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe')
  }
  if ($env:ProgramFiles) {
    $candidates += (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
  }
  try {
    $command = Get-Command msedge.exe -CommandType Application -ErrorAction Stop
    $candidates += $command.Source
  } catch { }

  foreach ($candidate in $candidates | Select-Object -Unique) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  Fail 'Edge discovery' 'Could not locate msedge.exe from App Paths, Program Files, or PATH. Set WSL_BROWSER_EDGE_EXE to a Windows path.'
}

function Resolve-UserDataDirectory {
  if ($UserDataDir) { return $UserDataDir }
  if (-not $env:LOCALAPPDATA) {
    Fail 'Edge profile' 'Windows LOCALAPPDATA is unavailable. Set WSL_BROWSER_USER_DATA_DIR to a Windows path.'
  }
  return (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data - CDP')
}

function Get-SingleListener([int]$Port, [string]$Layer) {
  $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
  if ($listeners.Count -gt 1) {
    Fail $Layer "Multiple listeners own port $Port; refusing to guess which process is safe."
  }
  if ($listeners.Count -eq 0) { return $null }
  return $listeners[0]
}

function Get-ProcessRecord([int]$ProcessId) {
  return Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction Stop
}

function Format-Owner($Listener) {
  $record = Get-ProcessRecord ([int]$Listener.OwningProcess)
  return "PID $($record.ProcessId) $($record.Name), address $($Listener.LocalAddress), command: $($record.CommandLine)"
}

function Get-SwitchValues([string[]]$Arguments, [string]$Name) {
  $values = @()
  for ($index = 0; $index -lt $Arguments.Count; $index++) {
    $argument = $Arguments[$index]
    if ([string]::Equals($argument, $Name, [StringComparison]::OrdinalIgnoreCase)) {
      if ($index + 1 -ge $Arguments.Count) { $values += $null } else { $values += $Arguments[$index + 1] }
      continue
    }
    $prefix = "$Name="
    if ($argument.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
      $values += $argument.Substring($prefix.Length)
    }
  }
  return @($values)
}

function Assert-EdgeListener($Listener, [string]$ExpectedExe, [string]$ExpectedProfile) {
  $record = Get-ProcessRecord ([int]$Listener.OwningProcess)
  $commandLine = [string]$record.CommandLine
  $actualExe = [string]$record.ExecutablePath
  $arguments = [Win32CommandLine]::Split($commandLine)
  $portValues = @(Get-SwitchValues $arguments '--remote-debugging-port')
  $profileValues = @(Get-SwitchValues $arguments '--user-data-dir')
  $normalizedExpectedProfile = [IO.Path]::GetFullPath($ExpectedProfile).TrimEnd('\')

  if ($Listener.LocalAddress -notin @('127.0.0.1', '::1')) {
    Fail 'Debug port ownership' "Edge CDP must listen only on Windows loopback, not $($Listener.LocalAddress). $(Format-Owner $Listener)"
  }
  if (-not $actualExe -or -not [string]::Equals($actualExe, $ExpectedExe, [StringComparison]::OrdinalIgnoreCase)) {
    Fail 'Debug port ownership' "Port $DebugPort is not owned by the configured Edge executable. $(Format-Owner $Listener)"
  }
  if ($portValues.Count -ne 1 -or -not [string]::Equals([string]$portValues[0], [string]$DebugPort, [StringComparison]::Ordinal)) {
    Fail 'Debug port ownership' "Port $DebugPort belongs to Edge, but its command line must contain exactly one matching --remote-debugging-port. $(Format-Owner $Listener)"
  }
  if ($profileValues.Count -ne 1) {
    Fail 'Debug port ownership' "Port $DebugPort belongs to Edge, but its command line must contain exactly one --user-data-dir. $(Format-Owner $Listener)"
  }
  try {
    $normalizedActualProfile = [IO.Path]::GetFullPath([string]$profileValues[0]).TrimEnd('\')
  } catch {
    Fail 'Debug port ownership' "Edge has an invalid --user-data-dir value: $($profileValues[0]). $(Format-Owner $Listener)"
  }
  if (-not [string]::Equals($normalizedActualProfile, $normalizedExpectedProfile, [StringComparison]::OrdinalIgnoreCase)) {
    Fail 'Debug port ownership' "Port $DebugPort belongs to Edge, but its dedicated profile is $normalizedActualProfile instead of $normalizedExpectedProfile. $(Format-Owner $Listener)"
  }
}

function Get-EdgeCdpIdentity {
  try {
    $version = Invoke-RestMethod -Uri "http://127.0.0.1:$DebugPort/json/version" -TimeoutSec 3 -ErrorAction Stop
  } catch {
    Fail 'Edge CDP identity' "Windows localhost:$DebugPort did not return /json/version: $($_.Exception.Message)"
  }
  $browser = [string]$version.Browser
  $webSocketUrl = [string]$version.webSocketDebuggerUrl
  if ($browser -notmatch '^Edg/' -or [string]::IsNullOrWhiteSpace($webSocketUrl)) {
    Fail 'Edge CDP identity' "Windows localhost:$DebugPort is not a Microsoft Edge CDP endpoint."
  }
  try {
    $webSocketPath = ([uri]$webSocketUrl).AbsolutePath
  } catch {
    Fail 'Edge CDP identity' "Edge returned an invalid webSocketDebuggerUrl: $webSocketUrl"
  }
  if ($webSocketPath -notmatch '^/devtools/browser/[^/]+$') {
    Fail 'Edge CDP identity' "Edge returned an unexpected browser WebSocket path: $webSocketPath"
  }
  return [pscustomobject]@{
    browser = $browser
    webSocketPath = $webSocketPath
  }
}

function Wait-ForListener([int]$Port, [string]$Layer, [int]$Seconds = 30) {
  for ($i = 0; $i -lt $Seconds; $i++) {
    $listener = Get-SingleListener $Port $Layer
    if ($null -ne $listener) { return $listener }
    Start-Sleep -Seconds 1
  }
  Fail $Layer "Port $Port did not begin listening within ${Seconds}s."
}

function Ensure-Edge {
  Assert-RemoteDebuggingPolicy
  $resolvedExe = Resolve-EdgeExecutable
  $resolvedProfile = Resolve-UserDataDirectory
  $listener = Get-SingleListener $DebugPort 'Debug port ownership'

  if ($null -eq $listener) {
    New-Item -ItemType Directory -Path $resolvedProfile -Force | Out-Null
    $arguments = @(
      "--remote-debugging-port=$DebugPort",
      "--user-data-dir=`"$resolvedProfile`"",
      '--no-first-run',
      '--no-default-browser-check',
      'about:blank'
    )
    try {
      Start-Process -FilePath $resolvedExe -ArgumentList $arguments -PassThru -ErrorAction Stop | Out-Null
    } catch {
      Fail 'Windows process launch' "Failed to start Microsoft Edge: $($_.Exception.Message)"
    }
    $listener = Wait-ForListener $DebugPort 'Windows process launch'
  }

  Assert-EdgeListener $listener $resolvedExe $resolvedProfile
  $identity = Get-EdgeCdpIdentity
  [pscustomobject]@{
    action = 'EnsureEdge'
    edgeExe = $resolvedExe
    userDataDir = $resolvedProfile
    debugPort = $DebugPort
    ownerPid = $listener.OwningProcess
    browser = $identity.browser
    webSocketPath = $identity.webSocketPath
  } | ConvertTo-Json -Compress
}

function Assert-ForwarderListener($Listener) {
  if ([string]::IsNullOrWhiteSpace($ListenAddress) -or
      $ListenAddress -in @('0.0.0.0', '::', '*')) {
    Fail 'NAT forwarder policy' 'A specific Windows gateway address is required; wildcard binds are prohibited.'
  }
  if (-not $ForwarderPath -or -not (Test-Path -LiteralPath $ForwarderPath -PathType Leaf)) {
    Fail 'NAT forwarder setup' "Forwarder script is missing: $ForwarderPath"
  }

  $record = Get-ProcessRecord ([int]$Listener.OwningProcess)
  $commandLine = [string]$record.CommandLine
  $actualAddress = [string]$Listener.LocalAddress
  $required = @(
    '-ListenAddress',
    $ListenAddress,
    '-ListenPort',
    [string]$ForwardPort,
    '-TargetPort',
    [string]$DebugPort
  )

  if ($record.Name -notmatch '^powershell(\.exe)?$' -or
      -not [string]::Equals($actualAddress, $ListenAddress, [StringComparison]::OrdinalIgnoreCase)) {
    Fail 'Forward port ownership' "Port $ForwardPort is not the narrowly bound Pi Edge forwarder. $(Format-Owner $Listener)"
  }
  $runningForwarderPath = $null
  if ($commandLine -match '(?i)-File\s+"([^"]+)"') {
    $runningForwarderPath = $Matches[1]
  } elseif ($commandLine -match '(?i)-File\s+(\S+)') {
    $runningForwarderPath = $Matches[1]
  }
  if (-not $runningForwarderPath -or -not (Test-Path -LiteralPath $runningForwarderPath -PathType Leaf)) {
    Fail 'Forward port ownership' "The running PowerShell listener has no readable -File script path. $(Format-Owner $Listener)"
  }
  $expectedHash = (Get-FileHash -LiteralPath $ForwarderPath -Algorithm SHA256 -ErrorAction Stop).Hash
  $runningHash = (Get-FileHash -LiteralPath $runningForwarderPath -Algorithm SHA256 -ErrorAction Stop).Hash
  if (-not [string]::Equals($runningHash, $expectedHash, [StringComparison]::OrdinalIgnoreCase)) {
    Fail 'Forward port ownership' "Port $ForwardPort uses a different forwarder script than this bridge version. $(Format-Owner $Listener)"
  }
  foreach ($token in $required) {
    if ($commandLine.IndexOf($token, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
      Fail 'Forward port ownership' "Port $ForwardPort has a PowerShell listener with unexpected arguments (missing $token). $(Format-Owner $Listener)"
    }
  }
}

function Ensure-Forwarder {
  if ([string]::IsNullOrWhiteSpace($ListenAddress) -or $ListenAddress -in @('0.0.0.0', '::', '*')) {
    Fail 'NAT forwarder policy' 'Refusing to expose Edge CDP on a wildcard address.'
  }

  $edgeExe = Resolve-EdgeExecutable
  $profile = Resolve-UserDataDirectory
  $edgeListener = Get-SingleListener $DebugPort 'Debug port ownership'
  if ($null -eq $edgeListener) {
    Fail 'NAT forwarder setup' "Edge is not listening on Windows localhost port $DebugPort."
  }
  Assert-EdgeListener $edgeListener $edgeExe $profile

  $listener = Get-SingleListener $ForwardPort 'Forward port ownership'
  if ($null -eq $listener) {
    $powershellExe = Join-Path $PSHOME 'powershell.exe'
    $arguments = @(
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      "`"$ForwarderPath`"",
      '-ListenAddress',
      $ListenAddress,
      '-ListenPort',
      [string]$ForwardPort,
      '-TargetPort',
      [string]$DebugPort
    )
    try {
      Start-Process -FilePath $powershellExe -ArgumentList $arguments -WindowStyle Hidden -PassThru -ErrorAction Stop | Out-Null
    } catch {
      Fail 'NAT forwarder launch' "Failed to start the local CDP forwarder: $($_.Exception.Message)"
    }
    $listener = Wait-ForListener $ForwardPort 'NAT forwarder launch' 15
  }

  Assert-ForwarderListener $listener
  [pscustomobject]@{
    action = 'EnsureForwarder'
    listenAddress = $ListenAddress
    listenPort = $ForwardPort
    targetAddress = '127.0.0.1'
    targetPort = $DebugPort
    ownerPid = $listener.OwningProcess
  } | ConvertTo-Json -Compress
}

switch ($Action) {
  'EnsureEdge' { Ensure-Edge }
  'EnsureForwarder' { Ensure-Forwarder }
}
