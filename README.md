<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./afendor_static/marketing/branding/logo-white.svg">
    <img src="./afendor_static/marketing/branding/logo-color.svg" alt="Afendor Chat logo" width="400">
  </picture>
</p>

<p align="center">
  <a href="https://deskapp.afendor.cc/">
    <img src="https://img.shields.io/badge/Download-deskapp.afendor.cc-9FE803" alt="Download Windows App" /></a>
  <a href="https://web.afendor.cc">
    <img src="https://img.shields.io/badge/Web%20App-web.afendor.cc-blue" alt="Web App" /></a>
  <a href="https://afendor.cc">
    <img src="https://img.shields.io/badge/Website-afendor.cc-informational" alt="Website" /></a>
  <a href="./LICENSE">
    <img src="https://img.shields.io/badge/License-AGPLv3-purple" alt="AGPLv3 License" /></a>
</p>

# Afendor Chat

Afendor Chat is a modern instant messaging and VoIP chat application built for friends, groups, and communities. Connected to **afendor.cc**.

---

## 💻 Download & Access

| Platform | Type | Link |
| :--- | :--- | :--- |
| **Windows (x64)** | Setup Installer | [Download Afendor-Chat-Setup.exe](https://deskapp.afendor.cc/) |
| **Web Browser** | Instant Access | [Open web.afendor.cc](https://web.afendor.cc/) |

---

## 🚀 Self-Hosted VPS Deployment

To install and run the complete Afendor Chat production stack on your VPS, execute the guided installer:

```bash
curl -fsSL https://deskapp.afendor.cc/install.sh | bash
```

### Stack Management (`afendorctl`)

Once installed, manage the entire system using the bundled CLI:

```bash
# Check service status
sudo afendorctl status

# Run automated health checks
sudo afendorctl health

# View live service logs
sudo afendorctl logs

# Start / Restart all services
sudo afendorctl start
sudo afendorctl restart
```

---

## ⚙️ Architecture & Features

- **Realtime Gateway:** High-throughput WebSocket architecture for instant messaging, typing indicators, and presence.
- **VoIP & Video:** WebRTC voice channels powered by LiveKit SFU.
- **Storage Options:** Seamless integration with Cloudflare R2 / S3 (Mode B) or local storage (Mode A).
- **Desktop Client:** Self-updating Windows desktop application powered by Velopack, hardcoded to official `afendor.cc` services.

---

## 📜 License

The source code is licensed under the [AGPL-3.0-or-later](./LICENSE) license.
Afendor artwork, branding, icons, and logos are covered by their respective copyrights.
