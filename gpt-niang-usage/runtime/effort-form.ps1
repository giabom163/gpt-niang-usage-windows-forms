# effort-form.ps1 — Codex reasoning effort -> five dragon-maid forms.
# Dot-sourced by widget.ps1; shares the $script: scope.
# Read-only inputs (no writes anywhere):
#   $env:CODEX_HOME/config.toml
#   $env:CODEX_HOME/sessions/**/rollout-*.jsonl
#   $env:GPTNIANG_FORM_STAGE                 (manual override, highest priority)
#   <dataDir>/form-override.json            (manual override, {"stage":"max"})
# Only side effect: swaps $script:ui.Girl.Source and rebuilds the alpha
# hit-test table. Quota, quotes, click-to-talk and settings.json are untouched.

$script:FORM_STAGES = @('low','medium','high','xhigh','max')
$script:FORM_DIR = Join-Path $script:appDir 'assets\forms'
$script:FORM_CURRENT = $null
$script:FORM_CHANGED_AT = $null
$script:FORM_SWAP_ERROR = $null
$script:FORM_FILES = @()
$script:FORM_NEXT_DISCOVERY = 0L
$script:FORM_NEXT_POLL = 0L
$script:FORM_NEXT_RECONCILE = 0L
$script:FORM_RECONCILED_AT = $null
$script:FORM_SESSION_STAGE = $null
$script:FORM_SESSION_SIGNAL = $null
$script:FORM_WATCHER = $null
$script:FORM_WATCHER_ROOT = $null
$script:FORM_WATCHER_ERROR = $null
$script:FORM_ASSETS = @{}
$script:FORM_SIGNAL = $null
$script:FORM_RECENT = @()
$script:FORM_TARGET = $null
$script:FORM_NATIVE_READER = $null
$script:FORM_NATIVE_ATTEMPTED = $false
$script:FORM_NATIVE_ERROR = $null
$script:FORM_NATIVE_SIGNAL = $null
$script:FORM_LAST_NATIVE_SIGNAL = $null
$script:formMode = 'auto'
$script:fixedForm = 'medium'
$script:formWidth = 100
$script:formHeight = 100
$script:formLock = $true
# Source alpha bounds measured at 64/255, in the 208-unit image box.
$script:FORM_GEOMETRY = @{
  low      = @{sourceHeight=134.4; foot=171.1; height=147}
  medium   = @{sourceHeight=174.8; foot=185.4; height=152}
  high     = @{sourceHeight=164.6; foot=186.0; height=157}
  xhigh    = @{sourceHeight=173.6; foot=191.8; height=162}
  max      = @{sourceHeight=186.4; foot=197.1; height=166}
}
$script:FORM_LAST_CONFIG_STAMP = 0
$script:FORM_LAST_CONFIG_EFFORT = $null
$script:FORM_SESSIONS = @{}
$script:FORM_LAST_OVERRIDE_STAMP = 0
$script:FORM_LAST_OVERRIDE_EFFORT = $null

# 1:1 port of dsh-dragon-maid-pet/logic.js normalizeEffort().
function ConvertTo-FormStage([string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) { return $null }
  $id = ($value.Trim().ToLowerInvariant()) -replace '[\s_-]+', ''
  switch ($id) {
    'off'       { return 'low' }
    'none'      { return 'low' }
    'minimal'   { return 'low' }
    'min'       { return 'low' }
    'low'       { return 'low' }
    'medium'    { return 'medium' }
    'high'      { return 'high' }
    'xhigh'     { return 'xhigh' }
    'extrahigh' { return 'xhigh' }
    'max'       { return 'max' }
    'maximum'   { return 'max' }
    'ultra'     { return 'max' }
  }
  return $null
}

function Get-CodexHome {
  if ($env:CODEX_HOME -and (Test-Path -LiteralPath $env:CODEX_HOME)) { return $env:CODEX_HOME }
  return (Join-Path $env:USERPROFILE '.codex')
}

# Global default in config.toml. Cached by mtime.
function Get-CodexConfigEffort {
  $path = Join-Path (Get-CodexHome) 'config.toml'
  if (!(Test-Path -LiteralPath $path)) { return $null }
  try {
    $stamp = [IO.File]::GetLastWriteTimeUtc($path).Ticks
    if ($stamp -ne $script:FORM_LAST_CONFIG_STAMP) {
      $script:FORM_LAST_CONFIG_STAMP = $stamp
      $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
      $m = [regex]::Match($text, '(?m)^\s*model_reasoning_effort\s*=\s*"([^"]+)"')
      if ($m.Success) { $script:FORM_LAST_CONFIG_EFFORT = $m.Groups[1].Value }
      else { $script:FORM_LAST_CONFIG_EFFORT = $null }
    }
    return $script:FORM_LAST_CONFIG_EFFORT
  } catch { return $null }
}

