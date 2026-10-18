param(
 [Parameter(Mandatory)][string]$OutputRoot,
 [string]$PublicRepository=(Join-Path $PSScriptRoot '../../..'),
 [string]$SwiftRoot='C:\BuildTools\PhotoTrailSwift64',
 [string]$ManifestTool='C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\mt.exe'
)
$ErrorActionPreference='Stop'
$output=[IO.Path]::GetFullPath($OutputRoot)
if(Test-Path -LiteralPath $output){throw 'Use a new isolated output directory; previous evidence is retained.'}
$lock=Get-Content -LiteralPath "$PSScriptRoot/source-lock.json" -Raw|ConvertFrom-Json
$bin=Join-Path $SwiftRoot "Toolchains/$($lock.toolchain)+Asserts/usr/bin"
$runtime=Join-Path $SwiftRoot "Runtimes/$($lock.toolchain)/usr/bin"
$original=Join-Path $bin 'swift-test.exe'
foreach($required in @($original,$ManifestTool,(Join-Path $bin 'swiftc.exe'))){if(-not(Test-Path -LiteralPath $required -PathType Leaf)){throw "Missing existing tool: $required"}}
[void][IO.Directory]::CreateDirectory($output)
$originalHash=(Get-FileHash -LiteralPath $original).Hash
$exe=Join-Path $output 'swift-test.exe'
Copy-Item -LiteralPath $original -Destination $exe
$manifest=Join-Path $output 'original.manifest'
& $ManifestTool ("-inputresource:"+$exe+';#1') ("-out:"+$manifest) *> (Join-Path $output 'manifest-extract.log')
if($LASTEXITCODE){throw 'Cannot extract diagnostic manifest'}
[xml]$xml=Get-Content -LiteralPath $manifest -Raw
# Only the diagnostic copy uses ordinary DLL resolution; the installed tool remains unchanged.
@($xml.assembly.dependency)|ForEach-Object {[void]$xml.assembly.RemoveChild($_)}
$diagnosticManifest=Join-Path $output 'diagnostic.manifest'
$xml.Save($diagnosticManifest)
& $ManifestTool -manifest $diagnosticManifest ("-outputresource:"+$exe+';#1') *> (Join-Path $output 'manifest-embed.log')
if($LASTEXITCODE){throw 'Cannot embed diagnostic manifest'}
Get-ChildItem -LiteralPath (Join-Path $bin '../share/pm') -Directory -Filter '*.resources'|ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $output -Recurse}
$prefix='Packages/PhotoTrailDateCore/'
$paths=& git -C $PublicRepository ls-tree -r --name-only $lock.commit $prefix
if($LASTEXITCODE -or -not $paths){throw 'Fixed package source unavailable'}
$sources=@()
foreach($path in $paths){
 $target=Join-Path $output ('package/'+$path.Substring($prefix.Length))
 [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
 $start=[Diagnostics.ProcessStartInfo]::new((Get-Command git).Source)
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true
 foreach($arg in @('-C',$PublicRepository,'show',($lock.commit+':'+$path))){$start.ArgumentList.Add($arg)}
 $child=[Diagnostics.Process]::Start($start);$file=[IO.File]::Create($target)
 try{$child.StandardOutput.BaseStream.CopyTo($file)}finally{$file.Dispose()}
 $child.WaitForExit();if($child.ExitCode){throw 'Fixed Git export failed'}
 $sources+=@{path=$path;sha256=(Get-FileHash -LiteralPath $target).Hash;bytes=(Get-Item -LiteralPath $target).Length}
}
$coreFile=Join-Path $output ('package/'+$lock.path.Substring($prefix.Length))
if((Get-FileHash -LiteralPath $coreFile).Hash.ToLower() -ne $lock.sha256){throw 'Locked core SHA mismatch'}
$oldPath=$env:Path;$oldSdk=$env:SDKROOT;$oldSwift=$env:SWIFT_EXEC
try{
 $env:Path="$bin;$runtime;"+$oldPath
 $env:SDKROOT=Join-Path $SwiftRoot "Platforms/$($lock.toolchain)/Windows.platform/Developer/SDKs/Windows.sdk"
 $env:SWIFT_EXEC=Join-Path $bin 'swiftc.exe'
 & $exe --package-path (Join-Path $output 'package') --scratch-path (Join-Path $output 'build') --toolchain (Join-Path $bin '..') --disable-sandbox --jobs 2 *> (Join-Path $output 'package-test.log')
 $result=$LASTEXITCODE
}finally{$env:Path=$oldPath;$env:SDKROOT=$oldSdk;$env:SWIFT_EXEC=$oldSwift}
if((Get-FileHash -LiteralPath $original).Hash -ne $originalHash){throw 'Installed tool identity changed'}
@{commit=$lock.commit;sources=$sources;exitCode=$result;originalToolSha256=$originalHash;diagnosticToolSha256=(Get-FileHash -LiteralPath $exe).Hash;scope='Isolated diagnostic tool only. Not production DateHost, clean deployment or redistribution qualification.'}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $output 'result.json') -Encoding utf8
if($result){throw "Package tests failed ($result); isolated logs and sources retained."}
