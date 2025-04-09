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

# Verificar si systemd está disponible
SYSTEMD_AVAILABLE=false
if command -v systemctl &> /dev/null && systemctl --version &> /dev/null; then
    SYSTEMD_AVAILABLE=true
    print_status "Systemd detectado, configurando como servicio systemd..."
else
    print_warning "Systemd no detectado. Se configurará un script de inicio alternativo."
fi

if [ "$SYSTEMD_AVAILABLE" = true ]; then
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

    # Configuración del servicio de monitoreo
    print_status "Configurando servicio de monitoreo..."
    cp $INSTALL_DIR/cloudflare-monitor.service /etc/systemd/system/
    systemctl daemon-reload
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
else
    # Método alternativo para sistemas sin systemd
    print_status "Creando scripts de inicio alternativos..."
    
    # Script de inicio para el servidor web
    START_SCRIPT="/usr/local/bin/gestor-tuneles-cloudflare"
    cat > $START_SCRIPT << EOF
#!/bin/bash
# Script para gestionar el servicio Gestor de Túneles CloudFlare
# Uso:
#   Para iniciar: $START_SCRIPT start
#   Para detener: $START_SCRIPT stop
#   Para reiniciar: $START_SCRIPT restart
#   Para ver estado: $START_SCRIPT status

INSTALL_DIR="$INSTALL_DIR"
PID_FILE="/tmp/gestor-tuneles-cloudflare.pid"
LOG_FILE="/var/log/gestor-tuneles-cloudflare.log"

start_service() {
    echo "Iniciando Gestor de Túneles CloudFlare..."
    cd \$INSTALL_DIR
    source venv/bin/activate
    nohup \$INSTALL_DIR/venv/bin/gunicorn --bind 0.0.0.0:5000 --reuse-port --reload main:app > \$LOG_FILE 2>&1 &
    echo \$! > \$PID_FILE
    echo "Servicio iniciado con PID \$(cat \$PID_FILE)"
}

stop_service() {
    if [ -f "\$PID_FILE" ]; then
        PID=\$(cat \$PID_FILE)
        echo "Deteniendo servicio (PID: \$PID)..."
        kill \$PID
        rm \$PID_FILE
        echo "Servicio detenido."
    else
        echo "El servicio no está en ejecución."
    fi
}

status_service() {
    if [ -f "\$PID_FILE" ]; then
        PID=\$(cat \$PID_FILE)
        if ps -p \$PID > /dev/null; then
            echo "El servicio está en ejecución (PID: \$PID)"
            return 0
        else
            echo "El servicio no está en ejecución (PID antiguo: \$PID)"
            rm \$PID_FILE
            return 1
        fi
    else
        echo "El servicio no está en ejecución."
        return 1
    fi
}

case "\$1" in
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    restart)
        stop_service
        sleep 2
        start_service
        ;;
    status)
        status_service
        ;;
    *)
        echo "Uso: \$0 {start|stop|restart|status}"
        exit 1
        ;;
esac

exit 0
EOF

    # Script de inicio para el servicio de monitoreo
    MONITOR_SCRIPT="/usr/local/bin/cloudflare-monitor"
    cat > $MONITOR_SCRIPT << EOF
#!/bin/bash
# Script para gestionar el servicio de monitoreo de Cloudflare Tunnels
# Uso:
#   Para iniciar: $MONITOR_SCRIPT start
#   Para detener: $MONITOR_SCRIPT stop
#   Para reiniciar: $MONITOR_SCRIPT restart
#   Para ver estado: $MONITOR_SCRIPT status

INSTALL_DIR="$INSTALL_DIR"
PID_FILE="/tmp/cloudflare-monitor.pid"
LOG_FILE="/var/log/cloudflare-monitor.log"

start_service() {
    echo "Iniciando servicio de monitoreo CloudFlare..."
    cd \$INSTALL_DIR
    source venv/bin/activate
    nohup python3 \$INSTALL_DIR/monitor.py > \$LOG_FILE 2>&1 &
    echo \$! > \$PID_FILE
    echo "Servicio de monitoreo iniciado con PID \$(cat \$PID_FILE)"
}

stop_service() {
    if [ -f "\$PID_FILE" ]; then
        PID=\$(cat \$PID_FILE)
        echo "Deteniendo servicio de monitoreo (PID: \$PID)..."
        kill \$PID
        rm \$PID_FILE
        echo "Servicio de monitoreo detenido."
    else
        echo "El servicio de monitoreo no está en ejecución."
    fi
}

