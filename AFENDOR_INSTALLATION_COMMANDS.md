# AFENDOR CHAT — COMPLETE COMMAND CHEATSHEET

> **Fast Reference:** All operations on your Ubuntu GCP VPS  

---

## 1. Initial Installation on VPS

```bash
# 1. SSH into your Google Cloud VPS
ssh user@<GCP-VPS-IP>

# 2. Navigate to / create Afendor directory
sudo mkdir -p /opt/afendor && cd /opt/afendor

# 3. Copy files from your local development machine (or clone private repo)
# rsync -avz --exclude 'node_modules' --exclude 'target' ./ user@<GCP-VPS-IP>:/opt/afendor/

# 4. Run the guided interactive installer
sudo bash deploy/install.sh

# 5. Enable the Nginx reverse proxy configuration
sudo cp /opt/afendor/deploy/nginx/afendor.conf /etc/nginx/sites-available/
sudo ln -sf /etc/nginx/sites-available/afendor.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# 6. Start the Afendor Chat stack
sudo afendorctl start
```

---

## 2. Daily Operations with `afendorctl`

```bash
# Check status of all containers and CPU/RAM usage
sudo afendorctl status

# Run deep health diagnostic on all microservices
sudo afendorctl health

# View live streaming logs across all containers
sudo afendorctl logs -f

# View logs for a specific service (e.g. api, gateway, media-proxy)
sudo afendorctl logs -f api
sudo afendorctl logs -f gateway
sudo afendorctl logs -f media-proxy

# Restart a specific service
sudo afendorctl restart api

# Stop the entire stack
sudo afendorctl stop

# Start the entire stack
sudo afendorctl start
```

---

## 3. Backups & Upgrades

```bash
# Create an instant database and configuration backup
sudo afendorctl backup

# List all existing backups
ls -lh /opt/afendor/backups/

# Restore a specific database backup
sudo afendorctl restore /opt/afendor/backups/afendor_backup_20261106_120000.sql.gz

# Perform a safe rolling update (backs up DB, pulls images, restarts, verifies)
sudo afendorctl update

# Emergency rollback if an update fails
sudo afendorctl rollback
```

---

## 4. Admin Setup & Invitations

```bash
# Print or generate the initial Admin Setup Token
sudo afendorctl setup-token

# Claim your account in the browser:
# Navigate to: https://web.afendor.cc
# Enter the token to create your Owner Administrator account.
```

