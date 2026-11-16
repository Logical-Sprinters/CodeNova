"""Same-origin password recovery page. No token is persisted in browser storage."""

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

router = APIRouter(tags=["Account recovery"])

PAGE = """<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer"><title>BrandGuard — reset password</title>
<style>body{font:16px system-ui;background:#f7f8f6;color:#142c3b;margin:0;padding:24px}
main{max-width:420px;margin:8vh auto;background:white;padding:30px;border-radius:20px}
input,button{box-sizing:border-box;width:100%;padding:14px;border:1px solid #cad9d3;border-radius:9px;margin:8px 0}
button{background:#006b5e;color:white;font-weight:bold;cursor:pointer}p{line-height:1.5}</style>
<main><h1>Reset your password</h1><p>Use the link from your BrandGuard recovery email. Tokens remain in memory only.</p>
<form id="form"><label for="password">New password (8–128 characters)</label>
<input id="password" type="password" minlength="8" maxlength="128" autocomplete="new-password" required>
<label for="confirm">Confirm password</label><input id="confirm" type="password" minlength="8" maxlength="128" autocomplete="new-password" required>
<button id="save">Update password</button></form><p id="message" role="status"></p>
<p><a href="/">Return to BrandGuard</a></p></main>
<script>
const params = new URLSearchParams(location.hash.slice(1));
let token = params.get('access_token');
const message = document.getElementById('message');
if (location.hash) history.replaceState(null, '', location.pathname);
if (!token) { message.textContent = 'No recovery token. Request a fresh reset email from the mobile app.'; document.getElementById('save').disabled = true; }
document.getElementById('form').addEventListener('submit', async event => {
 event.preventDefault();
 const password = document.getElementById('password').value;
 if (password !== document.getElementById('confirm').value) { message.textContent='Passwords do not match.'; return; }
 document.getElementById('save').disabled=true;
 try {
  const response=await fetch('/api/v1/auth/password',{method:'PUT',headers:{'Content-Type':'application/json','Authorization':'Bearer '+token},body:JSON.stringify({password})});
  const data=await response.json();
  if (!response.ok) throw new Error(typeof data.detail === 'string' ? data.detail : 'Reset failed. Request a fresh email.');
  token=null;document.getElementById('form').reset();message.textContent='Password updated. Return to the app and sign in with your new password.';
 } catch (error) { message.textContent=error.message;document.getElementById('save').disabled=false; }
});
</script></html>"""


CONFIRM_PAGE = """<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer"><title>BrandGuard — email confirmation</title>
<style>body{font:16px system-ui;background:#f7f8f6;color:#142c3b;margin:0;padding:24px}
main{max-width:420px;margin:8vh auto;background:white;padding:30px;border-radius:20px}
a{color:#006b5e}p{line-height:1.5}</style>
<main><h1>Email confirmation</h1><p id="message" role="status">Checking your verification link…</p>
<p><a href="/">Return to BrandGuard sign in</a></p></main>
<script>
(async () => {
 const params = new URLSearchParams(location.hash.slice(1));
 let token = params.get('access_token');
 if (location.hash || location.search) history.replaceState(null, '', location.pathname);
 const message = document.getElementById('message');
 if (!token || params.has('error')) {
  message.textContent = 'This confirmation link is missing, expired or already used. Request a fresh confirmation email, or sign in if you have already confirmed.';
  return;
 }
 try {
  const response = await fetch('/api/v1/auth/me', {headers: {'Authorization': 'Bearer ' + token}, cache: 'no-store'});
  token = null;
  if (!response.ok) throw new Error('Verification failed');
  message.textContent = 'Email confirmed. You can now return to BrandGuard and sign in with your password.';
 } catch (_) {
  token = null;
  message.textContent = 'The verification session could not be checked. Try signing in, or request a fresh confirmation email.';
 }
})();
</script></html>"""


@router.get("/auth/confirm", response_class=HTMLResponse)
def confirmation_page():
    return HTMLResponse(CONFIRM_PAGE, headers={"Cache-Control": "no-store"})


@router.get("/auth/reset", response_class=HTMLResponse)
def recovery_page():
    return HTMLResponse(
        PAGE,
        headers={
            "Cache-Control": "no-store",
            "Referrer-Policy": "no-referrer",
            "X-Content-Type-Options": "nosniff",
        },
    )
