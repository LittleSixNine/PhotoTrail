using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;

namespace PhotoTrail.Windows;

public partial class MainWindow
{
    // Preserve the old top-level track import of drop/CLI folders; photo recursion is independent.
    static Task<string[]> LegacyTrackInputsAsync(IEnumerable<string> paths)=>Task.Run(()=>paths.SelectMany(path=>Directory.Exists(path)&&(File.GetAttributes(path)&FileAttributes.ReparsePoint)==0?Directory.EnumerateFiles(path).Where(IsTrack):IsTrack(path)?new[]{path}:Array.Empty<string>()).Take(ImportQueue.MaximumFiles).Distinct(StringComparer.OrdinalIgnoreCase).ToArray());
    CancellationTokenSource? importCancellation;ImportQueue? importQueue;bool importPaused,importRunning;int importAccepted,importRead,importReadFailures,importReading;bool importPairing;DispatcherTimer? importTimer;
    double importEnumerationMs,importMetadataMs,importAcceptanceMs,firstThumbnailMs=-1;long importStartTicks;
    internal record PhotoDisplayGroup(long Id,string Label);
    private async Task ImportAsync(IEnumerable<string> paths)
    {
        if(importRunning||busy){ImportProgress.Text="已有任务运行；本次新导入未加入，请等待安全结束。";return;}var inputs=paths.Where(p=>!p.StartsWith("--",StringComparison.Ordinal)).ToArray();if(inputs.Length==0)return;
        var known=photos.Select(r=>r.Document.FilePath).ToArray();var remembered=photos.Where(r=>r.PhysicalIdentity is not null).ToDictionary(r=>r.Document.FilePath,r=>r.PhysicalIdentity!,StringComparer.OrdinalIgnoreCase);var recursive=settings.RecursiveImport;importPairing=settings.PairImport;importRunning=true;importPaused=false;importAccepted=importRead=importReadFailures=0;
        importCancellation=new();var token=importCancellation.Token;using var queue=new ImportQueue();importQueue=queue;
        var clock=System.Diagnostics.Stopwatch.StartNew();importStartTicks=System.Diagnostics.Stopwatch.GetTimestamp();firstThumbnailMs=-1;importMetadataMs=importAcceptanceMs=0;var exif=Interlocked.Read(ref ExifToolClient.RequestCount);var dates=Interlocked.Read(ref DateAdapter.StartedProcesses);
        importTimer=new DispatcherTimer(TimeSpan.FromMilliseconds(100),DispatcherPriority.Background,(_,_)=>RefreshImportProgress(),Dispatcher);importTimer.Start();ReadButton.IsEnabled=FolderButton.IsEnabled=false;ImportPause.IsEnabled=true;
        var producer=Task.Run(async()=>{var enumeration=System.Diagnostics.Stopwatch.StartNew();try{await queue.EnumerateAsync(inputs,recursive,known,token,remembered);}finally{importEnumerationMs=enumeration.Elapsed.TotalMilliseconds;}});bool cancelled=false;
        try{
            var tool=Tool();
            while(true){queue.Paused=importPaused||busy;var batch=await queue.TakeAsync(token);if(batch.Length==0)break;
                // A started read completes; saving/application owns acceptance until its safe end.
                importReading=batch.Length;var readClock=System.Diagnostics.Stopwatch.StartNew();var readings=await PhotoDocument.LoadBatchAsync(tool,batch.Select(s=>s.Path).ToArray(),CancellationToken.None,inspect:true);importMetadataMs+=readClock.Elapsed.TotalMilliseconds;importReading=0;importRead+=readings.Count;
                while(importPaused||busy){queue.Paused=true;await Task.Delay(30,token);}token.ThrowIfCancellationRequested();
                var acceptClock=System.Diagnostics.Stopwatch.StartNew();for(int i=0;i<readings.Count;i++){
                    var reading=readings[i];if(reading.Document is not {} doc){importReadFailures++;queue.Error(Path.GetFileName(reading.FilePath)+"："+reading.Error,false);continue;}
                    try{await Task.Run(()=>batch[i].RequireCurrent(),token);await doc.EnsureUnchangedAsync(token);if(doc.InspectionError.Length>0||doc.DateReadFailure.Length>0)throw new IOException("完整来源／共享日期尚未准备成功，未接纳。");if(!ImportSource.Types.Values.Contains(doc.FileType))throw new IOException("实际内容类型与候选扩展名不一致，未接纳。");
                        while(busy)await Task.Delay(30,token);token.ThrowIfCancellationRequested();batch[i].RequireCurrent();if(photos.Any(r=>r.Document.FilePath.Equals(doc.FilePath,StringComparison.OrdinalIgnoreCase))){queue.Skipped++;continue;}
                        var row=new PhotoRow(doc){PairEligible=importPairing,PhysicalIdentity=batch[i].Identity};photos.Add(row);importAccepted++;
                    }catch(OperationCanceledException){throw;}catch(Exception error)when(error is IOException or UnauthorizedAccessException or ArgumentException){importReadFailures++;queue.Error(Path.GetFileName(doc.FilePath)+"："+error.Message,false);}
                }
                AssignImportPairs();RefreshPhotoCount();SyncPhotoStrip();importAcceptanceMs+=acceptClock.Elapsed.TotalMilliseconds;
            }
            await producer;
        }catch(OperationCanceledException){cancelled=true;}catch(Exception error){queue.Error(error.Message,false);}
        finally{
            importCancellation.Cancel();try{await producer;}catch(OperationCanceledException){}catch(Exception error){queue.Error(error.Message,true);}
            importTimer.Stop();importTimer=null;importRunning=false;importQueue=null;ImportPause.IsEnabled=false;ImportPause.Content="暂停准备";ImportPending.ItemsSource=null;ReadButton.IsEnabled=FolderButton.IsEnabled=!busy;
            importMilliseconds=clock.Elapsed.TotalMilliseconds;importExifToolRequests=Interlocked.Read(ref ExifToolClient.RequestCount)-exif;importDateHostRequests=Interlocked.Read(ref DateAdapter.StartedProcesses)-dates;
        }
        if(!busy&&!InspectorHasInput()&&Photos.SelectedIndex<0&&photos.Count>0)Photos.SelectedIndex=0;
        foreach(var row in photos)if(queue.KnownFailures.TryGetValue(row.Document.FilePath,out var error))row.Document.InspectionError="来源重新核对失败，旧快照保留："+error;
        if(!busy&&!InspectorHasInput())RefreshSelection();else RefreshPhotoCount();_ = PostPhotosAsync();
        ImportProgress.Text=$"{(cancelled?"已取消":"准备结束")}：发现{queue.Discovered}，已读{importRead}，接纳{importAccepted}，跳过{queue.Skipped}，目录失败{queue.DirectoryFailures}，文件失败{queue.FileFailures}；未接纳{Math.Max(0,queue.Discovered-importAccepted-importReadFailures)}。已接纳与原草稿保留。";
        ImportProgress.ToolTip=string.Join("\n",queue.Errors);if(!busy)Status.Text="导入准备已结束；未修改原件、已有输入或草稿。";
    }
    void RefreshImportProgress()
    {
        if(importQueue is not {} queue)return;queue.Paused=importPaused||busy;
        ImportProgress.Text=$"{(busy?"等待保存／应用安全节点":importPaused?"暂停等待项":queue.EnumerationComplete?"读取／接纳":"枚举中，总数未知")}：已发现{queue.Discovered}，当前读取{importReading}，已读{importRead}，已接纳{importAccepted}，等待{queue.Waiting.Length}，跳过{queue.Skipped}，目录失败{queue.DirectoryFailures}，文件失败{queue.FileFailures}。";
        var chosen=(ImportPending.SelectedItem as ImportSource)?.Path;ImportPending.ItemsSource=queue.Waiting;if(chosen is not null)ImportPending.SelectedItem=queue.Waiting.FirstOrDefault(s=>s.Path==chosen);
    }
    void PauseImport(object sender,RoutedEventArgs e){if(!importRunning)return;importPaused=!importPaused;importQueue!.Paused=importPaused||busy;ImportPause.Content=importPaused?"继续准备":"暂停准备";RefreshImportProgress();}
    void PrioritizeImport(object sender,SelectionChangedEventArgs e){if(ImportPending.SelectedItem is ImportSource source)importQueue?.Prioritize(source.Path);}
    void ImportOptionsChanged(object sender,RoutedEventArgs e){if(!IsLoaded||restoringSettings)return;settings=settings with{RecursiveImport=ImportRecursive.IsChecked==true,PairImport=ImportPair.IsChecked==true};SaveSettings();ImportProgress.Text="导入选项已保存，仅作用下一次导入；当前队列和既有成员不重组。";}
    void AssignImportPairs()
    {
        foreach(var group in photos.Where(r=>r.PairEligible&&(r.Document.FileType=="JPEG"||ImportSource.Raw(r.Document.FileType))).GroupBy(r=>ImportSource.Stem(r.Document.FilePath),StringComparer.OrdinalIgnoreCase)){
            var jpeg=group.Where(r=>r.Document.FileType=="JPEG").ToArray();var raw=group.Where(r=>ImportSource.Raw(r.Document.FileType)).ToArray();
            if(jpeg.Length==1&&raw.Length==1){var id=group.Min(r=>r.Imported);foreach(var row in group){row.DisplayGroup=new(id,Path.GetFileNameWithoutExtension(jpeg[0].Document.FilePath)+" · JPG／RAW配对");row.PairStatus=ReferenceEquals(row,jpeg[0])?"JPEG主视图；RAW成员独立来源":"RAW成员；元数据与旁车独立，写入资格不扩展";}}
            else if(jpeg.Length>1||raw.Length>1)foreach(var row in group)row.PairStatus="同主体配对歧义；成员独立保留，不自动传播修改";
        }
        RefreshPhotoRows();
    }
}
