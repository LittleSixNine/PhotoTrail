param([string]$PublicRepository=(Join-Path $PSScriptRoot '../../..'),[string]$SwiftRoot='C:\BuildTools\PhotoTrailSwift64')
$ErrorActionPreference='Stop'
$utf=[Text.UTF8Encoding]::new($false)
$lock=Get-Content -LiteralPath "$PSScriptRoot/source-lock.json" -Raw|ConvertFrom-Json
$cache=Join-Path $PSScriptRoot '.cache';[void][IO.Directory]::CreateDirectory($cache)
$output=Join-Path $PSScriptRoot 'bin';[void][IO.Directory]::CreateDirectory($output)
$pi=[Diagnostics.ProcessStartInfo]::new();$pi.FileName=(Get-Command git).Source
$pi.UseShellExecute=$false;$pi.CreateNoWindow=$true;$pi.RedirectStandardOutput=$true;$pi.RedirectStandardError=$true
$pi.ArgumentList.Add('-C');$pi.ArgumentList.Add([IO.Path]::GetFullPath($PublicRepository));$pi.ArgumentList.Add('show');$pi.ArgumentList.Add($lock.commit+':'+$lock.path)
$process=[Diagnostics.Process]::Start($pi)
$source=Join-Path $cache 'MetadataDateEdit.swift'
$file=[IO.File]::Create($source);try{$process.StandardOutput.BaseStream.CopyTo($file)}finally{$file.Dispose()}
$errorText=$process.StandardError.ReadToEnd();$process.WaitForExit()
if($process.ExitCode -ne 0){throw $errorText}
$actual=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLower()
if($actual -ne $lock.sha256){throw 'Git source SHA mismatch; no private-copy fallback'}
$identity="enum BuildIdentity { static let version = `"$($lock.version)`"; static let commit = `"$($lock.commit)`"; static let path = `"$($lock.path)`"; static let sha256 = `"$actual`" }`n"
[IO.File]::WriteAllText((Join-Path $cache 'BuildIdentity.swift'),$identity,$utf)
$bin=Join-Path $SwiftRoot "Toolchains/$($lock.toolchain)+Asserts/usr/bin"
$runtime=Join-Path $SwiftRoot "Runtimes/$($lock.toolchain)/usr/bin"
$env:Path="$bin;$runtime;"+$env:Path
$env:SDKROOT=Join-Path $SwiftRoot "Platforms/$($lock.toolchain)/Windows.platform/Developer/SDKs/Windows.sdk"
& "$bin/swiftc.exe" -O $source "$cache/BuildIdentity.swift" "$PSScriptRoot/Host/Host.swift" -o "$output/DateHost.exe"
if($LASTEXITCODE){throw 'Swift host compile failed'}
Get-ChildItem -LiteralPath $runtime -File -Filter '*.dll'|Copy-Item -Destination $output
dotnet build "$PSScriptRoot/Checks/Caller.csproj" -o "$PSScriptRoot/caller-bin"
if($LASTEXITCODE){throw 'C# build failed'}
[IO.File]::WriteAllText("$cache/build-source.json",($lock|ConvertTo-Json)+"`n",$utf)
Write-Output 'Source exported from fixed public Git object and SHA verified; no production tree changed'
