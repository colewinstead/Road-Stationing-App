param([switch]$Release)
$ErrorActionPreference = 'Stop'
$repoTaskRoot = Split-Path -Parent $PSScriptRoot
if (-not $env:SDKROOT) {
    $env:SDKROOT = [Environment]::GetEnvironmentVariable('SDKROOT', 'User')
}
$swiftTaskRuntime = Join-Path $env:LOCALAPPDATA 'Programs\Swift\Runtimes'
if (Test-Path -LiteralPath $swiftTaskRuntime) {
    $swiftTaskRuntimeBin = Get-ChildItem -LiteralPath $swiftTaskRuntime -Filter swiftCore.dll -Recurse |
        Where-Object { $_.FullName -notmatch 'arm64' } | Sort-Object FullName -Descending |
        Select-Object -First 1 -ExpandProperty DirectoryName
    if ($swiftTaskRuntimeBin) { $env:Path = $swiftTaskRuntimeBin + ';' + $env:Path }
}
$swiftTaskCommand = Get-Command swift -ErrorAction SilentlyContinue
if (-not $swiftTaskCommand) {
    $swiftTaskBase = Join-Path $env:LOCALAPPDATA 'Programs\Swift\Toolchains'
    $swiftTaskExe = Get-ChildItem -LiteralPath $swiftTaskBase -Filter swift.exe -Recurse |
        Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (-not $swiftTaskExe) { throw 'Install the Swift Windows toolchain first (see README).' }
    $env:Path = (Split-Path -Parent $swiftTaskExe) + ';' + $env:Path
}
if (-not (Get-Command link.exe -ErrorAction SilentlyContinue)) {
    $vsTaskWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vsTaskInstall = & $vsTaskWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vsTaskInstall) { throw 'Microsoft C++ Build Tools and Windows SDK are required.' }
    $vsTaskBatch = Join-Path $vsTaskInstall 'Common7\Tools\VsDevCmd.bat'
    $vsTaskProcess = [System.Diagnostics.ProcessStartInfo]::new($env:ComSpec)
    $vsTaskProcess.Arguments = "/d /s /c `"`"$vsTaskBatch`" -no_logo -arch=x64 -host_arch=x64 >nul && set`""
    $vsTaskProcess.UseShellExecute = $false
    $vsTaskProcess.CreateNoWindow = $true
    $vsTaskProcess.RedirectStandardOutput = $true
    $vsTaskChild = [System.Diagnostics.Process]::Start($vsTaskProcess)
    $vsTaskVariables = $vsTaskChild.StandardOutput.ReadToEnd() -split "`r?`n"
    $vsTaskChild.WaitForExit()
    if ($vsTaskChild.ExitCode -ne 0) { throw 'Could not initialize Microsoft build environment.' }
    foreach ($vsTaskLine in $vsTaskVariables) {
        if ($vsTaskLine -match '^([^=]+)=(.*)$') {
            [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
        }
    }
}
Push-Location -LiteralPath $repoTaskRoot
try {
    swift --version
    if ($Release) { swift test -c release } else { swift test }
    if ($LASTEXITCODE -ne 0) { throw "swift test failed with exit code $LASTEXITCODE" }
} finally { Pop-Location }