# A rollout can grow without changing its modification time. Keep a byte
# cursor per file and only advance it past complete lines. Choose the newest
# recognized settings event, regardless of which file's timestamp changed.
# Native callbacks only set flags. Parsing and image updates stay on the WPF thread.
function Initialize-FormWatcher([string]$root) {
  if ($script:FORM_WATCHER_ROOT -eq $root) { return }
  if ($script:FORM_WATCHER) { $script:FORM_WATCHER.Dispose() }
  $script:FORM_WATCHER = $null
  $script:FORM_WATCHER_ROOT = $root
  $script:FORM_FILES = @()
  $script:FORM_SESSIONS = @{}
  $script:FORM_SESSION_STAGE = $null
  $script:FORM_SESSION_SIGNAL = $null
  $script:FORM_NEXT_RECONCILE = 0L
  try {
    if (!('GptNiangRolloutWatcher' -as [type])) {
      Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
public sealed class GptNiangRolloutWatcher : IDisposable {
    readonly FileSystemWatcher watcher;
    int pending;
    public GptNiangRolloutWatcher(string root) {
        watcher = new FileSystemWatcher(root, "rollout-*.jsonl");
        watcher.IncludeSubdirectories = true;
        watcher.NotifyFilter = NotifyFilters.FileName | NotifyFilters.Size | NotifyFilters.LastWrite;
        watcher.Changed += (sender, args) => Mark(1);
        watcher.Created += (sender, args) => Mark(2);
        watcher.Deleted += (sender, args) => Mark(2);
        watcher.Renamed += (sender, args) => Mark(2);
        watcher.Error += (sender, args) => Mark(3);
        try { watcher.EnableRaisingEvents = true; }
        catch { watcher.Dispose(); throw; }
    }
    void Mark(int value) {
        int old;
        do {
            old = Volatile.Read(ref pending);
            if (old >= value) return;
        } while (Interlocked.CompareExchange(ref pending, value, old) != old);
    }
    public int Take() { return Interlocked.Exchange(ref pending, 0); }
    public void Dispose() { watcher.Dispose(); }
}
'@
    }
    $script:FORM_WATCHER = [GptNiangRolloutWatcher]::new($root)
    $script:FORM_WATCHER_ERROR = $null
  } catch { $script:FORM_WATCHER_ERROR = $_.Exception.GetType().Name }
}

function Get-FormCursorProbe($stream, [long]$offset) {
  $count = [int][Math]::Min(4096, $offset)
  if (!$count) { return '' }
  $buffer = New-Object byte[] $count
  $null = $stream.Seek($offset-$count, [IO.SeekOrigin]::Begin)
  $read = 0
  while ($read -lt $count) {
    $n = $stream.Read($buffer, $read, $count-$read)
    if (!$n) { throw 'Rollout changed while reading the cursor' }
    $read += $n
  }
  return [Convert]::ToBase64String($buffer)
}

