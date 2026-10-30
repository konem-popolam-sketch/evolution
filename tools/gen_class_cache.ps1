# Пересобирает .godot/global_script_class_cache.cfg по class_name в проекте.
# Нужно потому, что этот проект создаётся без запуска редактора Godot, а headless-проверки
# (godot_validate_script) разрешают глобальные class_name только через кэш классов.
# Запуск: pwsh -File tools/gen_class_cache.ps1 -ProjectRoot <путь>

param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path $ProjectRoot).Path
$scripts = Get-ChildItem -Path (Join-Path $root 'scripts'), (Join-Path $root 'shaders') -Filter *.gd -Recurse -ErrorAction SilentlyContinue

$entries = New-Object System.Collections.Generic.List[string]
foreach ($f in $scripts) {
    $rel = 'res://' + ($f.FullName.Substring($root.Length + 1) -replace '\\', '/')
    $lines = Get-Content -LiteralPath $f.FullName -Encoding UTF8 -TotalCount 40
    $className = $null
    $baseName = 'RefCounted'
    foreach ($line in $lines) {
        if ($line -match '^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)') {
            $className = $Matches[1]
        }
        elseif ($line -match '^\s*extends\s+([A-Za-z_][A-Za-z0-9_]*(?:\[[^\]]*\])?)') {
            $baseName = $Matches[1]
        }
    }
    if (-not $className) { continue }
    $entry = @"
{
"base": &"$baseName",
"class": &"$className",
"icon": "",
"is_abstract": false,
"is_tool": false,
"language": &"GDScript",
"path": "$rel"
}
"@
    $entries.Add($entry.TrimEnd("`r", "`n"))
}

$godotDir = Join-Path $root '.godot'
if (-not (Test-Path $godotDir)) { New-Item -ItemType Directory -Path $godotDir | Out-Null }
$cachePath = Join-Path $godotDir 'global_script_class_cache.cfg'
$body = 'list=[' + ($entries -join ', ') + ']'
[System.IO.File]::WriteAllText($cachePath, $body, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "class cache: $($entries.Count) entries -> $cachePath"
