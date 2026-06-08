from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import time
import json

options = Options()
options.add_argument('--headless=new')
options.add_argument('--disable-gpu')
options.add_argument('--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')

print("Starting Chrome...")
driver = webdriver.Chrome(options=options)

try:
    print("Navigating to animevietsub.by...")
    driver.get("https://animevietsub.by/")
    
    # Wait for the movie list to load
    print("Waiting for TPostMv to load...")
    WebDriverWait(driver, 20).until(
        EC.presence_of_element_located((By.CLASS_NAME, "TPostMv"))
    )
    
    html = driver.page_source
    print(f"Loaded Home HTML! Length: {len(html)}")
    
    # Find the home-v1.js link
    js_links = driver.find_elements(By.XPATH, "//script[contains(@src, 'home-v1.js')]")
    for link in js_links:
        print(f"Found JS: {link.get_attribute('src')}")
        
    # Pick a movie and get its watch link
    movie = driver.find_element(By.XPATH, "//article[contains(@class, 'TPost')]/a")
    movie_link = movie.get_attribute('href')
    print(f"Navigating to movie: {movie_link}")
    
    driver.get(movie_link)
    WebDriverWait(driver, 20).until(
        EC.presence_of_element_located((By.XPATH, "//a[contains(@href, '-tap-')]"))
    )
    
    watch_link = driver.find_element(By.XPATH, "//a[contains(@href, '-tap-')]").get_attribute('href')
    print(f"Navigating to watch page: {watch_link}")
    
    driver.get(watch_link)
    # Wait for player
    WebDriverWait(driver, 20).until(
        lambda d: d.execute_script("return typeof window.PLAYER_DATA !== 'undefined'")
    )
    
    player_data = driver.execute_script("return window.PLAYER_DATA;")
    print("Extracted PLAYER_DATA:")
    print(json.dumps(player_data, indent=2))
    
    ghost_js = driver.find_elements(By.XPATH, "//script[contains(@src, 'ghost.js')]")
    for script in ghost_js:
         print(f"Found Ghost JS: {script.get_attribute('src')}")

finally:
    driver.quit()
