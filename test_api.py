import urllib.request
import re

headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0 Safari/537.36'}

req = urllib.request.Request('https://animevietsub.by/', headers=headers)
html = urllib.request.urlopen(req).read().decode('utf-8')

# Find token
token_match = re.search(r'"token":"(.*?)"', html)
if token_match:
    token = token_match.group(1)
    print(f"Found token: {token}")
    
    # POST
    data = b"widget=list-film&type=new-update"
    req_ajax = urllib.request.Request(f'https://animevietsub.by/ajax/item?_fxToken={token}', data=data, headers=headers)
    ajax_resp = urllib.request.urlopen(req_ajax).read().decode('utf-8')
    print("AJAX Response starts with:")
    print(ajax_resp[:500])
else:
    print("No token found")
