# Hyrovi APT Repo

Öffentliches APT-Repository für `hyrovi-tool`.

## Installieren



Repo-URL:
- `https://H-Y-R-O-V-I.github.io/apt/`

Installationsbefehl für Debian / Raspberry Pi OS:

```bash
sudo install -d -m 0755 /etc/apt/keyrings && \
curl -fsSL -o /tmp/hyrovi-archive-keyring.gpg https://H-Y-R-O-V-I.github.io/apt/hyrovi-archive-keyring.gpg && \
sudo install -m 0644 /tmp/hyrovi-archive-keyring.gpg /etc/apt/keyrings/hyrovi-archive-keyring.gpg && \
echo "deb [signed-by=/etc/apt/keyrings/hyrovi-archive-keyring.gpg] https://H-Y-R-O-V-I.github.io/apt/ hyrovi main" | sudo tee /etc/apt/sources.list.d/hyrovi.list && \
sudo apt update && \
sudo apt install hyrovi-tool
```