function Read-CodexSessionEffort($file, $entry, [bool]$reconcile) {
  $stamp = $file.LastWriteTimeUtc.Ticks
  if (!$reconcile -and $file.Length -eq $entry.Length -and $stamp -eq $entry.Stamp) { return }

  $stream = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
  try {
    $length = $stream.Length
    $reset = $length -lt $entry.Length
    if (!$reset -and $entry.Offset -gt 0 -and ($reconcile -or $stamp -ne $entry.Stamp)) {
      $reset = (Get-FormCursorProbe $stream $entry.Offset) -cne $entry.Probe
    }
    if (!$reset -and $length -eq $entry.Length) { $entry.Stamp = $stamp; return }
    if ($reset) {
      $entry.Offset = 0L
      $entry.Probe = ''
      $entry.Stage = $null
      $entry.At = [DateTimeOffset]::MinValue
      $entry.ChangedAt = [DateTimeOffset]::MinValue
      $entry.Skipping = $false
    }
    $null = $stream.Seek($entry.Offset, [IO.SeekOrigin]::Begin)
    $buffer = New-Object byte[] 1048576
    while ($stream.Position -lt $length) {
      $start = $stream.Position
      $take = [int][Math]::Min($buffer.Length, $length - $start)
      $read = 0
      while ($read -lt $take) {
        $n = $stream.Read($buffer, $read, $take - $read)
        if ($n -eq 0) { return }
        $read += $n
      }

      $last = [Array]::LastIndexOf($buffer, [byte]10, $read - 1)
      if ($last -lt 0) {
        if ($read -lt $buffer.Length) { break }
        # Oversized records can contain tool output. Discard through the next LF.
        $entry.Skipping = $true
        $entry.Offset = $stream.Position
        continue
      }
      $first = 0
      if ($entry.Skipping) {
        $first = [Array]::IndexOf($buffer, [byte]10, 0, $read) + 1
        $entry.Skipping = $false
      }

      $text = [Text.Encoding]::UTF8.GetString($buffer, $first, $last + 1 - $first)
      foreach ($line in $text.Split([char]10)) {
        if (!$line.Contains('"thread_settings_applied"') -and !$line.Contains('"turn_context"')) { continue }
        try {
          $event = ConvertFrom-Json -InputObject $line -ErrorAction Stop
          if ($event.type -ceq 'event_msg' -and $event.payload.type -ceq 'thread_settings_applied') {
            $raw = [string]$event.payload.thread_settings.reasoning_effort
          } elseif ($event.type -ceq 'turn_context') {
            $raw = [string]$event.payload.effort
          } else { continue }

          $stage = ConvertTo-FormStage $raw
          if (!$stage -or !$event.timestamp) { continue }
          $at = [DateTimeOffset]$event.timestamp
          if ($at -ge $entry.At) {
            $entry.At = $at
            # A new turn often repeats the thread settings. Only a change
            # advances this thread in the cross-thread appearance ordering.
            if ($stage -ne $entry.Stage) {
              $entry.Stage = $stage; $entry.ChangedAt = $at; $entry.Raw = $raw
            }
          }
        } catch { continue }
      }

      $entry.Offset = $start + $last + 1
      if ($stream.Position -eq $length) { break }
      $null = $stream.Seek($entry.Offset, [IO.SeekOrigin]::Begin)
    }
    $entry.Probe = Get-FormCursorProbe $stream $entry.Offset
    $entry.Length = $length
    $entry.Stamp = $stamp
  } finally { $stream.Dispose() }
}

function Get-CodexSessionEffort([switch]$Immediate) {
  $root = Join-Path (Get-CodexHome) 'sessions'
  if (!(Test-Path -LiteralPath $root)) {
    $script:FORM_SIGNAL = $script:FORM_SESSION_SIGNAL
    return $script:FORM_SESSION_STAGE
  }
  Initialize-FormWatcher $root
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $notice = if ($script:FORM_WATCHER) { $script:FORM_WATCHER.Take() } else { 0 }
  $reconcile = $notice -eq 3 -or $now -ge $script:FORM_NEXT_RECONCILE
  if (!$Immediate -and !$notice -and !$reconcile -and $now -lt $script:FORM_NEXT_POLL) {
    $script:FORM_SIGNAL = $script:FORM_SESSION_SIGNAL
    return $script:FORM_SESSION_STAGE
  }
  $script:FORM_NEXT_POLL = $now + 450
  if ($reconcile) { $script:FORM_NEXT_RECONCILE = $now + 30000 }
  if ($Immediate -or $notice -ge 2 -or $reconcile -or $now -ge $script:FORM_NEXT_DISCOVERY) {
    $script:FORM_NEXT_DISCOVERY = $now + 1600
    try {
      $script:FORM_FILES = @(Get-ChildItem -LiteralPath $root -Filter 'rollout-*.jsonl' -File -Recurse -ErrorAction Stop)
      $seen = @{}
      foreach ($file in $script:FORM_FILES) { $seen[$file.FullName] = $true }
      foreach ($path in @($script:FORM_SESSIONS.Keys)) {
        if (!$seen.ContainsKey($path)) { $script:FORM_SESSIONS.Remove($path) }
      }
    } catch { }
  }
  $latest = $null
  foreach ($file in $script:FORM_FILES) {
    $path = $file.FullName
    if (!$script:FORM_SESSIONS.ContainsKey($path)) {
      $script:FORM_SESSIONS[$path] = @{
        Offset = 0L; Length = -1L; Stamp = 0L; Probe = ''
        Stage = $null; At = [DateTimeOffset]::MinValue; ChangedAt = [DateTimeOffset]::MinValue; Skipping = $false
      }
    }
    $entry = $script:FORM_SESSIONS[$path]
    try { $file.Refresh(); Read-CodexSessionEffort $file $entry $reconcile } catch { }
    if ($entry.Stage -and (!$latest -or $entry.ChangedAt -gt $latest.ChangedAt -or ($entry.ChangedAt -eq $latest.ChangedAt -and $entry.At -gt $latest.At))) { $latest = $entry }
  }
  if ($reconcile) { $script:FORM_RECONCILED_AT = $now }
  if ($latest) {
    $script:FORM_SIGNAL = @{raw=$latest.Raw; stage=$latest.Stage; at=$latest.ChangedAt.ToUnixTimeMilliseconds()}
    $script:FORM_SESSION_SIGNAL = $script:FORM_SIGNAL
    $script:FORM_SESSION_STAGE = $latest.Stage
    return $latest.Stage
  }
  $script:FORM_SIGNAL = $script:FORM_SESSION_SIGNAL
  return $script:FORM_SESSION_STAGE
}

