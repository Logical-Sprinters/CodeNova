# scripts/

| File | What it does |
|---|---|
| `smoke.py` | the 14-step end-to-end story over HTTP: check → repair → approve → edit → void. Run it after `make api`. |
| `dev.sh` | first-run helper for bash: database → assertions → API, in order |
| `dev.ps1` | the same for PowerShell |

`smoke.py` is the most useful file in the repository after the schema: it is the demo,
executed, and it fails loudly if any claim stops being true.

```bash
python scripts/smoke.py
python scripts/smoke.py --base http://192.168.1.20:8000
```
