from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import time

options = Options()
options.add_argument('--disable-gpu')

print("Starting Chrome...")
driver = webdriver.Chrome(options=options)

try:
    print("Navigating to iframe...")
    # Iframe from previous selenium script
    driver.get("https://stream.googleapiscdn.com/player/3f81e251fc47d91b697d84397fb326a0a330432f8cc1596e1bea08906bd2db91?nextName=10&nextUrl=...")
    
    # Wait for the player to initialize
    time.sleep(10)
    
    html = driver.page_source
    if ".m3u8" in html:
        print("YES! m3u8 is in the HTML!")
    else:
        print("NO! m3u8 is NOT in the HTML!")
        print("Let's check Network requests for m3u8 via JS...")
        logs = driver.execute_script("return window.performance.getEntriesByType('resource').map(e => e.name);")
        for log in logs:
            if ".m3u8" in log:
                print(f"Found m3u8 in network logs: {log}")
finally:
    driver.quit()
