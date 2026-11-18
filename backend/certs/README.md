# Public Supabase database trust root

`supabase-prod-ca-2021.crt` is a PUBLIC CA certificate, not a private key or service
credential. It was retrieved over HTTPS and verified against the live project's
session-pooler connection on 2026-11-15.

Source:
https://supabase-downloads.s3-ap-southeast-1.amazonaws.com/prod/ssl/prod-ca-2021.crt

Official usage guidance:
https://supabase.com/docs/guides/platform/ssl-enforcement

- Subject / issuer CN: `Supabase Root 2021 CA` (self-signed trust root).
- Validity: 2021-04-28 10:56:53 UTC through 2031-04-26 10:56:53 UTC.
- SHA-256 of the downloaded PEM FILE:
  `700723581420dd1ac98fd7e9ac529f0ef210eadcaf87fc868a3ad7d114c2f3b7`.
- SHA-256 X.509 certificate fingerprint (DER, not PEM file hash):
  `80:70:25:AD:50:D4:ED:21:9D:2C:9C:7D:29:9C:00:4F:82:4E:B0:0C:F7:F6:5A:FE:F6:07:D0:7B:72:E6:CA:FA`.

Use `sslmode=verify-full` plus `sslrootcert` pointing to this file. Launching from
`backend/` permits `sslrootcert=certs/supabase-prod-ca-2021.crt`; deployments using a
different working directory must set the absolute path in the database URL.
`start_backend.py` already launches Uvicorn with `backend/` as its working directory.

A public CA bundle such as certifi alone did not trust this pooler's private CA.
`sslmode=require` encrypted the connection but was not retained as the final solution:
the runtime now verifies BOTH the trust chain and actual pooler hostname. A deliberately
incorrect hostname at the same pooler IP was rejected in the final TLS checks.

At certificate rotation, obtain the new trust root from Supabase's official dashboard
(Database Settings → SSL Configuration) and validate the new connection. Do not fix
trust errors by disabling verification or trusting an unverified presented chain.
