import requests

BASE = 'http://127.0.0.1:8000'

for path in ['/api/model-info', '/api/seasonal-crops?region=Hill&month=5', '/api/seasonal_crops?region=Hill&month=5', '/api/debug-seasonal']:
    try:
        r = requests.get(BASE + path, timeout=5)
        print(path, r.status_code)
        print(r.text[:1000])
    except Exception as e:
        print(path, 'ERROR', e)
