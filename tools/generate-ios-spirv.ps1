param(
    [string] $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$cmakeLists = Join-Path $RepositoryRoot 'UnleashedRecomp/CMakeLists.txt'
$shaderDirectory = Join-Path $RepositoryRoot 'UnleashedRecomp/gpu/shader/hlsl'

$dxc = Get-Command dxc.exe -ErrorAction SilentlyContinue
if ($dxc) {
    $dxcPath = $dxc.Source
} else {
    $dxcPath = Get-ChildItem "$env:LOCALAPPDATA/Microsoft/WinGet/Packages/Microsoft.DirectX.ShaderCompiler_*/bin/x64/dxc.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $dxcPath) {
    throw 'DXC was not found. Install Microsoft.DirectX.ShaderCompiler, then rerun this script.'
}

$shaderCalls = Select-String -Path $cmakeLists -Pattern '^compile_(vertex|pixel)_shader[(]([^)]+)[)]'
if (-not $shaderCalls) {
    throw "No shader calls found in $cmakeLists"
}

foreach ($line in $shaderCalls) {
    $kind = $line.Matches[0].Groups[1].Value
    $shader = $line.Matches[0].Groups[2].Value
    $profile = if ($kind -eq 'vertex') { 'vs_6_0' } else { 'ps_6_0' }
    $source = Join-Path $shaderDirectory "$shader.hlsl"
    $output = "$source.spirv.h"

    $arguments = @(
        '-T', $profile,
        '-HV', '2021',
        '-all-resources-bound',
        '-Wno-ignored-attributes',
        '-spirv',
        '-fvk-use-dx-layout'
    )
    if ($kind -eq 'vertex') {
        $arguments += @('-fvk-invert-y', '-DUNLEASHED_RECOMP')
    } else {
        $arguments += '-DUNLEASHED_RECOMP'
    }
    $arguments += @('-E', 'shaderMain', '-Fh', $output, $source, '-Vn', ('g_{0}_spirv' -f $shader))

    & $dxcPath @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "DXC failed for $shader (exit code $LASTEXITCODE)."
    }
}

$headers = Get-ChildItem $shaderDirectory -Filter '*.hlsl.spirv.h'
if ($headers.Count -ne $shaderCalls.Count) {
    throw "Generated $($headers.Count) headers; expected $($shaderCalls.Count)."
}
Write-Host "Generated $($headers.Count) iOS SPIR-V shader headers."
