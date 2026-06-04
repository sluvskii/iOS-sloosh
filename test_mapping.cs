using System;
using System.Text;

class Program {
    static void Main() {
        string text = "494595//hls/1234/master.m3u8";
        string base64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(text));
        
        StringBuilder sb = new StringBuilder();
        foreach (char c in base64) {
            sb.Append(c switch {
                'A' => 'D', 'B' => 'l', 'C' => 'C', 'D' => 'h', 'E' => 'E', 'F' => 'X', 'G' => 'i', 'H' => 't', 'I' => 'L', 'J' => 'O',
                'K' => 'N', 'L' => 'Y', 'M' => 'R', 'N' => 'k', 'O' => 'F', 'P' => 'j', 'Q' => 'A', 'R' => 's', 'S' => 'n', 'T' => 'B',
                'U' => 'b', 'V' => 'y', 'W' => 'm', 'X' => 'W', 'Y' => 'z', 'Z' => 'S', 'a' => 'H', 'b' => 'M', 'c' => 'q', 'd' => 'K',
                'e' => 'P', 'f' => 'g', 'g' => 'Q', 'h' => 'Z', 'i' => 'p', 'j' => 'v', 'k' => 'w', 'l' => 'e', 'm' => 'r', 'n' => 'o',
                'o' => 'f', 'p' => 'J', 'q' => 'T', 'r' => 'V', 's' => 'd', 't' => 'I', 'u' => 'u', 'v' => 'U', 'w' => 'c', 'x' => 'x',
                'y' => 'a', 'z' => 'G',
                _ => c
            });
        }
        Console.WriteLine(sb.ToString());
    }
}
