# scripts/

| File | Platform | What it does |
|---|---|---|
| `dev.ps1` | Windows | Docker check → postgres → schema/functions/seed → 28 assertions. **No make, no psql, no PowerShell 7 needed.** |
| `api.ps1` | Windows | Creates `.venv` on first run, installs requirements, starts uvicorn on :8000 |
| `dev.sh` | macOS / Linux | Docker check → postgres → schema/functions/seed → 28 assertions |
| `smoke.py` | any | the 14-step end-to-end story over HTTP: check → repair → approve → edit → void |

On Windows, the two `.ps1` files are the supported path: PowerShell 5.1 has no `&&`, and
`make` and `psql` are not installed by default. Full run book: [../docs/run-local.md](../docs/run-local.md).

`smoke.py` is the most useful file in the repository after the schema: it is the demo,
executed, and it fails loudly if any claim stops being true.

```bash
python scripts/smoke.py
python scripts/smoke.py --base http://192.168.1.20:8000
```