status_service() {
    if [ -f "\$PID_FILE" ]; then
        PID=\$(cat \$PID_FILE)
        if ps -p \$PID > /dev/null; then
            echo "El servicio de monitoreo está en ejecución (PID: \$PID)"
            return 0
        else
            echo "El servicio de monitoreo no está en ejecución (PID antiguo: \$PID)"
            rm \$PID_FILE
            return 1
        fi
    else
        echo "El servicio de monitoreo no está en ejecución."
        return 1
    fi
}

case "\$1" in
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    restart)
        stop_service
        sleep 2
        start_service
        ;;
    status)
        status_service
        ;;
    *)
        echo "Uso: \$0 {start|stop|restart|status}"
        exit 1
        ;;
esac

exit 0
EOF

    # Hacer ejecutables los scripts
    chmod +x $START_SCRIPT
    chmod +x $MONITOR_SCRIPT
    
    # Iniciar los servicios
    print_status "Iniciando servicios..."
    $START_SCRIPT start
    $MONITOR_SCRIPT start
    
    # Verificar si los servicios se iniciaron correctamente
    if $START_SCRIPT status; then
        print_status "Servicio principal iniciado correctamente."
    else
        print_error "Error al iniciar el servicio principal. Verifica los logs en /var/log/gestor-tuneles-cloudflare.log"
    fi
    
    if $MONITOR_SCRIPT status; then
        print_status "Servicio de monitoreo iniciado correctamente."
    else
        print_warning "El servicio de monitoreo no pudo iniciarse. Verifica los logs en /var/log/cloudflare-monitor.log"
        print_warning "Esto no afecta al funcionamiento principal de la aplicación."
    fi
    
    # Añadir a inittab o rc.local para inicio automático si están disponibles
    if [ -f "/etc/rc.local" ]; then
        # Verificar si ya están las líneas para evitar duplicados
        if ! grep -q "$START_SCRIPT start" /etc/rc.local; then
            print_status "Añadiendo servicios a rc.local para inicio automático..."
            # Insertar antes del 'exit 0' final
            sed -i "/exit 0/i $START_SCRIPT start\n$MONITOR_SCRIPT start" /etc/rc.local
            chmod +x /etc/rc.local
        fi
    else
        print_warning "No se encontró rc.local. Los servicios no se iniciarán automáticamente al arranque."
        print_warning "Para iniciar manualmente los servicios después de reiniciar el sistema, ejecuta:"
        print_warning "sudo $START_SCRIPT start"
        print_warning "sudo $MONITOR_SCRIPT start"
    fi
fi

# Configuración para producción
print_status "Aplicando configuraciones de seguridad adicionales..."
mkdir -p $INSTALL_DIR/config
chmod 700 $INSTALL_DIR/config

# Copiar plantilla de configuración del monitor
if [ -f "$INSTALL_DIR/monitor_config_template.json" ]; then
    cp "$INSTALL_DIR/monitor_config_template.json" "$INSTALL_DIR/config/monitor_config.json"
    chmod 600 "$INSTALL_DIR/config/monitor_config.json"
    print_status "Plantilla de configuración del monitor instalada"
fi

# Variable para entorno de producción
grep -q "FLASK_ENV=production" /etc/environment || echo "FLASK_ENV=production" >> /etc/environment

# Crear directorio de logs
mkdir -p /var/log/cloudflare
touch /var/log/cloudflare-monitor.log
chmod 640 /var/log/cloudflare-monitor.log

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

# Instrucciones específicas según el método de instalación
if [ "$SYSTEMD_AVAILABLE" = true ]; then
    print_status "Monitoreo (systemd):"
    print_status "- Estado del servicio principal: systemctl status gestor-tuneles-cloudflare"
    print_status "- Estado del servicio de monitoreo: systemctl status cloudflare-monitor"
    print_status "- Logs: journalctl -u gestor-tuneles-cloudflare -f"
else
    print_status "Monitoreo (scripts):"
    print_status "- Estado del servicio principal: $START_SCRIPT status"
    print_status "- Estado del servicio de monitoreo: $MONITOR_SCRIPT status"
    print_status "- Logs principales: cat /var/log/gestor-tuneles-cloudflare.log"
    print_status "- Logs de monitoreo: cat /var/log/cloudflare-monitor.log"
    print_status ""
    print_status "Gestión de servicios:"
    print_status "- Reiniciar servicio principal: $START_SCRIPT restart"
    print_status "- Reiniciar servicio de monitoreo: $MONITOR_SCRIPT restart"
fi

print_status "- API de salud: http://$IP_ADDRESS:5000/health"
print_status ""
print_status "Para configurar notificaciones por correo, edita el archivo:"
print_status "$INSTALL_DIR/config/monitor_config.json"
print_status "====================================================="

exit 0
