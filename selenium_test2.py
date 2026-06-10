from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import time
import json

options = Options()
# Do NOT use headless so Cloudflare passes automatically!
options.add_argument('--disable-gpu')

print("Starting Chrome...")
driver = webdriver.Chrome(options=options)

try:
    print("Navigating to animevietsub.by...")
    driver.get("https://animevietsub.by/phim/needy-girl-overdose-a5807/tap-10-113821.html")
    
    # Wait for Cloudflare to pass (up to 30 seconds)
    print("Waiting for page load...")
    WebDriverWait(driver, 30).until(
        lambda d: d.execute_script("return typeof window.PLAYER_DATA !== 'undefined'")
    )
    
    player_data = driver.execute_script("return window.PLAYER_DATA;")
    print("Extracted PLAYER_DATA:")
    print(json.dumps(player_data, indent=2))
    
    # Now load the iframe
    iframe_link = player_data.get('link')
    if iframe_link:
        print(f"Loading iframe: {iframe_link}")
        driver.get(iframe_link)
        time.sleep(5)
        iframe_html = driver.page_source
        if ".m3u8" in iframe_html:
            print("FOUND m3u8 in iframe!")
            # Extract it
            import re
            match = re.search(r'(?i)file\s*:\s*["\'](https?://.*?\.m3u8.*?)["\']', iframe_html)
            if match:
                print(f"M3U8 Link: {match.group(1)}")
        else:
            print("NO m3u8 found in iframe HTML. Dumping first 1000 chars:")
            print(iframe_html[:1000])

finally:
    driver.quit()