# Optional manual lock. Environment variable needs no file writes at all,
# which is what the offline preview/verification uses.
function Get-FormOverrideEffort {
  if ($env:GPTNIANG_FORM_STAGE) { return $env:GPTNIANG_FORM_STAGE }
  $path = Join-Path $script:dataDir 'form-override.json'
  if (!(Test-Path -LiteralPath $path)) { return $null }
  try {
    $stamp = [IO.File]::GetLastWriteTimeUtc($path).Ticks
    if ($stamp -ne $script:FORM_LAST_OVERRIDE_STAMP) {
      $script:FORM_LAST_OVERRIDE_STAMP = $stamp
      $obj = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($obj.stage) { $script:FORM_LAST_OVERRIDE_EFFORT = [string]$obj.stage }
      else { $script:FORM_LAST_OVERRIDE_EFFORT = $null }
    }
    return $script:FORM_LAST_OVERRIDE_EFFORT
  } catch { return $null }
}

function Update-NativeEffortSource([long]$hostWindow) {
  if (!$script:FORM_NATIVE_ATTEMPTED -and $hostWindow) {
    $script:FORM_NATIVE_ATTEMPTED = $true
    try {
      Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
      if (!('GptNiangNativeEffort' -as [type])) {
        $refs = @([Windows.Automation.AutomationElement].Assembly.Location,
          [Windows.Automation.ControlType].Assembly.Location,
          [Windows.Rect].Assembly.Location,
          [Text.RegularExpressions.Regex].Assembly.Location)
        Add-Type -Path (Join-Path $script:appDir 'runtime\\native-effort.cs') -ReferencedAssemblies $refs
      }
      $script:FORM_NATIVE_READER = [GptNiangNativeEffort]::new()
    } catch { $script:FORM_NATIVE_ERROR = $_.Exception.Message }
  }
  if ($script:FORM_NATIVE_READER) {
    $script:FORM_NATIVE_READER.SetHost($hostWindow)
    $script:FORM_NATIVE_SIGNAL = $script:FORM_NATIVE_READER.Read($hostWindow)
    if ($script:FORM_LAST_NATIVE_SIGNAL -and $script:FORM_LAST_NATIVE_SIGNAL.Host -ne $hostWindow) {
      $script:FORM_LAST_NATIVE_SIGNAL = $null
    }
    if ($script:FORM_NATIVE_SIGNAL) { $script:FORM_LAST_NATIVE_SIGNAL = $script:FORM_NATIVE_SIGNAL }
  }
}

function Get-CodexEffortStage([switch]$Immediate) {
  $script:FORM_SIGNAL = $null
  if ($script:formMode -eq 'original') { return 'original' }
  if ($script:formMode -eq 'fixed') { return $script:fixedForm }
  $o = ConvertTo-FormStage (Get-FormOverrideEffort)
  if ($o) { return $o }
  if ($script:FORM_NATIVE_SIGNAL) {
    $native = $script:FORM_NATIVE_SIGNAL
    $script:FORM_SIGNAL = @{raw=$native.Stage; stage=$native.Stage; at=$native.At; source=$native.Source}
    return $native.Stage
  }
  $s = ConvertTo-FormStage (Get-CodexSessionEffort -Immediate:$Immediate)
  $lastNative = $script:FORM_LAST_NATIVE_SIGNAL
  if ($lastNative -and (!$s -or !$script:FORM_SIGNAL -or $script:FORM_SIGNAL.at -le $lastNative.At)) {
    $script:FORM_SIGNAL = @{raw=$lastNative.Stage; stage=$lastNative.Stage; at=$lastNative.At; source='native-retained'}
    return $lastNative.Stage
  }
  if ($s) { return $s }
  $c = ConvertTo-FormStage (Get-CodexConfigEffort)
  if ($c) { return $c }
  return 'medium'
}

