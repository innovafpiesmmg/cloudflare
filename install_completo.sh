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

# Actualizar sistema y repositorios
print_status "Actualizando repositorios y sistema..."
apt-get update
if [ $? -ne 0 ]; then
    print_error "Error al actualizar repositorios. Comprobando conectividad..."
    if ! ping -c 1 google.com &> /dev/null; then
        print_error "No hay conexión a Internet. Verifica la conectividad de red."
        exit 1
    else
        print_warning "Hay conectividad pero falló la actualización. Intentando continuar..."
    fi
fi

# Instalar dependencias esenciales primero
print_status "Instalando dependencias esenciales..."
apt-get install -y apt-utils dialog apt-transport-https ca-certificates software-properties-common gnupg2 curl wget

# Verificar e instalar dependencias principales
print_status "Instalando dependencias principales..."
apt-get install -y python3 python3-pip python3-venv python3-dev \
                   git curl wget sudo systemd lsb-release \
                   build-essential libssl-dev libffi-dev

# Verificar si ocurrió algún error
if [ $? -ne 0 ]; then
    print_error "Error al instalar dependencias principales."
    print_warning "Intentando instalar dependencias críticas mínimas..."
    apt-get install -y python3 python3-pip curl wget
    
    if [ $? -ne 0 ]; then
        print_error "No se pudieron instalar las dependencias críticas. Abortando instalación."
        exit 1
    else
        print_warning "Se instalaron las dependencias mínimas. Algunas funcionalidades podrían estar limitadas."
    fi
fi

# Crear entorno virtual de Python
print_status "Creando entorno virtual de Python..."
python3 -m venv venv
source venv/bin/activate

# Clonar repositorio desde GitHub
print_status "Clonando repositorio desde GitHub..."
git clone https://github.com/innovafpiesmmg/cloudflare.git temp || {
    print_error "Error al clonar el repositorio. Creando estructura básica manualmente..."
    mkdir -p temp
    mkdir -p temp/static/css
    mkdir -p temp/static/js
    mkdir -p temp/static/img
    mkdir -p temp/templates
    mkdir -p temp/utils
    
    # Crear archivos básicos si el repositorio no está disponible
    echo '#!/bin/bash
echo "Monitor de túneles CloudFlare"
python3 $INSTALL_DIR/monitor.py --daemon
' > temp/cloudflare-monitor.service
    
    print_warning "Estructura básica creada. La aplicación estará limitada hasta que se complete el repositorio."
}

