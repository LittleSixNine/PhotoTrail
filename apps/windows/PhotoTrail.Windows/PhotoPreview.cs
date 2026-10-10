using System.IO;
using System.Security.Cryptography;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace PhotoTrail.Windows;

public static class PhotoPreview
{
    public const long MaximumBytes = 64L * 1024 * 1024;
    public const int MaximumDimension = 512;
    public static async Task<BitmapSource> LoadDngAsync(ExifToolClient client, string path, string expectedHash, int orientation, CancellationToken cancellation = default)
    {
        cancellation.ThrowIfCancellationRequested();
        using var source = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (source.Length is < 1 or > MaximumBytes) throw new InvalidDataException("预览文件须为1字节至64MiB。");
        if (Convert.ToHexString(await SHA256.HashDataAsync(source, cancellation)) != expectedHash)
            throw new IOException("照片已在外部改变，请重新导入后预览。");
        var temporary = Path.Combine(Path.GetTempPath(), "PhotoTrail-preview-" + Guid.NewGuid().ToString("N") + ".jpg");
        try
        {
            // A basename in the native working directory avoids ExifTool interpreting % codes in user paths.
            await client.RunAsync(["-charset", "filename=UTF8", "-b", "-PreviewImage", "-W", Path.GetFileName(temporary), "--", Path.GetFullPath(path)], cancellation, workingDirectory: Path.GetDirectoryName(temporary));
            if (!File.Exists(temporary)) throw new NotSupportedException("DNG没有可用的内嵌JPEG预览；仍可读取元数据。");
            using var preview = new FileStream(temporary, FileMode.Open, FileAccess.Read, FileShare.Read);
            if (preview.Length is < 1 or > MaximumBytes) throw new InvalidDataException("内嵌预览大小无效或超过64MiB。");
            var hash = Convert.ToHexString(await SHA256.HashDataAsync(preview, cancellation));
            cancellation.ThrowIfCancellationRequested();
            return Load(temporary, "JPEG", hash, orientation);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    public static BitmapSource Load(string path, string fileType, string expectedHash, int orientation = 1)
    {
        if (fileType is not ("JPEG" or "PNG")) throw new NotSupportedException("当前预览支持JPEG/PNG；其他格式仍可读取元数据。");
        if (orientation is < 1 or > 8) throw new ArgumentException("图像方向无效。");
        using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (file.Length is < 1 or > MaximumBytes) throw new InvalidDataException("预览文件须为1字节至64MiB。");
        if (Convert.ToHexString(SHA256.HashData(file)) != expectedHash) throw new IOException("照片已在外部改变，请重新导入后预览。");
        file.Position = 0;
        var decoder = BitmapDecoder.Create(file, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.None);
        if ((fileType == "JPEG" && decoder is not JpegBitmapDecoder) || (fileType == "PNG" && decoder is not PngBitmapDecoder))
            throw new InvalidDataException("图像格式已改变，请重新导入。");
        var frame = decoder.Frames[0];
        if (frame.PixelWidth < 1 || frame.PixelHeight < 1 || (long)frame.PixelWidth * frame.PixelHeight > 100_000_000)
            throw new InvalidDataException("预览尺寸超过一亿像素上限。");
        file.Position = 0;
        var image = new BitmapImage(); image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad; image.StreamSource = file;
        if (Math.Max(frame.PixelWidth, frame.PixelHeight) > MaximumDimension)
        {
            if (frame.PixelWidth >= frame.PixelHeight) image.DecodePixelWidth = MaximumDimension;
            else image.DecodePixelHeight = MaximumDimension;
        }
        image.EndInit(); image.Freeze();
        var matrix = orientation switch
        {
            2 => new Matrix(-1,0,0,1,0,0), 3 => new Matrix(-1,0,0,-1,0,0), 4 => new Matrix(1,0,0,-1,0,0),
            5 => new Matrix(0,1,1,0,0,0), 6 => new Matrix(0,1,-1,0,0,0),
            7 => new Matrix(0,-1,-1,0,0,0), 8 => new Matrix(0,-1,1,0,0,0), _ => Matrix.Identity
        };
        var result = new TransformedBitmap(image, new MatrixTransform(matrix)); result.Freeze();
        return result;
    }
}
