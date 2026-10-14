using System.Data;
using System.IO;

namespace PhotoTrail.Windows;

public partial class MainWindow
{
    void ComparisonColumn(object sender,System.Windows.Controls.DataGridAutoGeneratingColumnEventArgs e) {
        if(ComparisonGrid.ItemsSource is DataView view)e.Column.Header=view.Table?.Columns[e.PropertyName]?.Caption??e.PropertyName;
    }
    void RequireExchangeOutput(string path) {
        var target=Path.GetFullPath(path);
        if(photos.SelectMany(r=>r.Document.SidecarPath is {} sidecar?new[]{r.Document.FilePath,sidecar}:new[]{r.Document.FilePath}).Concat(tracks.Select(t=>t.Path)).Any(p=>Path.GetFullPath(p).Equals(target,StringComparison.OrdinalIgnoreCase)))
            throw new IOException("导出目标不能是当前照片、旁车或轨迹。");
    }
    PhotoDocument[] comparisonSelection=[];
    void RefreshComparison()
    {
        if(ComparisonTab is null||!ComparisonTab.IsSelected)return;
        comparisonSelection=Selected.Select(r=>r.Document.BatchSnapshot()).ToArray();
        ComparisonStatus.Text=$"展示{Math.Min(20,comparisonSelection.Length)}／实际冻结{comparisonSelection.Length}张；磁盘快照与含草稿有效值分列。CSV导出／应用另行冻结全部当前选择，不受20张显示上限影响。缺失／混合／读取失败文案只用于显示。";
        var shown=comparisonSelection.Take(20).ToArray();var table=new DataTable();
        var sources=comparisonSelection.ToDictionary(d=>d,d=>(d.Inspection??[]).GroupBy(v=>(v.Tag,v.Role)).ToDictionary(g=>g.Key,g=>g.Select(v=>v.Value).ToArray()));
        table.Columns.Add("精确字段");table.Columns.Add("来源");table.Columns.Add("全选择状态");
        foreach(var (doc,index) in shown.Select((d,i)=>(d,i)))
        {
            table.Columns.Add("disk"+index).Caption=$"{index+1} {Path.GetFileName(doc.FilePath)} · 磁盘";
            table.Columns.Add("effective"+index).Caption=$"{index+1} {Path.GetFileName(doc.FilePath)} · 含草稿";
        }
        var keys=comparisonSelection.SelectMany(d=>d.Inspection??[]).Select(v=>(v.Tag,v.Role)).Concat(
            comparisonSelection.SelectMany(d=>PhotoDocument.EditableTags.Select(tag=>(Tag:tag,Role:tag.StartsWith("XMP-",StringComparison.Ordinal)&&d.SidecarPath is not null?"旁车XMP":d.FileType=="XMP"?"独立XMP":"原图")))).Distinct().OrderBy(k=>k.Tag,StringComparer.Ordinal).ThenBy(k=>k.Role);
        foreach(var (tag,role) in keys)
        {
            string Disk(PhotoDocument doc)=>doc.InspectionError.Length>0?"读取失败／过期（旧快照保留）":sources[doc].TryGetValue((tag,role),out var entries)?entries.Length==1?entries[0]:"来源冲突："+System.Text.Json.JsonSerializer.Serialize(entries):
                (PhotoDocument.EditableTags.Contains(tag)&&(tag.StartsWith("XMP-",StringComparison.Ordinal)&&doc.SidecarPath is not null?"旁车XMP":doc.FileType=="XMP"?"独立XMP":"原图")==role?MetadataFields.Original(doc,tag):"");
            var values=comparisonSelection.Select(Disk).Distinct(StringComparer.Ordinal).ToArray();
            var cells=new List<string>{tag,role,comparisonSelection.Any(d=>d.InspectionError.Length>0)?"含读取失败／过期":values.Length>1?"混合（含缺失）":values.FirstOrDefault()?.Length>0?"一致":"缺失"};
            foreach(var doc in shown)
            {
                var disk=Disk(doc);bool target=(tag.StartsWith("XMP-",StringComparison.Ordinal)&&doc.SidecarPath is not null?"旁车XMP":doc.FileType=="XMP"?"独立XMP":"原图")==role;
                var effective=target&&doc.Draft.TryGetValue(tag,out var draft)?draft:disk;
                cells.Add(disk.Length==0?"（缺失）":disk);cells.Add(target&&doc.Draft.ContainsKey(tag)?effective.Length==0?"（草稿明确清除）":effective:effective.Length==0?"（缺失）":effective);
            }
            table.Rows.Add(cells.ToArray());
        }
        ComparisonGrid.ItemsSource=table.DefaultView;
    }
}
