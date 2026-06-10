import urllib.request
try:
    url = 'https://stream.googleapiscdn.com/player/534c032f0ace0f1807ae5e01dc0acad8213315ac3ee1c1309a5723997e4aa0e5?isFinal=1'
    req = urllib.request.Request(url)
    req.add_header('User-Agent', 'Mozilla/5.0')
    req.add_header('Referer', 'https://animevietsub.by/')
    resp = urllib.request.urlopen(req)
    html = resp.read().decode('utf-8')
    import re
    m3u8 = re.findall(r'https?://.*?\.m3u8.*', html)
    print("Found m3u8:", len(m3u8))
    if m3u8:
        print(m3u8[0][:200])
except Exception as e:
    print("Error:", e)
