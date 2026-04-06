# Server Player

![Platform](https://img.shields.io/badge/platform-linux-lightgrey.svg)
![Go](https://img.shields.io/badge/Go-1.24-blue.svg)

API สำหรับจัดการ player embed และ video streaming

## 🚀 Quick Install (One-line)

```bash
# ติดตั้งทั้ง App + Nginx upstream
curl -fsSL https://raw.githubusercontent.com/zergolf1994/server-player-releases/main/install.sh | sudo -E bash -s -- \
    --port 8081 \
    --mongodb-uri "mongodb+srv://user:pass@host/dbname"
```

## 🛠️ Manual Installation

```bash
# Download
chmod +x install.sh

# ติดตั้งทั้งหมด (App + Nginx upstream) ด้วยค่า default
sudo ./install.sh

# ติดตั้งแบบกำหนดค่าเอง
sudo ./install.sh --port 8081 --mongodb-uri "mongodb+srv://..."

# ติดตั้งเฉพาะ App
sudo ./install.sh --app --port 8081 --mongodb-uri "mongodb+srv://..."

# ติดตั้งเฉพาะ Nginx upstream
sudo ./install.sh --nginx --port 8081

# อัปเดต App อย่างเดียว (ไม่แตะ Nginx)
sudo ./install.sh --app
```

## 🔧 Nginx Configuration

สคริปต์จะ**เขียนทับ** `/etc/nginx/sites-available/default` ให้เป็น reverse proxy ไปที่ app โดยอัตโนมัติ:

```nginx
upstream server-player {
    server localhost:8081;
}

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    location / {
        proxy_pass http://server-player;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

> **Note:** ใช้ `server_name _;` ทำให้ทุกโดเมนเข้าถึงได้โดยไม่ต้องกำหนด domain

## 🗑️ Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/zergolf1994/server-player-releases/main/install.sh | sudo -E bash -s -- \
    --uninstall
```

## 📡 API Usage

### Health Check
```
GET /health
```

### Response
```json
{
  "success": true,
  "data": { ... }
}
```

## ⚙️ Service Management

```bash
# Status
systemctl status server-player

# Logs
journalctl -u server-player -f

# Restart
sudo systemctl restart server-player

# Stop
sudo systemctl stop server-player
```

## 📋 Install Options

| Option | Default | Description |
|--------|---------|-------------|
| `--app` | — | ติดตั้ง/อัปเดตเฉพาะ Application |
| `--nginx` | — | ติดตั้ง/อัปเดตเฉพาะ Nginx upstream config |
| `-p, --port` | `8081` | HTTP port |
| `--mongodb-uri` | — | MongoDB connection string |
| `--uninstall` | — | ลบทั้งหมด (binary, service, nginx upstream) |
| `-h, --help` | — | แสดง help |

> **Note:** ถ้าไม่ระบุ `--app` หรือ `--nginx` จะติดตั้งทั้ง 2 component

> **Note:** ไม่ต้องระบุ domain — Nginx upstream เปิดให้ทุกโดเมนเข้าถึงได้ผ่าน `proxy_pass http://server-player;`
