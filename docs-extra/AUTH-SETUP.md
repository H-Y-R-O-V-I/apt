# Hyrovi Auth Setup

Geräte-API:
- https://tool.hyrovi.com
- lokal: http://127.0.0.1:8787
- health: http://127.0.0.1:8787/healthz

Admin-Dashboard:
- lokal: http://127.0.0.1:8788/admin
- health: http://127.0.0.1:8788/healthz

Defaults auf Clients:
- /etc/default/hyrovi-tool-auth

Wichtig:
- 8787 ist nur für Geräte/API
- 8788 ist nur fürs Admin-Dashboard
- Nach Approve im Admin-Dashboard funktioniert der nächste Start direkt
- Nur bei explizitem revoked/blocked/unknown_device/invalid_token wird nur hyrovi-tool entfernt
