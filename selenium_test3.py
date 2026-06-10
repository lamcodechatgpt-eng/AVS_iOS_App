from selenium import webdriver
from selenium.webdriver.chrome.options import Options
import time

options = Options()
options.add_argument('--disable-gpu')

print("Starting Chrome...")
driver = webdriver.Chrome(options=options)

try:
    driver.get("https://animevietsub.by/ajax/player?v=2019a")
    time.sleep(2)
    # Let's run a manual POST to the backup link API
    script = """
    return fetch('https://animevietsub.by/ajax/player?v=2019a', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-Requested-With': 'XMLHttpRequest'
        },
        body: 'episode_id=113821&backup=1'
    }).then(r => r.text());
    """
    backup_data = driver.execute_script(script)
    print("Backup Data:")
    print(backup_data)

finally:
    driver.quit()
