# Smoke test against DEPLOYED api.turnend.win — verifies the presign bug fix from cd615441
# Flow: login (real user) → POST /media/upload-url PUT→R2→204 → GET original presign works
import json, urllib.request, urllib.parse, hmac, hashlib, datetime, ssl, uuid
import os, sys

API='https://api.turnend.win'

def post_json(url, body, token=None):
    data=json.dumps(body).encode()
    req=urllib.request.Request(url,data=data,method='POST',headers={'content-type':'application/json',**({'authorization':f'Bearer {token}'} if token else {})})
    return urllib.request.urlopen(req, timeout=10)

def get_json(url, token=None, raw=False):
    req=urllib.request.Request(url, headers={**({'authorization':f'Bearer {token}'} if token else {})})
    return urllib.request.urlopen(req, timeout=10)

# 1. login as existing dev user
r = post_json(f'{API}/auth/login', {'email':'javier@example.com','password':'devpassword123'})
print('LOGIN_STATUS:', r.status)
if r.status != 200:
    sys.exit('login failed: '+r.read(200).decode())
auth = json.loads(r.read())
token = auth['access_token']
user_id = auth['user']['id']
print('user_id:', user_id[:8]+'...')

# 2. Request presigned PUT for album photo
r = post_json(f'{API}/media/upload-url', {'kind':'album','ext':'jpg'}, token)
print('UPLOAD_URL_STATUS:', r.status)
body = json.loads(r.read())
print('KEY:', body['key'])
print('URL:', body['put_url'][:160]+'...')
assert 'X-Amz-Content-Sha256=UNSIGNED-PAYLOAD' in body['put_url'], 'BUG cd615441 NOT FIXED: missing sha256 param'
print('OK: presign contains X-Amz-Content-Sha256=UNSIGNED-PAYLOAD  <-- cd615441 regression guard')

# 3. PUT to R2 via presigned URL
ctx = ssl.create_default_context()
payload = f'Vibra R2 deployed smoke {uuid.uuid4().hex[:8]} 2026-07-06'.encode()
put = urllib.request.Request(body['put_url'], data=payload, method='PUT',
                             headers={'content-type':'image/jpeg'})
with urllib.request.urlopen(put, timeout=15, context=ctx) as pr:
    print('R2_PUT_STATUS:', pr.status)
    assert pr.status in (200, 204), f'PUT failed: {pr.status}'
print('OK: PUT to R2 succeeded')

# 4. GET presign from /media/get-url and verify object is retrievable
r = get_json(f'{API}/media/get-url?key={urllib.parse.quote(body["key"])}&kind=album', token)
gb = json.loads(r.read())
get = urllib.request.Request(gb['get_url'])
with urllib.request.urlopen(get, timeout=15, context=ctx) as gr:
    print('R2_GET_STATUS:', gr.status)
    echo = gr.read()
    assert echo == payload, f'roundtrip mismatch: {echo[:30]!r} vs {payload[:30]!r}'
print('OK: GET roundtrip matches PUT payload')