function Set-GirlGeometry {
  $profile = $script:FORM_GEOMETRY[$script:FORM_CURRENT]
  $base = 1.0
  $foot = 208.0
  $targetFoot = 208.0
  if ($profile) {
    $base = $profile.height / $profile.sourceHeight
    $foot = $profile.foot
    $targetFoot = 182.0
  }
  $sx = $base * $script:formWidth / 100
  $sy = $base * $script:formHeight / 100
  $targetX = 104.0
  if (!$profile) {
    # The old bust fills the image box. Expand left to keep its right edge in view.
    $targetX = [Math]::Min($targetX, 208 - 104 * $sx)
  }
  $matrix = [Windows.Media.Matrix]::new($sx,0,0,$sy,($targetX-104*$sx),($targetFoot-$foot*$sy))
  $script:ui.Girl.RenderTransform = [Windows.Media.MatrixTransform]::new($matrix)
}

function Set-GirlStage([string]$stage) {
  if (!$stage -or $stage -eq $script:FORM_CURRENT) { return $false }
  if (!$script:FORM_ASSETS.ContainsKey($stage)) {
    $path = if ($stage -eq 'original') {
      Join-Path $script:appDir 'assets\gpt-dragon-niang-bust.png'
    } else { Join-Path $script:FORM_DIR ($stage + '.png') }
    if (!(Test-Path -LiteralPath $path)) { throw "Missing artwork: $stage" }
    $bmp = New-Object Windows.Media.Imaging.BitmapImage
    $bmp.BeginInit()
    $bmp.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bmp.UriSource = [Uri]$path
    $bmp.DecodePixelWidth = 640
    $bmp.EndInit()
    $bmp.Freeze()
    $alpha = New-Object Windows.Media.Imaging.FormatConvertedBitmap($bmp, [Windows.Media.PixelFormats]::Bgra32, $null, 0)
    $stride = $bmp.PixelWidth * 4
    $pixels = New-Object byte[] ($stride * $bmp.PixelHeight)
    $alpha.CopyPixels($pixels, $stride, 0)
    $script:FORM_ASSETS[$stage] = @{Bitmap=$bmp; Pixels=$pixels; Stride=$stride}
  }
  $asset = $script:FORM_ASSETS[$stage]
  $script:ui.Girl.Source = $asset.Bitmap
  $script:bitmap = $asset.Bitmap
  $script:alphaPixels = $asset.Pixels
  $script:alphaStride = $asset.Stride
  $script:FORM_CURRENT = $stage
  Set-GirlGeometry
  $script:FORM_CHANGED_AT = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  return $true
}

function Sync-EffortForm([switch]$Immediate) {
  try {
    $script:FORM_TARGET = Get-CodexEffortStage -Immediate:$Immediate
    $changed = Set-GirlStage $script:FORM_TARGET
    $script:FORM_SWAP_ERROR = $null
    if ($changed) {
      $script:FORM_RECENT = @($script:FORM_RECENT + @{
        stage=$script:FORM_CURRENT
        image=[IO.Path]::GetFileName($script:ui.Girl.Source.UriSource.LocalPath)
        at=$script:FORM_CHANGED_AT; signal=$script:FORM_SIGNAL; mode=$script:formMode
        visible=[bool]$script:window.IsVisible
      } | Select-Object -Last 12)
    }
  } catch { $script:FORM_SWAP_ERROR = $_.Exception.Message }
}

function Get-WidgetFormStatus {
  return @{
    mode=$script:formMode; target=$script:FORM_TARGET; stage=$script:FORM_CURRENT
    image=[IO.Path]::GetFileName($script:ui.Girl.Source.UriSource.LocalPath)
    reconciledAt=$script:FORM_RECONCILED_AT; watcherError=$script:FORM_WATCHER_ERROR
    nativeError=$script:FORM_NATIVE_ERROR
    signal=$script:FORM_SIGNAL; changedAt=$script:FORM_CHANGED_AT; error=$script:FORM_SWAP_ERROR
    imageLoaded=[bool]$script:ui.Girl.IsLoaded; windowVisible=[bool]$script:window.IsVisible
    alphaBytes=$script:alphaPixels.Length; recent=$script:FORM_RECENT
    width=$script:formWidth; height=$script:formHeight; lockRatio=$script:formLock
  }
}
