from selenium import webdriver
from selenium.webdriver.chrome.options import Options
import time

options = Options()
options.add_argument('--disable-gpu')

driver = webdriver.Chrome(options=options)

try:
    driver.get("https://stream.googleapiscdn.com/player/3f81e251fc47d91b697d84397fb326a0a330432f8cc1596e1bea08906bd2db91")
    time.sleep(10)
    html = driver.page_source
    with open('d:/code/animevietsub/AVS_iOS_App/iframe_dump.html', 'w', encoding='utf-8') as f:
        f.write(html)
finally:
    driver.quit()
