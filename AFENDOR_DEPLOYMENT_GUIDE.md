# AFENDOR CHAT — PRODUCTION DEPLOYMENT GUIDE

> **Target Machine:** Google Cloud Platform (GCP) Compute Engine VPS  
> **Installation Directory:** `/opt/afendorchat`  
> **Prerequisites:** Docker Engine, Docker Compose Plugin, Host Nginx, TLS Certificates  

---

## 1. Initial Preparation on VPS

Connect to your GCP VPS via SSH:

```bash
ssh user@your-gcp-vps-ip
```

Create the application directory:

```bash
sudo mkdir -p /opt/afendorchat
sudo chown -R $USER:$USER /opt/afendorchat
```

---

## 2. Deploying Files to VPS

From your local machine (or once your private GitHub repository is cloned):

```bash
# Copy the repository files to the VPS (excluding local build artifacts)
rsync -avz --exclude 'node_modules' --exclude 'target' --exclude 'dist' --exclude '.git' \
  ./ user@your-gcp-vps-ip:/opt/afendorchat/
```

---

## 3. Configure Production Environment

Navigate to the deployment directory:

```bash
cd /opt/afendorchat
```

Run the automated installer:

```bash
sudo bash deploy/install.sh
```

The installer will:
1. Validate system resources (CPU, RAM, Disk).
2. Ask you to confirm the domain (`afendor.cc` or custom).
3. Allow you to select Mode A (Bundled SeaweedFS) or Mode B (Backblaze B2 / Generic S3).
4. Generate secure cryptographic secrets.
5. Create `config/env/production.env` with restricted `0600` permissions.
6. Install the `afendorctl` command line tool to `/usr/local/bin/afendorctl`.
7. Configure the systemd service for automatic reboot survival.

---

## 4. Configure Host Nginx Reverse Proxy

Link the pre-built Nginx site configuration to your existing Nginx:

```bash
sudo cp /opt/afendorchat/deploy/nginx/afendor.conf /etc/nginx/sites-available/afendor.conf
sudo ln -sf /etc/nginx/sites-available/afendor.conf /etc/nginx/sites-enabled/afendor.conf

# Test syntax before reloading
sudo nginx -t

# Reload Nginx without downtime
sudo systemctl reload nginx
```

---

## 5. Start the Afendor Chat Stack

Start all containers in detached mode:

```bash
sudo afendorctl start
```

Verify service status:

```bash
sudo afendorctl status
```

Run internal health checks:

```bash
sudo afendorctl health
```

---

## 6. Claim the Administrator Account

1. Retrieve your unique setup token:
   ```bash
   sudo afendorctl setup-token
   ```
2. Open **`https://web.afendor.cc`** in your browser.
3. You will be greeted by the **Afendor Setup Wizard**.
4. Enter the setup token.
5. Choose your administrator username and password.
6. Your account is now created as the **Instance Owner**.

---

## 7. Generating Private Friend Invitations

Because registration is strictly **invite-only**:
1. Log in at `https://web.afendor.cc`.
2. Create a server/guild for you and your friends.
3. Click **Server Settings -> Invites -> Create Invite**.
4. Set expiration to "Never" or your preferred duration.
5. Send the private invite link (e.g. `https://web.afendor.cc/invite/abcdef12`) to your friends.

