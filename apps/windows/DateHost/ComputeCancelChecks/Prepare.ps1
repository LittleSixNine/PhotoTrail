$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot '../../PhotoTrail.Windows/DateAdapter.cs'
$text=[IO.File]::ReadAllText($source)
$marker='marked = true; CalculationStarted?.Invoke();'
$exit='await process.WaitForExitAsync(); LastChildExited = process.HasExited;'
foreach($needle in @($marker,$exit)){if($text.IndexOf($needle) -lt 0 -or $text.IndexOf($needle) -ne $text.LastIndexOf($needle)){throw 'Production observation point changed'}}
# Test-only passive observations; no pacing, token changes, fake host or altered wire data.
$text=$text.Replace($marker,'marked = true; ComputeCancelProbe.Started(process, output!, requestId, items?.Length ?? 0); CalculationStarted?.Invoke();')
$text=$text.Replace($exit,$exit+' ComputeCancelProbe.Exited(process, output!, requestId, AcceptedFrames, PublishedCalls);')
$cache=Join-Path $PSScriptRoot '.cache';[void][IO.Directory]::CreateDirectory($cache)
[IO.File]::WriteAllText((Join-Path $cache 'DateAdapter.cs'),$text,[Text.UTF8Encoding]::new($false))
Get-FileHash -LiteralPath $source,(Join-Path $cache 'DateAdapter.cs') -Algorithm SHA256
