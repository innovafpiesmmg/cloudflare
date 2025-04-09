#!/bin/bash

# Script de instalación para CloudFlare Tunnel Manager
# Este script instala y configura la aplicación para gestionar túneles de CloudFlare en Ubuntu

# Colores para los mensajes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Función para imprimir mensajes de estado
print_status() {
    echo -e "${GREEN}[+]${NC} $1"
}

# Función para imprimir advertencias
print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Función para imprimir errores
print_error() {
    echo -e "${RED}[x]${NC} $1"
}

# Verificar que se está ejecutando como root
if [ "$EUID" -ne 0 ]; then
    print_error "Este script debe ejecutarse como root o con sudo"
    exit 1
fi

# Verificar que es un sistema Ubuntu
if [ ! -f /etc/lsb-release ] || ! grep -q "Ubuntu" /etc/lsb-release; then
    print_warning "Este script está diseñado para Ubuntu. Puede haber problemas de compatibilidad en otros sistemas."
    read -p "¿Desea continuar de todos modos? (s/n): " answer
    if [ "$answer" != "s" ]; then
        print_status "Instalación cancelada."
        exit 0
    fi
fi

# Directorio donde se instalará la aplicación
INSTALL_DIR="/opt/gestor-tuneles-cloudflare"

# Crear directorio de instalación
print_status "Creando directorio de instalación en $INSTALL_DIR"
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# Verificar e instalar dependencias
print_status "Verificando e instalando dependencias..."
apt-get update
apt-get install -y python3 python3-pip git curl sudo systemd python3-venv

# Verificar si ocurrió algún error
if [ $? -ne 0 ]; then
    print_error "Error al instalar dependencias. Por favor, verifica la conectividad a Internet y los permisos."
    exit 1
fi

# Crear entorno virtual de Python
print_status "Creando entorno virtual de Python..."
python3 -m venv venv
source venv/bin/activate

# Clonar repositorio (asumimos que este script se ejecuta desde el repo o se descarga individualmente)
if [ ! -d ".git" ]; then
    print_status "Clonando repositorio desde GitHub..."
    git clone https://github.com/innovafpiesmmg/cloudflare.git temp
    cp -r temp/* .
    cp -r temp/.* . 2>/dev/null
    rm -rf temp
fi

# Instalar requisitos de Python
print_status "Instalando requisitos de Python..."
pip install flask pyyaml psutil requests pillow gunicorn

# Crear archivo de servicio systemd
SERVICE_FILE="/etc/systemd/system/gestor-tuneles-cloudflare.service"
print_status "Creando servicio systemd..."

cat > $SERVICE_FILE << EOF
[Unit]
Description=Gestor de Túneles CloudFlare
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/gunicorn --bind 0.0.0.0:5000 --reuse-port --reload main:app
Restart=on-failure
RestartSec=5s
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=gestor-tuneles-cloudflare

[Install]
WantedBy=multi-user.target
EOF

# Recargar systemd
systemctl daemon-reload

# Habilitar e iniciar el servicio
print_status "Habilitando e iniciando el servicio..."
systemctl enable gestor-tuneles-cloudflare
systemctl start gestor-tuneles-cloudflare

# Verificar si el servicio se inició correctamente
if systemctl is-active --quiet gestor-tuneles-cloudflare; then
    print_status "Servicio iniciado correctamente."
else
    print_error "Error al iniciar el servicio. Verificando logs..."
    journalctl -u gestor-tuneles-cloudflare -n 20
fi

# Mostrar información final
IP_ADDRESS=$(hostname -I | awk '{print $1}')
print_status "====================================================="
print_status "  Gestor de Túneles CloudFlare instalado correctamente  "
print_status "====================================================="
print_status "Puedes acceder a la interfaz web en:"
print_status "http://$IP_ADDRESS:5000"
print_status ""
print_status "Si encuentras algún problema, verifica los logs con:"
print_status "journalctl -u gestor-tuneles-cloudflare -f"
print_status "====================================================="

exit 0
