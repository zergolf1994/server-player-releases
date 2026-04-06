#!/bin/bash

# Server Player Installation Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
HTTP_PORT="8081"
INSTALL_APP=false
INSTALL_NGINX=false
UNINSTALL=false
MONGODB_URI=""

APP_NAME="server-player"
APP_DIR="/opt/$APP_NAME"
URL_BASE="https://raw.githubusercontent.com/zergolf1994/server-player-releases/main"

# Functions
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        --app)
            INSTALL_APP=true
            shift
            ;;
        --nginx)
            INSTALL_NGINX=true
            shift
            ;;
        -p|--port)
            HTTP_PORT="$2"
            shift 2
            ;;
        --mongodb-uri)
            MONGODB_URI="$2"
            shift 2
            ;;
        -h|--help)
            echo "Server Player Installer"
            echo ""
            echo "Usage: sudo ./install.sh [OPTIONS]"
            echo ""
            echo "Components (if none specified, both are installed):"
            echo "  --app              Install/Update Application only"
            echo "  --nginx            Install/Update Nginx config only"
            echo "  --uninstall        Uninstall completely"
            echo ""
            echo "Configuration:"
            echo "  -p, --port PORT    HTTP port (default: 8081)"
            echo "  --mongodb-uri URI  MongoDB connection string"
            echo "  -h, --help         Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ==========================================
# Uninstallation
# ==========================================
if [ "$UNINSTALL" = true ]; then
    print_warning "⚠️  Starting Uninstallation..."

    # Stop and disable service
    print_status "Stopping and disabling service..."
    systemctl stop $APP_NAME 2>/dev/null || true
    systemctl disable $APP_NAME 2>/dev/null || true

    # Remove systemd service file
    if [ -f "/etc/systemd/system/$APP_NAME.service" ]; then
        print_status "Removing systemd service file..."
        rm "/etc/systemd/system/$APP_NAME.service"
        systemctl daemon-reload
    fi

    # Remove application directory
    if [ -d "$APP_DIR" ]; then
        print_status "Removing application directory..."
        rm -rf "$APP_DIR"
    fi

    # Remove upstream from Nginx default config
    if [ -f "/etc/nginx/sites-available/default" ]; then
        print_status "Removing Nginx upstream configuration..."
        sed -i "/# --- $APP_NAME upstream begin ---/,/# --- $APP_NAME upstream end ---/d" /etc/nginx/sites-available/default

        if command -v nginx &> /dev/null; then
            print_status "Reloading Nginx..."
            nginx -t && systemctl reload nginx
        fi
    fi

    print_status "✅ Uninstallation completed successfully!"
    exit 0
fi

# If no specific component flag is set, install everything
if [ "$INSTALL_APP" = false ] && [ "$INSTALL_NGINX" = false ]; then
    INSTALL_APP=true
    INSTALL_NGINX=true
fi

print_status "🚀 Starting Installation..."
print_status "Components: App=$INSTALL_APP, Nginx=$INSTALL_NGINX"
print_status "Configuration: Port=$HTTP_PORT"

# Update and install dependencies
print_status "Updating system packages..."
if command -v apt-get &> /dev/null; then
    apt-get update -qq
    print_status "Installing dependencies (curl)..."
    apt-get install -y -qq curl 2>/dev/null || true
elif command -v yum &> /dev/null; then
    yum install -y curl
elif command -v dnf &> /dev/null; then
    dnf install -y curl
fi

# ==========================================
# Application Installation
# ==========================================
if [ "$INSTALL_APP" = true ]; then
    print_status "📦 Installing Application..."

    SERVICE_USER="root"

    # Stop service if running
    print_status "Stopping existing service..."
    systemctl stop $APP_NAME 2>/dev/null || true

    # Create directory structure
    print_status "Creating directory structure..."
    mkdir -p "$APP_DIR"

    # Determine architecture
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        BINARY="server-player-linux"
    elif [ "$ARCH" = "aarch64" ]; then
        BINARY="server-player-linux-arm64"
    else
        print_error "Unsupported architecture: $ARCH"
        exit 1
    fi

    # Download binary
    print_status "Downloading binary ($BINARY)..."
    curl -fsSL "$URL_BASE/$BINARY" -o "$APP_DIR/$APP_NAME"
    chmod +x "$APP_DIR/$APP_NAME"

    # Create .env file (preserve existing if no new values provided)
    if [ -f "$APP_DIR/.env" ] && [ -z "$MONGODB_URI" ]; then
        print_status "Preserving existing configuration..."
        # Update only HTTP_PORT in existing config
        if grep -q "^HTTP_PORT=" "$APP_DIR/.env"; then
            sed -i "s/^HTTP_PORT=.*/HTTP_PORT=$HTTP_PORT/" "$APP_DIR/.env"
        else
            echo "HTTP_PORT=$HTTP_PORT" >> "$APP_DIR/.env"
        fi
    else
        print_status "Creating configuration..."
        cat > "$APP_DIR/.env" << EOF
