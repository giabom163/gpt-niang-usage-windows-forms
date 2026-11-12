[CmdletBinding()]
param(
  [switch]$DownloadOnly,
  [switch]$CheckOnly,
  [string]$Destination = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\GPTNiangForms')
)

$ErrorActionPreference = 'Stop'
if ($DownloadOnly -and $CheckOnly) { throw 'Choose either -DownloadOnly or -CheckOnly.' }

$installer = 'gpt-niang-usage\Install.ps1'
$source = $PSScriptRoot
if (!(Test-Path -LiteralPath (Join-Path $source $installer) -PathType Leaf)) {
  $source = [IO.Path]::GetFullPath($Destination)
  if (!(Test-Path -LiteralPath $source)) {
    $parent = Split-Path -Parent $source
    $null = New-Item -Path $parent -ItemType Directory -Force
    $scratch = Join-Path $parent ('GPTNiangForms-' + [Guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $scratch -ItemType Directory
    try {
      $zip = Join-Path $scratch 'source.zip'
      $expanded = Join-Path $scratch 'expanded'
      $url = 'https://github.com/giabom163/gpt-niang-usage-windows-forms/archive/refs/tags/v1.0.0.zip'
      Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip
      Expand-Archive -LiteralPath $zip -DestinationPath $expanded
      $folders = @(Get-ChildItem -LiteralPath $expanded -Directory)
      if ($folders.Count -ne 1 -or !(Test-Path -LiteralPath (Join-Path $folders[0].FullName $installer) -PathType Leaf)) {
        throw 'The repository archive does not contain the expected Windows installer.'
      }

      if (Test-Path -LiteralPath $source) { throw 'The installation directory appeared during download. Run the command again.' }
      [IO.Directory]::Move($folders[0].FullName,$source)
    } finally {
      Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

$entry = Join-Path $source $installer
$manifest = Join-Path $source '.agents\plugins\marketplace.json'
if (!(Test-Path -LiteralPath $entry -PathType Leaf) -or !(Test-Path -LiteralPath $manifest -PathType Leaf)) {
  throw "The installation directory is missing project files: $source"
}

if ($DownloadOnly) {
  Write-Output "GPT Niang Forms source: $source"
  return
}
& $entry -CheckOnly:$CheckOnly
