# Steam Frame Realtek 8832CU diagnostic / optional one-shot US runtime country command.
# Uses built-in Windows wlanapi.dll, NOT third-party binaries.
# Protocol packet derived from toorux/steam-frame-6ghz-tool src/protocol.rs.
# WARNING: WlanIhvControl transport compatibility with this specific Realtek firmware
# has not been tested on hardware. A failed call is NOT evidence the driver is unsupported.
# Run: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\SteamFrame-6GHz.ps1
# To apply once: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\SteamFrame-6GHz.ps1 -ApplyUS
param([switch]$ApplyUS, [switch]$Force)
$ErrorActionPreference='Stop'
if (-not [Environment]::Is64BitProcess) { throw 'Run with 64-bit PowerShell.' }
if ($ApplyUS -and -not $Force) {
  $answer = Read-Host 'This submits ONE vendor command to set the adapter runtime country to US. Type APPLY to continue'
  if ($answer -cne 'APPLY') { Write-Host 'Cancelled.'; exit 0 }
}
$source = @'
using System;
using System.Runtime.InteropServices;
public static class FrameWlan {
  [DllImport("wlanapi.dll", ExactSpelling=true)]
  public static extern uint WlanOpenHandle(uint version, IntPtr reserved, out uint negotiated, out IntPtr handle);
  [DllImport("wlanapi.dll", ExactSpelling=true)]
  public static extern uint WlanCloseHandle(IntPtr handle, IntPtr reserved);
  [DllImport("wlanapi.dll", ExactSpelling=true)]
  public static extern uint WlanIhvControl(IntPtr handle, ref Guid guid, uint type, uint inSize,
      [In] byte[] input, uint outSize, [Out] byte[] output, out uint returned);
}
'@
Add-Type -TypeDefinition $source -ErrorAction Stop
$adapter = Get-NetAdapter -Name 'Wi-Fi' -ErrorAction Stop
if ($adapter.InterfaceDescription -notmatch 'Realtek 8832CU.*Valve') {
  throw "Refusing to target unexpected adapter: $($adapter.InterfaceDescription)"
}
$guid = [Guid]::Parse($adapter.InterfaceGuid.ToString())
$negotiated=[uint32]0
$h=[IntPtr]::Zero
$err=[FrameWlan]::WlanOpenHandle(2,[IntPtr]::Zero,[ref]$negotiated,[ref]$h)
if ($err -ne 0) { throw "WlanOpenHandle failed: Win32 error $err" }
function Packet([string]$kind) {
  $b = [Collections.Generic.List[byte]]::new()
  $oid = switch($kind) {
    'Country' { [uint32]4286665247 }
    'Info' { [uint32]4286677056 }
    'ManualUS' { [uint32]4286677056 }
    'Done' { [uint32]4286677057 }
    'Output' { [uint32]4286677058 }
    default { throw 'Unknown command' }
  }
  if ($kind -in @('Info','ManualUS')) {
    foreach ($n in @(0,0, $(if($kind -eq 'ManualUS'){29}else{0}),3)) { $b.AddRange([BitConverter]::GetBytes([uint32]$n)) }
    $tokens=if($kind -eq 'ManualUS') { @('67','US') } else { @('echo','core','6g_info') }
    foreach($token in $tokens) {
      $bytes=[Text.Encoding]::ASCII.GetBytes($token)
      $b.AddRange($bytes)
      for($i=$bytes.Length;$i -lt 16;$i++){ $b.Add([byte]0) }
    }
    while($b.Count -lt 336) { $b.Add([byte]0) }
  } else {
    while($b.Count -lt 300) { $b.Add([byte]0) }
  }
  $n=[uint32]$b.Count
  $p=[Collections.Generic.List[byte]]::new()
  # Parenthesize arithmetic: Windows PowerShell 5.1 otherwise treats comma-separated
  # expressions such as $n+36,VALUE as array addition (Object[].op_Addition).
  $headerWords = @(
    ($n + 36),
    2169298944,
    4,
    1,
    7,
    ($n + 40),
    $oid,
    ($n + 24),
    ($n + 24),
    $n
  )
  foreach($x in $headerWords) {
    $p.AddRange([BitConverter]::GetBytes([uint32]$x))
  }
  $p.AddRange($b)
  return ,$p.ToArray()
}
function Exchange([string]$kind) {
  [byte[]]$req=Packet $kind
  $resp=New-Object byte[] $req.Length
  $returned=[uint32]0
  # Driver control type 1; if this vendor's transport uses an alternate method, this will fail.
  $code=[FrameWlan]::WlanIhvControl($h,[ref]$guid,1,[uint32]$req.Length,$req,[uint32]$resp.Length,$resp,[ref]$returned)
  if ($code -ne 0) { throw "WlanIhvControl($kind) failed: Win32 error $code" }
  if ($returned -lt 40 -or $returned -gt $resp.Length) { throw "Invalid reply length for $kind ($returned)" }
  for($i=0;$i -lt 28;$i++) { if($req[$i] -ne $resp[$i]) {throw "Protocol header mismatch: $kind"} }
  for($i=36;$i -lt 40;$i++) { if($req[$i] -ne $resp[$i]) {throw "Protocol length mismatch: $kind"} }
  $written=[BitConverter]::ToUInt32($resp,28)
  $status=[BitConverter]::ToUInt32($resp,32)
  $capacity=[BitConverter]::ToUInt32($resp,36)
  if ($status -ne 0 -or $written -gt $capacity -or (40+$written) -gt $returned) {throw "Driver did not confirm valid $kind reply"}
  $out=New-Object byte[] ([int]$written)
  [Array]::Copy($resp,40,$out,0,[int]$written)
  return ,$out
}
function Country {
  [byte[]]$x=Exchange 'Country'
  if($x.Length -ne 2) {throw 'Unexpected country reply length'}
  if($x[0] -eq 0 -and $x[1] -eq 0){return 'unknown (two zero bytes)'}
  return [Text.Encoding]::ASCII.GetString($x)
}
function Diagnostic([string]$kind) {
  [void](Exchange 'Done') # consume stale completion
  [void](Exchange $kind)   # exactly ONE submission, no retry
  $ready=$false
  for($i=0;$i -lt 20;$i++) {
    Start-Sleep -Milliseconds 100
    [byte[]]$d=Exchange 'Done'
    if($d.Length -ne 4){throw 'Unexpected Done reply'}
    $state=[BitConverter]::ToUInt32($d,0)
    if($state -gt 1){throw 'Unexpected Done state'}
    if($state -eq 1){$ready=$true;break}
  }
  if(-not $ready){throw 'Timed out; command was NOT resent. State is unknown.'}
  $full=[Collections.Generic.List[byte]]::new()
  $sequence=$null
  for($i=0;$i -lt 64;$i++) {
    [byte[]]$part=Exchange 'Output'
    if($part.Length -lt 16){throw 'Truncated output block'}
    $mode=[BitConverter]::ToUInt32($part,0)
    $status=[BitConverter]::ToUInt32($part,4)
    $seq=[BitConverter]::ToUInt32($part,8)
    $len=[BitConverter]::ToUInt32($part,12)
    if($mode -ne 0 -or $status -notin @(0,2) -or $len -gt 200 -or $part.Length -ne (16+$len)){throw 'Invalid output block'}
    if($null -ne $sequence -and $seq -ne $sequence){throw 'Output sequence changed'}
    $sequence=$seq
    for($j=16;$j -lt $part.Length;$j++){$full.Add($part[$j])}
    if($full.Contains([byte]0) -or $status -eq 0){
      $bytes=$full.ToArray()
      $idx=[Array]::IndexOf($bytes,[byte]0)
      if($idx -eq 0){$bytes=[byte[]]@()} elseif($idx -gt 0){$bytes=$bytes[0..($idx-1)]}
      return [Text.Encoding]::ASCII.GetString($bytes).Replace("`r",'')
    }
  }
  throw 'Diagnostic output exceeded limit'
}
try {
  Write-Host "Target: $($adapter.InterfaceDescription) / $guid"
  if ($ApplyUS) {
    Write-Host 'Submitting one-time US runtime command...'
    $reply=Diagnostic 'ManualUS'
    Write-Host "Driver reply:`n$reply"
    if ($reply -notmatch 'Country code has changed to US|Invalid country code!') {
      Write-Warning 'Unexpected reply. Do not automatically retry.'
    }
  }
  Write-Host "Country: $(Country)"
  Write-Host "6 GHz diagnostic output:`n$(Diagnostic 'Info')"
  Write-Host 'Done. No registry, driver files, or startup tasks changed.'
} finally {
  [void][FrameWlan]::WlanCloseHandle($h,[IntPtr]::Zero)
}
