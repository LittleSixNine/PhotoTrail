using System.IO;
using System.Text;
using System.Text.Json;
namespace PhotoTrail.Windows;

// JPEG Photoshop IIM records are compared as bytes, including legacy encodings and unknown datasets.
internal sealed class MetadataIptc
{
    internal static readonly Dictionary<string,(int Dataset,int Limit,bool List)> Fields=new() {
        ["IPTC:By-line"]=(80,32,true),["IPTC:By-lineTitle"]=(85,32,true),["IPTC:Contact"]=(118,128,true),["IPTC:Keywords"]=(25,64,true),
        ["IPTC:Headline"]=(105,256,false),["IPTC:Caption-Abstract"]=(120,2000,false),["IPTC:ObjectName"]=(5,64,false),
        ["IPTC:City"]=(90,32,false),["IPTC:Province-State"]=(95,32,false),["IPTC:Sub-location"]=(92,32,false),
        ["IPTC:Country-PrimaryLocationName"]=(101,64,false),["IPTC:Country-PrimaryLocationCode"]=(100,3,false)
    };
    internal sealed record Dataset(int Record,int Id,byte[] Value,byte[] Raw);
    internal readonly List<Dataset> Records=[];
    readonly List<byte[]> resources=[];
    readonly List<byte[]> exifBlocks=[];
    internal string Error {get;private set;}="";
    int blocks;
    internal string ReadState=>Error.Length>0?"原始数据集读取失败／结构不支持":Empty?"无IPTC：首次设置声明UTF8":Utf8?"明确UTF8":"编码未声明／非UTF8／冲突：设置拒绝，仅明确删除可验证";
    internal bool Utf8=>Records.Count(r=>r.Record==1&&r.Id==90)==1&&Records.Single(r=>r.Record==1&&r.Id==90).Value.SequenceEqual(new byte[]{27,37,71});
    internal bool Empty=>blocks==0&&Records.Count==0;
    internal void CheckDecodedSource(JsonElement metadata) {
        if(metadata.EnumerateObject().Any(f=>f.Name.Split(':')[^1] is "IPTC-NAA" or "IPTCData")||Empty&&metadata.EnumerateObject().Any(f=>f.Name.StartsWith("IPTC:",StringComparison.Ordinal)))
            Error="IPTC存在于未证明的原始容器中，不能当作无IPTC或迁移编码；保留只读。";
    }
    internal string PlanDescription(IReadOnlyDictionary<string,string> changes)=>!changes.Keys.Any(Fields.ContainsKey)?"":changes.Any(p=>Fields.ContainsKey(p.Key)&&p.Value.Length>0)?Empty?"；IPTC UTF8首次声明，必要记录版本4；其他原始数据集／资源保持":"；IPTC UTF8声明保持；必要缺失版本4独立核对":"；IPTC独立删除，编码声明及剩余原始数据集保持";
    internal static async Task<MetadataIptc> ReadAsync(string file,CancellationToken token) {
        var result=new MetadataIptc();
        try {result.Parse(await File.ReadAllBytesAsync(file,token));}
        catch(InvalidDataException e){result.Error=e.Message;}
        return result;
    }
    void Parse(byte[] b) {
        void Check(bool ok){if(!ok)throw new InvalidDataException("IPTC原始JPEG／Photoshop／IIM结构不可证明，保留只读。");}
        int U16(int p)=>b[p]*256+b[p+1];
        Check(b.Length>=4&&b[0]==255&&b[1]==216);int p=2;bool scan=false;
        while(p<b.Length) {
            if(scan){int next=b.AsSpan(p).IndexOf((byte)255);Check(next>=0);p+=next;}
            Check(b[p++]==255);while(p<b.Length&&b[p]==255)p++;Check(p<b.Length);int marker=b[p++];
            if(scan&&marker==0)continue;
            if(marker==217)break;
            if(marker==218)scan=true;
            if(marker is 1 or >=208 and <=215)continue;
            Check(p+2<=b.Length);int end=p+U16(p);Check(end>=p+2&&end<=b.Length);p+=2;
            if(marker==225&&end-p>=6&&b.AsSpan(p,6).SequenceEqual("Exif\0\0"u8))exifBlocks.Add(b.AsSpan(p,end-p).ToArray());
            if(marker==237) {
                if(end-p>=14&&b.AsSpan(p,14).SequenceEqual("Photoshop 3.0\0"u8)) {
                    p+=14;
                    while(p<end) {
                        int rs=p;Check(p+7<=end&&b.AsSpan(p,4).SequenceEqual("8BIM"u8));int id=U16(p+4);p+=6;
                        int nameSize=1+b[p];p+=nameSize+(nameSize%2);Check(p+4<=end);
                        uint length=((uint)b[p]<<24)|((uint)b[p+1]<<16)|((uint)b[p+2]<<8)|b[p+3];p+=4;Check(length<=int.MaxValue&&p+(long)length+(length%2)<=end);
                        int dataEnd=p+(int)length;
                        if(id==0x0404) {
                            blocks++;Check(blocks==1);
                            while(p<dataEnd) {
                                int ds=p;Check(p+5<=dataEnd&&b[p++]==28);int record=b[p++],dataset=b[p++],size=U16(p);p+=2;
                                if((size&32768)!=0){int count=size&32767;Check(count is >=1 and <=4&&p+count<=dataEnd);long extended=0;for(int i=0;i<count;i++)extended=extended*256+b[p++];Check(extended<=int.MaxValue);size=(int)extended;}
                                Check(p+(long)size<=dataEnd);var value=b.AsSpan(p,size).ToArray();p+=size;Records.Add(new(record,dataset,value,b.AsSpan(ds,p-ds).ToArray()));
                            }
                        }
                        p=dataEnd+(int)(length%2);
                        // Digest is intentionally NOT exempted: if a writer changes it, reject until independently proved.
                        if(id!=0x0404)resources.Add(b.AsSpan(rs,p-rs).ToArray());
                    }
                } else throw new InvalidDataException("未支持的APP13容器，不能证明完整IPTC来源；IPTC写入保留只读。");
            }
            p=end;
        }
    }
    internal void Require(IReadOnlyDictionary<string,string> changes) {
        var targets=changes.Where(p=>Fields.ContainsKey(p.Key)).ToArray();if(targets.Length==0)return;
        if(Error.Length>0)throw new ArgumentException(Error);
        foreach(var (tag,_) in targets)if(!Fields[tag].List&&Records.Count(r=>r.Record==2&&r.Id==Fields[tag].Dataset)>1)throw new ArgumentException("IPTC目标存在重复真实数据集，保留只读："+tag);
        if(targets.Any(p=>p.Value.Length>0)&&!Empty&&!Utf8)throw new ArgumentException("已有IPTC没有唯一明确UTF8声明；设置／追加／补空整次拒绝，不能隐式重编码。");
    }
    internal static void Validate(string tag,string value) {
        if(value.Length==0||!Fields.TryGetValue(tag,out var field))return;
        var values=field.List?MetadataFields.List(value):[value];
        if(values.Length==0)throw new ArgumentException("IPTC设置列表须非空；清除请使用明确清除。");
        foreach(var text in values) {
            int bytes=new UTF8Encoding(false,true).GetByteCount(text);
            if(bytes==0||bytes>field.Limit||text.Contains('\0'))throw new ArgumentException("IPTC值须非空、无NUL且不超过UTF8字节上限："+tag);
            if(tag=="IPTC:Country-PrimaryLocationCode"&&(bytes!=3||text.Any(c=>c is not(>='A' and <='Z' or >='a' and <='z'))))throw new ArgumentException("IPTC国家代码须恰好3个ASCII英文字母，保留大小写。");
        }
    }
    internal void Verify(MetadataIptc after,IReadOnlyDictionary<string,string> changes) {
        Require(changes);if(after.Error.Length>0)throw new InvalidDataException(after.Error);
        // APP13 layout can move ExifTool's absolute thumbnail offset without changing any EXIF bytes.
        if(changes.Keys.All(t=>t.StartsWith("XMP-",StringComparison.Ordinal)||Fields.ContainsKey(t))&&!exifBlocks.Select(Convert.ToHexString).SequenceEqual(after.exifBlocks.Select(Convert.ToHexString)))throw new InvalidDataException("IPTC修改改变了非目标EXIF APP1原始载荷，拒绝交付。");
        bool first=Empty&&changes.Any(p=>Fields.ContainsKey(p.Key)&&p.Value.Length>0);
        if(first&&!after.Utf8)throw new InvalidDataException("新IPTC的标准UTF8声明回读不一致。");
        foreach(var (tag,text) in changes.Where(p=>Fields.ContainsKey(p.Key))) {
            var field=Fields[tag];var expected=text.Length==0?Array.Empty<string>():field.List?MetadataFields.List(text):[text];
            var actual=after.Records.Where(r=>r.Record==2&&r.Id==field.Dataset).Select(r=>Convert.ToHexString(r.Value));
            if(!actual.SequenceEqual(expected.Select(v=>Convert.ToHexString(new UTF8Encoding(false,true).GetBytes(v)))))throw new InvalidDataException("IPTC目标原始字节／列表顺序回读不一致："+tag);
        }
        bool Target(Dataset r)=>r.Record==2&&changes.Keys.Any(t=>Fields.TryGetValue(t,out var field)&&field.Dataset==r.Id);
        bool NewVersion(Dataset r)=>changes.Any(p=>Fields.ContainsKey(p.Key)&&p.Value.Length>0)&&r.Id==0&&r.Record is 1 or 2&&!Records.Any(old=>old.Record==r.Record&&old.Id==0);
        string Key(Dataset r)=>Convert.ToHexString(r.Raw);
        var old=Records.Where(r=>!Target(r)).OrderBy(r=>r.Record).ThenBy(r=>r.Id).Select(Key).ToArray();
        var next=after.Records.Where(r=>!Target(r)&&!NewVersion(r)&&!(first&&r.Record==1&&r.Id==90)).OrderBy(r=>r.Record).ThenBy(r=>r.Id).Select(Key).ToArray();
        if(!old.SequenceEqual(next)||!resources.Select(Convert.ToHexString).SequenceEqual(after.resources.Select(Convert.ToHexString)))throw new InvalidDataException("剩余IPTC原始数据集或非目标Photoshop资源字节改变，拒绝交付。");
        // ExifTool creates envelope and application RecordVersion=4 with new IPTC; dataset layout may move, repeated values must retain order.
        if(after.Records.Where(NewVersion).Any(r=>!r.Value.SequenceEqual(new byte[]{0,4}))||after.Records.Where(NewVersion).GroupBy(r=>r.Record).Any(g=>g.Count()!=1))throw new InvalidDataException("新IPTC必要RecordVersion不符合已证明的唯一值。");
    }
}
