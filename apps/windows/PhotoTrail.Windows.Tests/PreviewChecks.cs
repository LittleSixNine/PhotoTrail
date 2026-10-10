using System.Security.Cryptography;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using PhotoTrail.Windows;

static class PreviewChecks
{
    public static async Task RunAsync()
    {
        var root = Environment.GetEnvironmentVariable("PHOTOTRAIL_TEST_OUTPUT") ?? throw new Exception("Missing test output");
        var folder = Path.Combine(root,"preview-checks-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
        var count = 0;
        void Check(bool ok,string label){if(!ok)throw new Exception(label);count++;Console.WriteLine("PASS "+label);}
        void Reject(Action action,string label){try{action();}catch(Exception error) when(error is ArgumentException or IOException or InvalidDataException or NotSupportedException or System.IO.FileFormatException){Check(true,label);return;}throw new Exception(label);}
        var pixels = Enumerable.Range(1,8).SelectMany(i=>new byte[]{(byte)(i*25),(byte)(i*11),(byte)(i*7),255}).ToArray();
        var png=Path.Combine(folder,"orientation.png");
        var frame=BitmapSource.Create(4,2,96,96,PixelFormats.Bgra32,null,pixels,16);frame.Freeze();
        using(var output=File.Create(png)){var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(frame));encoder.Save(output);}
        var hash=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(png)));
        var expected = new[]{new[]{1,2,3,4,5,6,7,8},new[]{4,3,2,1,8,7,6,5},new[]{8,7,6,5,4,3,2,1},new[]{5,6,7,8,1,2,3,4},
            new[]{1,5,2,6,3,7,4,8},new[]{5,1,6,2,7,3,8,4},new[]{8,4,7,3,6,2,5,1},new[]{4,8,3,7,2,6,1,5}};
        for(var orientation=1;orientation<=8;orientation++)
        {
            var image=await Task.Run(()=>PhotoPreview.Load(png,"PNG",hash,orientation));
            Check(image.IsFrozen && image.PixelWidth==(orientation<=4?4:2) && image.PixelHeight==(orientation<=4?2:4),"orientation dimensions/frozen for UI: "+orientation);
            var converted=new FormatConvertedBitmap(image,PixelFormats.Bgra32,null,0);var actual=new byte[32];converted.CopyPixels(actual,image.PixelWidth*4,0);
            Check(expected[orientation-1].SelectMany(i=>pixels.AsSpan((i-1)*4,4).ToArray()).SequenceEqual(actual),"exact asymmetric orientation pixels: "+orientation);
        }
        using(var exclusive=new FileStream(png,FileMode.Open,FileAccess.ReadWrite,FileShare.None))Check(exclusive.Length>0,"preview releases source file for later rename/save");
        Check(Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(png)))==hash,"all previews leave source bytes unchanged");
        var jpeg=Path.Combine(folder,"large.jpg");var large=BitmapSource.Create(1024,512,96,96,PixelFormats.Bgra32,null,new byte[1024*512*4],1024*4);
        using(var output=File.Create(jpeg)){var encoder=new JpegBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(large));encoder.Save(output);}
        var jpegHash=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(jpeg)));var scaled=await Task.Run(()=>PhotoPreview.Load(jpeg,"JPEG",jpegHash));
        Check(scaled.PixelWidth==512 && scaled.PixelHeight==256,"large JPEG preview fits 512-pixel bound with aspect ratio");
        var rotated=await Task.Run(()=>PhotoPreview.Load(jpeg,"JPEG",jpegHash,6));Check(rotated.PixelWidth==256&&rotated.PixelHeight==512,"rotated JPEG stays bounded");
        Reject(()=>PhotoPreview.Load(png,"PNG",new string('0',64)),"changed source baseline refused");
        Reject(()=>PhotoPreview.Load(png,"JPEG",hash),"mismatched actual image format refused");
        Reject(()=>PhotoPreview.Load(png,"DNG",hash),"unsupported preview format refuses without codec dependency");
        Reject(()=>PhotoPreview.Load(png,"PNG",hash,9),"invalid orientation refused");
        var oversized=Path.Combine(folder,"oversized.jpg");using(var file=File.Create(oversized))file.SetLength(PhotoPreview.MaximumBytes+1);
        Reject(()=>PhotoPreview.Load(oversized,"JPEG",""),"oversized preview refused before hashing/decoding");
        var invalid=Path.Combine(folder,"invalid.jpg");File.WriteAllText(invalid,"not an image");var invalidHash=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(invalid)));
        Reject(()=>PhotoPreview.Load(invalid,"JPEG",invalidHash),"damaged image refuses rather than displaying old preview");
        Console.WriteLine($"Preview checks complete: {count}; evidence {folder}");
    }
}
