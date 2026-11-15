import os
import json
import pytest
from fastapi.testclient import TestClient

# Ensure the backend directory is on PYTHONPATH for imports
os.environ['PYTHONPATH'] = os.path.abspath('backend')

from app.main import app

client = TestClient(app)

# Helper to set auth headers (prototype user auth)
def auth_headers(user_id, role):
    return {
        'X-User-Id': user_id,
        'X-User-Role': role,
        'Content-Type': 'application/json'
    }

def test_full_workflow():
    # 1. Create a brand check as creator (u1)
    resp = client.post('/api/v1/brand/check', json={
        'brand_name': 'Acme',
        'content': 'original content',
        'content_type': 'text'
    }, headers=auth_headers('u1', 'creator'))
    assert resp.status_code == 200
    data = resp.json()
    check_id = data['check_id']
    receipt_id = data['receipt_id']

    # 2. Submit edited content (new version) as same creator
    resp2 = client.post(f'/api/v1/brand/{check_id}/versions', json={'content': 'edited content'}, headers=auth_headers('u1', 'creator'))
    assert resp2.status_code == 200
    vdata = resp2.json()
    assert vdata['check_id'] == check_id
    new_receipt_id = vdata['receipt_id']

    # 3. Reviewer (u2) approves the edited check
    approve = client.patch(f'/api/v1/reviews/{check_id}/decision', json={'decision': 'approved', 'note': 'ok'}, headers=auth_headers('u2', 'reviewer'))
    assert approve.status_code == 200
    assert approve.json()['review']['status'] == 'approved'

    # 4. Creator cannot approve own submission (should get 409)
    deny = client.patch(f'/api/v1/reviews/{check_id}/decision', json={'decision': 'approved', 'note': ''}, headers=auth_headers('u1', 'reviewer'))
    assert deny.status_code == 409

    # 5. Verify approval – should be valid now
    verify = client.post('/api/v1/approvals/verify', json={
        'check_id': check_id,
        'brand_name': 'Acme',
        'content': 'edited content'
    })
    assert verify.status_code == 200
    assert verify.json()['valid'] is True

    # 6. Retrieve receipt details (new receipt)
    receipt_resp = client.get(f'/api/v1/receipts/{new_receipt_id}')
    assert receipt_resp.status_code == 200
    receipt = receipt_resp.json()
    assert receipt['receipt_id'] == new_receipt_id

    # 7. Ensure audit log contains entries for each step
    # Load audit log directly from file
    audit_path = os.path.join('backend', 'app', 'audit', 'audit_log.json')
    with open(audit_path, 'r', encoding='utf-8') as f:
        audit_entries = json.load(f)
    actions = [e['action'] for e in audit_entries]
    assert 'create_check' in actions
    assert 'submit_version' in actions
    assert 'review_decision' in actions

    # 8. Edit content again after approval – should invalidate previous approval
    resp3 = client.post(f'/api/v1/brand/{check_id}/versions', json={'content': 'second edit'}, headers=auth_headers('u1', 'creator'))
    assert resp3.status_code == 200
    # Verify again – should now be invalid because status reset to pending
    verify2 = client.post('/api/v1/approvals/verify', json={
        'check_id': check_id,
        'brand_name': 'Acme',
        'content': 'second edit'
    })
    assert verify2.status_code == 200
    assert verify2.json()['valid'] is False

if __name__ == '__main__':
    pytest.main([__file__])
