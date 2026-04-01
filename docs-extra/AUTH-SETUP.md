# Hyrovi Tool Auth / Device Approval

## Admin-System
Dieses Projekt setzt einen separaten Admin-Server in `~/programmieren/apt-admin` auf.

## Client-Seite
Im APT-Projekt liegen ergänzend:
- `tools/hyrovi-auth-guard.sh`
- `tools/install-client-auth-files.sh`
- `client-hooks/hyrovi-tool-wrapper-template.sh`

## Verhalten
- Gerät registriert sich beim Server
- Gerät muss im Adminpanel freigegeben werden
- Nur bei explizitem Entzug (`revoked`, `blocked`, `invalid_token`, `unknown_device`) entfernt sich nur `hyrovi-tool`
- Bei reinem Netzwerkfehler passiert **keine** automatische Deinstallation
