using System;
class Program {
    static void Main() {
        Uri uri = new Uri("https://s3.collaps.io/hls/1234/master.m3u8");
        Console.WriteLine(uri.AbsolutePath);
    }
}
