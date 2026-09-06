#!/usr/bin/env python3
"""Upload App Store App Preview via ASC reserve + curl upload + commit."""
from __future__ import annotations
import hashlib, json, pathlib, subprocess, sys, time

TOKEN = pathlib.Path('/tmp/asc_token.txt').read_text().strip()
API = 'https://api.appstoreconnect.apple.com'
LOC = '332cd8cf-931d-40d1-bb48-5d8367a05962'

def curl_json(method, path, body=None):
    out = pathlib.Path('/tmp/asc_tmp_out.json')
    cmd = ['curl','-g','-sS','-X',method,'-H',f'Authorization: Bearer {TOKEN}','-H','Accept: application/json','-o',str(out),'-w','%{http_code}']
    if body is not None:
        body_file = pathlib.Path('/tmp/asc_tmp_body.json')
        body_file.write_text(json.dumps(body))
        cmd += ['-H','Content-Type: application/json','--data-binary',f'@{body_file}']
    cmd.append(path if path.startswith('http') else API+path)
    code = subprocess.check_output(cmd, text=True).strip()
    data = json.loads(out.read_text() or '{}')
    if not code.startswith('2'):
        raise SystemExit(f'{method} {path} -> {code} {json.dumps(data)[:1200]}')
    return data

def ensure_set(preview_type: str) -> str:
    listing = curl_json('GET', f'/v1/appStoreVersionLocalizations/{LOC}/appPreviewSets')
    for s in listing.get('data') or []:
        if s['attributes'].get('previewType') == preview_type:
            print(f'using existing preview set {s["id"]} {preview_type}')
            return s['id']
    created = curl_json('POST', '/v1/appPreviewSets', {
        'data': {
            'type': 'appPreviewSets',
            'attributes': {'previewType': preview_type},
            'relationships': {
                'appStoreVersionLocalization': {
                    'data': {'type': 'appStoreVersionLocalizations', 'id': LOC}
                }
            }
        }
    })
    sid = created['data']['id']
    print(f'created preview set {sid} {preview_type}')
    return sid

def upload_file(set_id: str, path: pathlib.Path):
    raw = path.read_bytes()
    size = len(raw)
    reserved = curl_json('POST', '/v1/appPreviews', {
        'data': {
            'type': 'appPreviews',
            'attributes': {'fileName': path.name, 'fileSize': size},
            'relationships': {
                'appPreviewSet': {'data': {'type': 'appPreviewSets', 'id': set_id}}
            }
        }
    })
    preview_id = reserved['data']['id']
    ops = reserved['data']['attributes']['uploadOperations']
    print(f'reserved {preview_id} ops={len(ops)} size={size}')
    for op in ops:
        url = op['url']
        method = op['method']
        headers = {h['name']: h['value'] for h in op.get('requestHeaders') or []}
        offset = op.get('offset', 0)
        length = op.get('length', size)
        chunk = raw[offset:offset+length]
        chunk_path = pathlib.Path('/tmp/asc_chunk.bin')
        chunk_path.write_bytes(chunk)
        hdr_args = []
        for k,v in headers.items():
            hdr_args += ['-H', f'{k}: {v}']
        cmd = ['curl','-g','-sS','-X',method, *hdr_args, '--data-binary', f'@{chunk_path}', '-o','/tmp/asc_upload_resp.bin','-w','%{http_code}', url]
        code = subprocess.check_output(cmd, text=True).strip()
        if not code.startswith('2'):
            raise SystemExit(f'upload chunk failed http={code}')
        print(f'  uploaded chunk offset={offset} len={length} http={code}')
    md5 = hashlib.md5(raw).hexdigest()
    committed = curl_json('PATCH', f'/v1/appPreviews/{preview_id}', {
        'data': {
            'type': 'appPreviews',
            'id': preview_id,
            'attributes': {
                'uploaded': True,
                'sourceFileChecksum': md5
            }
        }
    })
    state = committed['data']['attributes'].get('assetDeliveryState')
    print(f'committed {preview_id} state={state}')
    return preview_id

def wait_complete(preview_id: str, timeout_s: int = 600):
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        data = curl_json('GET', f'/v1/appPreviews/{preview_id}')
        state = data['data']['attributes'].get('assetDeliveryState') or {}
        print(f'poll {preview_id} state={state}')
        if state.get('state') == 'COMPLETE':
            return state
        if state.get('state') in ('FAILED', 'INVALID'):
            raise SystemExit(f'preview processing failed: {state}')
        time.sleep(8)
    raise SystemExit(f'timeout waiting for COMPLETE on {preview_id}')

def main():
    preview_type = sys.argv[1]
    path = pathlib.Path(sys.argv[2])
    set_id = ensure_set(preview_type)
    preview_id = upload_file(set_id, path)
    final = wait_complete(preview_id)
    print('DONE', json.dumps({'previewSetId': set_id, 'previewId': preview_id, 'previewType': preview_type, 'state': final}))

if __name__ == '__main__':
    main()