# Server Player Configuration
HTTP_PORT=$HTTP_PORT
MONGODB_URI=$MONGODB_URI
EOF
    fi

    # Create systemd service
    print_status "Creating systemd service..."
    cat > /etc/systemd/system/$APP_NAME.service << EOF
[Unit]
Description=Server Player API
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/$APP_NAME
Restart=always
RestartSec=5
Environment=HOME=/root

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable service
    print_status "Configuring systemd..."
    systemctl daemon-reload
    systemctl enable $APP_NAME

    # Start service
    print_status "Starting service..."
    systemctl start $APP_NAME

    # Verify service
    sleep 2
    if systemctl is-active --quiet $APP_NAME; then
        print_status "✅ Application installed and running!"
    else
        print_error "❌ Application failed to start. Check logs: journalctl -u $APP_NAME -e"
        exit 1
    fi
fi

# ==========================================
# Nginx Installation (upstream in default)
# ==========================================
if [ "$INSTALL_NGINX" = true ]; then
    print_status "🔧 Installing/Configuring Nginx..."

    # Check Nginx installation
    if ! command -v nginx &> /dev/null; then
        print_status "Installing Nginx..."
        apt-get update -qq
        apt-get install -y nginx
        systemctl start nginx
        systemctl enable nginx
    else
        print_status "Nginx is already installed"
    fi

    NGINX_DEFAULT="/etc/nginx/sites-available/default"

    # Remove old upstream block if exists
    if [ -f "$NGINX_DEFAULT" ]; then
        sed -i "/# --- $APP_NAME upstream begin ---/,/# --- $APP_NAME upstream end ---/d" "$NGINX_DEFAULT"
    fi

    # Check if upstream block already exists in the file (by upstream name)
    if grep -q "upstream $APP_NAME" "$NGINX_DEFAULT" 2>/dev/null; then
        print_warning "Upstream '$APP_NAME' already exists in $NGINX_DEFAULT, skipping..."
    else
        print_status "Adding upstream to $NGINX_DEFAULT..."

        # Prepend upstream block before the first server block
        UPSTREAM_BLOCK="# --- $APP_NAME upstream begin ---\nupstream $APP_NAME {\n    server localhost:$HTTP_PORT;\n}\n# --- $APP_NAME upstream end ---\n"

        sed -i "1i\\${UPSTREAM_BLOCK}" "$NGINX_DEFAULT"
    fi

    # Test and Reload
    print_status "Reloading Nginx..."
    if nginx -t; then
        systemctl reload nginx
        print_status "✅ Nginx configured successfully!"
        print_status "   Upstream '$APP_NAME' -> localhost:$HTTP_PORT"
        print_status "   Use 'proxy_pass http://$APP_NAME;' in your server blocks"
    else
        print_error "❌ Nginx configuration failed verification"
        exit 1
    fi
fi

echo ""
echo "============================================"
print_status "🎉 Installation completed successfully!"
echo "============================================"
echo "  Service: $APP_NAME"
echo "  Port:    $HTTP_PORT"
echo ""
echo "  Health:  http://localhost:$HTTP_PORT/health"
echo ""
echo "  Nginx upstream: $APP_NAME -> localhost:$HTTP_PORT"
echo "  Usage: proxy_pass http://$APP_NAME;"
echo ""
echo "  Commands:"
echo "    systemctl status $APP_NAME"
echo "    systemctl restart $APP_NAME"
echo "    journalctl -u $APP_NAME -f"
echo "============================================"
