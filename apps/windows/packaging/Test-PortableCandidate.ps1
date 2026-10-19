param(
    [Parameter(Mandatory=$true)][string]$Candidate,
    [Parameter(Mandatory=$true)][string]$Report
)
$ErrorActionPreference='Stop'
$candidateRoot=[IO.Path]::GetFullPath($Candidate)
$reportPath=[IO.Path]::GetFullPath($Report)
if(Test-Path -LiteralPath $reportPath){throw 'Preserve the previous report; choose a new path.'}
$checks=[Collections.Generic.List[object]]::new()
function Record([string]$Name,[bool]$Passed,[string]$Detail){$checks.Add([pscustomobject]@{name=$Name;passed=$Passed;detail=$Detail})}
foreach($name in @('PhotoTrail.Windows.exe','PhotoTrail.Windows.dll','PhotoTrail.Windows.runtimeconfig.json','tools/exiftool/ExifTool.exe')){
    Record $name (Test-Path -LiteralPath (Join-Path $candidateRoot $name) -PathType Leaf) 'Required portable file'
}
$runtimeLock=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'datehost-runtime-lock.json') -Raw | ConvertFrom-Json
foreach($item in $runtimeLock.files){
    $file=Join-Path $candidateRoot $item.path
    $present=Test-Path -LiteralPath $file -PathType Leaf
    $matches=$present -and (Get-Item -LiteralPath $file).Length -eq $item.bytes -and (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -eq $item.sha256
    Record $item.path $matches 'Fixed DateHost combination; missing or changed files must not be mixed with another package'
}
$dotnet=Get-Command dotnet -ErrorAction SilentlyContinue
$runtimes=@();$sdks=@()
if($dotnet){$runtimes=@(& $dotnet.Source --list-runtimes);$sdks=@(& $dotnet.Source --list-sdks)}
Record 'WindowsDesktopRuntime10' ([bool]($runtimes -match '^Microsoft.WindowsDesktop.App 10\.')) 'Requires .NET 10 Windows Desktop Runtime of the application architecture'
$webviewVersions=@()
foreach($registryRoot in @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients','HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients','HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients')){
    if(Test-Path -LiteralPath $registryRoot){foreach($key in Get-ChildItem -LiteralPath $registryRoot){
        $entry=Get-ItemProperty -LiteralPath $key.PSPath
        if($entry.name -like '*WebView2*' -and $entry.pv -and $entry.pv -ne '0.0.0.0'){$webviewVersions+=$entry.pv}
    }}
}
Record 'WebView2Registration' ($webviewVersions.Count -gt 0) 'Registration only; map startup must still be exercised in the real application'
Record 'WindowsX64Process' ([Environment]::Is64BitOperatingSystem -and [Environment]::Is64BitProcess) 'Run the x64 package on Windows x64'
$result=[pscustomobject]@{
    kind='LOCAL_PREFLIGHT_ONLY';utc=[DateTime]::UtcNow.ToString('o');checks=$checks
    prerequisitesPass=($checks.Where({-not $_.passed}).Count -eq 0)
    sdkDetected=($sdks.Count -gt 0);cleanMachineQualification='NOT_TESTED'
    appWorkflowQualification='NOT_TESTED';licenseQualification='NOT_CLEARED_BY_THIS_SCRIPT'
}
$parent=Split-Path -Parent $reportPath
if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent | Out-Null}
[IO.File]::WriteAllText($reportPath,($result|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
$result|Select-Object kind,prerequisitesPass,sdkDetected,cleanMachineQualification
if(-not $result.prerequisitesPass){exit 1}