# Copiar archivos
cp -r temp/* . 2>/dev/null
cp -r temp/.* . 2>/dev/null || true
rm -rf temp

# Instalar requisitos de Python
print_status "Instalando requisitos de Python..."
pip install --upgrade pip
pip install setuptools wheel

# Instalar dependencias en etapas para mejor manejo de errores
print_status "Instalando dependencias básicas de Python..."
pip install flask pyyaml requests
if [ $? -ne 0 ]; then
    print_error "Error al instalar dependencias básicas de Python."
    print_warning "Intentando instalar Flask con opciones alternativas..."
    pip install --no-cache-dir flask
    if [ $? -ne 0 ]; then
        print_error "No se pudo instalar Flask. El aplicativo no funcionará correctamente."
        exit 1
    fi
fi

print_status "Instalando dependencias adicionales de Python..."
pip install psutil pillow gunicorn
if [ $? -ne 0 ]; then
    print_warning "Algunas dependencias adicionales no pudieron instalarse."
    print_warning "El aplicativo podría funcionar con funcionalidad limitada."
    
    # Instalar gunicorn que es crítico para el servidor web
    pip install gunicorn
    if [ $? -ne 0 ]; then
        print_error "No se pudo instalar gunicorn. Intentando método alternativo..."
        python3 -m pip install gunicorn
        
        if [ $? -ne 0 ]; then
            print_error "No se pudo instalar gunicorn. El aplicativo no funcionará correctamente."
            exit 1
        fi
    fi
fi

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

# Crear archivo principal si no existe
if [ ! -f "$INSTALL_DIR/main.py" ]; then
    print_warning "No se encontró main.py. Creando un archivo básico..."
    cat > $INSTALL_DIR/main.py << EOF
import os
from flask import Flask, render_template, jsonify, request

app = Flask(__name__)

@app.route('/')
def index():
    return render_template('index.html', title="Gestor de Túneles CloudFlare")

@app.route('/health')
def health_check():
    return jsonify({"status": "ok", "version": "1.2"})

if __name__ == "__main__":
    debug_mode = os.environ.get('FLASK_ENV') != 'production'
    app.run(host="0.0.0.0", port=5000, debug=debug_mode)
EOF
fi

# Crear carpeta templates y archivo index.html si no existe
if [ ! -d "$INSTALL_DIR/templates" ]; then
    mkdir -p "$INSTALL_DIR/templates"
fi

if [ ! -f "$INSTALL_DIR/templates/index.html" ]; then
    print_warning "No se encontró la plantilla principal. Creando un archivo básico..."
    cat > $INSTALL_DIR/templates/index.html << EOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{ title }}</title>
    <link rel="stylesheet" href="https://cdn.replit.com/agent/bootstrap-agent-dark-theme.min.css">
</head>
<body>
    <div class="container mt-5">
        <div class="row">
            <div class="col-12 text-center">
                <h1>Gestor de Túneles CloudFlare</h1>
                <p>Desarrollado por ATECA TECHLAB SOFTWARE</p>
                <p>Instalación básica completada. Por favor, configure el repositorio completo para todas las funcionalidades.</p>
            </div>
        </div>
    </div>
</body>
</html>
EOF
fi

# Crear carpeta para monitoreo y configuración
mkdir -p "$INSTALL_DIR/config"
chmod 700 "$INSTALL_DIR/config"

# Crear configuración de monitoreo
cat > "$INSTALL_DIR/config/monitor_config.json" << EOF
{
    "email_notifications": false,
    "smtp_server": "smtp.example.com",
    "smtp_port": 587,
    "smtp_user": "usuario@example.com",
    "smtp_password": "contraseña_segura",
    "notification_email": "admin@example.com",
    "from_email": "cloudflare-monitor@example.com",
    "check_interval_seconds": 300,
    "alert_recovery_minutes": 30,
    "enable_system_stats": true,
    "allowed_ip_networks": [
        "127.0.0.1/8",
        "10.0.0.0/8",
        "172.16.0.0/12",
        "192.168.0.0/16"
    ]
}
EOF
chmod 600 "$INSTALL_DIR/config/monitor_config.json"

# Crear servicio de monitoreo
cat > "/etc/systemd/system/cloudflare-monitor.service" << EOF
[Unit]
Description=Monitor de Túneles CloudFlare
After=network.target gestor-tuneles-cloudflare.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/monitor.py --daemon
Restart=on-failure
RestartSec=10s
StandardOutput=append:/var/log/cloudflare-monitor.log
StandardError=append:/var/log/cloudflare-monitor.log

[Install]
WantedBy=multi-user.target
EOF

# Crear script de monitoreo básico si no existe
if [ ! -f "$INSTALL_DIR/monitor.py" ]; then
    print_warning "No se encontró monitor.py. Creando un archivo básico..."
    cat > $INSTALL_DIR/monitor.py << EOF
#!/usr/bin/env python3
import argparse
import json
import logging
import os
import sys
import time
from datetime import datetime
import requests

# Configuración de logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('/var/log/cloudflare-monitor.log')
    ]
)

TUNNEL_CHECK_INTERVAL = 300  # 5 minutos por defecto
CONFIG_DIR = '/opt/gestor-tuneles-cloudflare/config'
CONFIG_FILE = os.path.join(CONFIG_DIR, 'monitor_config.json')
KNOWN_ISSUES_FILE = os.path.join(CONFIG_DIR, 'known_issues.json')

def load_config():
    """Cargar configuración del monitor"""
    if not os.path.exists(CONFIG_FILE):
        logging.warning(f"Archivo de configuración no encontrado: {CONFIG_FILE}")
        return {}
    
    try:
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    except Exception as e:
        logging.error(f"Error al cargar configuración: {str(e)}")
        return {}

def get_tunnels():
    """Obtener lista de túneles configurados"""
    try:
        # En una implementación real, esto obtendría la lista de túneles
        # Simplificado para este script básico
        return []
    except Exception as e:
        logging.error(f"Error al obtener lista de túneles: {str(e)}")
        return []

def monitor_tunnels():
    """Función principal para monitorizar túneles"""
    config = load_config()
    logging.info("Monitor de túneles iniciado")
    
    # Lógica de monitoreo (simplificada)
    tunnels = get_tunnels()
    if not tunnels:
        logging.warning("No se encontraron túneles para monitorizar")
    else:
        logging.info(f"Monitorizando {len(tunnels)} túneles")
    
    # Verificar estado del servidor web
    try:
        response = requests.get('http://localhost:5000/health', timeout=5)
        if response.status_code == 200:
            logging.info("Servidor web funcionando correctamente")
        else:
            logging.warning(f"El servidor web respondió con estado: {response.status_code}")
    except Exception as e:
        logging.error(f"Error al verificar el estado del servidor web: {str(e)}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Monitoriza el estado de los túneles CloudFlare")
    parser.add_argument("--daemon", action="store_true", help="Ejecutar como demonio")
    parser.add_argument("--interval", type=int, default=TUNNEL_CHECK_INTERVAL, help="Intervalo de verificación en segundos")
    args = parser.parse_args()
    
    if args.daemon:
        logging.info(f"Iniciando monitorización en modo demonio (intervalo: {args.interval}s)")
        
        try:
            while True:
                monitor_tunnels()
                time.sleep(args.interval)
        except KeyboardInterrupt:
            logging.info("Monitorización detenida por el usuario")
            sys.exit(0)
    else:
        monitor_tunnels()
EOF
    chmod +x $INSTALL_DIR/monitor.py
fi

# Crear directorio para logs
mkdir -p /var/log/cloudflare
touch /var/log/cloudflare-monitor.log
chmod 640 /var/log/cloudflare-monitor.log

# Recargar systemd
systemctl daemon-reload

# Habilitar e iniciar el servicio
print_status "Habilitando e iniciando el servicio..."
systemctl enable gestor-tuneles-cloudflare
systemctl start gestor-tuneles-cloudflare

# Configuración del servicio de monitoreo
print_status "Configurando servicio de monitoreo..."
systemctl enable cloudflare-monitor.service
systemctl start cloudflare-monitor.service

# Verificar si los servicios se iniciaron correctamente
if systemctl is-active --quiet gestor-tuneles-cloudflare; then
    print_status "Servicio principal iniciado correctamente."
else
    print_error "Error al iniciar el servicio principal. Verificando logs..."
    journalctl -u gestor-tuneles-cloudflare -n 20
fi

if systemctl is-active --quiet cloudflare-monitor; then
    print_status "Servicio de monitoreo iniciado correctamente."
else
    print_warning "El servicio de monitoreo no pudo iniciarse. Verificando logs..."
    journalctl -u cloudflare-monitor -n 10
    print_warning "Esto no afecta al funcionamiento principal de la aplicación."
fi

# Variable para entorno de producción
grep -q "FLASK_ENV=production" /etc/environment || echo "FLASK_ENV=production" >> /etc/environment

# Mostrar información final
IP_ADDRESS=$(hostname -I | awk '{print $1}')
print_status "====================================================="
print_status "  Gestor de Túneles CloudFlare instalado correctamente  "
print_status "====================================================="
print_status "Puedes acceder a la interfaz web en:"
print_status "http://$IP_ADDRESS:5000"
print_status ""
print_status "Para mayor seguridad en producción, configura HTTPS con Nginx"
print_status "siguiendo las instrucciones en README.md"
print_status ""
print_status "Monitoreo:"
print_status "- Estado del servicio principal: systemctl status gestor-tuneles-cloudflare"
print_status "- Estado del servicio de monitoreo: systemctl status cloudflare-monitor"
print_status "- Logs: journalctl -u gestor-tuneles-cloudflare -f"
print_status "- API de salud: http://$IP_ADDRESS:5000/health"
print_status ""
print_status "Para configurar notificaciones por correo, edita el archivo:"
print_status "$INSTALL_DIR/config/monitor_config.json"
print_status "====================================================="

exit 0