from selenium import webdriver
from selenium.webdriver.chrome.options import Options
import time

options = Options()
options.add_argument('--disable-gpu')

print("Starting Chrome...")
driver = webdriver.Chrome(options=options)

try:
    driver.get("https://stream.googleapiscdn.com/player/3f81e251fc47d91b697d84397fb326a0a330432f8cc1596e1bea08906bd2db91")
    time.sleep(10)
    html = driver.page_source
    print("IFRAME HTML STARTS WITH:")
    print(html[:1500])
finally:
    driver.quit()
