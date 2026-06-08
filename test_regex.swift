import Foundation

let path = "d:\code\animevietsub\trangchu.html"
let html = try! String(contentsOfFile: path, encoding: .utf8)

let pattern = "<article id=\"post-[\\s\\S]*?<a href=\"([^\\"]+)\"[\\s\\S]*?<img[\\s\\S]*?src=\"([^\\"]+)\"[\\s\\S]*?<span class=\"mli-eps\">(.*?)</span>[\\s\\S]*?<h2 class=\"Title\">([^<]+)</h2>"
let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

print("Found \(matches.count) movies")
