param(
    [string]$VisualStudio = 'C:/Program Files/Microsoft Visual Studio/2022/Community',
    [switch]$TestsOnly
)
$ErrorActionPreference = 'Stop'
$toolsRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$gameRoot = (Resolve-Path (Join-Path $toolsRoot '..')).Path
$vendor = Join-Path $toolsRoot 'vendor/team-sync-ue4ss-1181'
$source = Join-Path $vendor 'source/RE-UE4SS-8333063595fa3c49ad307f3b0f732accbb760d25'
$output = Join-Path $PSScriptRoot 'build'
$ue4ss = Join-Path $toolsRoot 'vendor/ue4ss-1181/ue4ss/UE4SS.dll'
$steam = Join-Path $gameRoot 'Engine/Binaries/ThirdParty/Steamworks/Steamv157/Win64/steam_api64.dll'
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $ue4ss).Hash -ne 'CE5E3C46A920CC00B2817AC61E438C9162830290379D0B5B9C4DFC2B29459290') {
    throw 'UE4SS DLL does not match the pinned 1181 headers; rebuild against the correct framework version.'
}
New-Item -ItemType Directory -Force -Path $output | Out-Null
Import-Module (Join-Path $VisualStudio 'Common7/Tools/Microsoft.VisualStudio.DevShell.dll')
Enter-VsDevShell -VsInstallPath $VisualStudio -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64'

function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}

# No /MP and no parallel build jobs. All output remains beneath this source tree.
$common = @('/nologo', '/utf-8', '/std:c++20', '/EHsc', '/MD', '/O2', '/W4', '/DWIN32', '/D_WIN32',
    "/I$PSScriptRoot", "/external:I$vendor/steam", '/external:W0', "/Fo$output/")
$transport = Join-Path $PSScriptRoot 'Transport.cpp'
$binding = Join-Path $PSScriptRoot 'SteamBinding.cpp'
Invoke-Checked 'cl.exe' ($common + @("$toolsRoot/tests/transport_test.cpp", $transport, $binding, "/Fe$output/transport_test.exe"))
Invoke-Checked "$output/transport_test.exe" @()
Invoke-Checked 'cl.exe' ($common + @("$toolsRoot/tests/transport_abi_test.cpp", $binding, "/Fe$output/transport_abi_test.exe"))
Invoke-Checked "$output/transport_abi_test.exe" @($steam)
if ($TestsOnly) { return }

# Exact official header. Drop only its unused circular GUI.hpp include, which
# otherwise pulls all GUI and UEPseudo dependencies into a non-GUI transport.
# Every GUITab definition and field remains byte-for-byte unchanged.
$overrides = Join-Path $output 'header-overrides'
New-Item -ItemType Directory -Force -Path "$overrides/GUI" | Out-Null
$guiHeader = [IO.File]::ReadAllText("$source/UE4SS/include/GUI/GUITab.hpp")
$guiHeader = $guiHeader.Replace('#include <GUI/GUI.hpp>', '// Unused circular GUI.hpp include omitted by FFWTeamSync build.ps1.')
[IO.File]::WriteAllText("$overrides/GUI/GUITab.hpp", $guiHeader, [Text.UTF8Encoding]::new($false))

# The official binary release contains no import .lib. Generate it from the
# actual installed-version DLL's named exports; never guess decorated names.
$exports = & dumpbin.exe /NOLOGO /EXPORTS $ue4ss
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect UE4SS exports' }
$names = @($exports | ForEach-Object { if ($_ -match '^\s+\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+(\S+)') { $Matches[1] } })
if ($names.Count -lt 100) { throw 'Unexpected UE4SS export inventory' }
[IO.File]::WriteAllLines("$output/UE4SS.def", (@('LIBRARY UE4SS.dll', 'EXPORTS') + $names), [Text.UTF8Encoding]::new($false))
Invoke-Checked 'lib.exe' @('/nologo', '/machine:x64', "/def:$output/UE4SS.def", "/out:$output/UE4SS.lib")
$includes = @("$overrides", "$source/UE4SS/include", "$source/deps/first/File/include", "$source/deps/first/Input/include",
    "$source/deps/first/String/include", "$source/deps/first/LuaMadeSimple/include", "$source/deps/first/LuaRaw/include",
    "$vendor/fmt/fmt-11.2.0/include") | ForEach-Object { "/external:I$_" }
Invoke-Checked 'cl.exe' ($common + $includes + @('/LD', '/D_HAS_ITERATOR_DEBUGGING=0', '/D_ITERATOR_DEBUG_LEVEL=0',
    "$PSScriptRoot/Bridge.cpp", $transport, $binding, "$output/UE4SS.lib", "/Fe$output/main.dll", '/link', '/INCREMENTAL:NO'))
Write-Output "Built $output/main.dll. No files were deployed and no game was launched."
