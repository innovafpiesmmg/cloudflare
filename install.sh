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

# Configuración inicial de Cloudflare (opcional)
print_status "====================================================="
print_status "  Configuración inicial de Cloudflare  "
print_status "====================================================="
print_status "Esta configuración es opcional. Puedes saltarla y configurar Cloudflare más tarde."
print_status "Si tienes una API key de Cloudflare, puedes configurarla ahora para que la aplicación"
print_status "pueda empezar a funcionar con tu cuenta de Cloudflare de inmediato."
print_status ""

read -p "¿Deseas configurar la API key de Cloudflare ahora? (s/n): " setup_cloudflare
if [ "$setup_cloudflare" = "s" ]; then
    # Crear archivo para almacenar la API key de forma segura
    CF_CONFIG_FILE="$INSTALL_DIR/config/cloudflare.json"
    
    print_status "Para obtener tu API key de Cloudflare:"
    print_status "1. Inicia sesión en tu cuenta de Cloudflare (https://dash.cloudflare.com/)"
    print_status "2. Ve a 'Mi perfil' > 'API Tokens'"
    print_status "3. Crea un nuevo token con permisos para administrar túneles y DNS"
    print_status "   o usa la opción 'Global API Key' para un acceso completo"
    print_status ""
    
    read -p "Ingresa tu API key de Cloudflare: " cf_api_key
    read -p "Ingresa el correo electrónico asociado a tu cuenta de Cloudflare: " cf_email
    
    # Guardar la información de forma segura
    cat > $CF_CONFIG_FILE << EOF
{
    "api_key": "$cf_api_key",
    "email": "$cf_email",
    "configured": true
}
EOF
    
    # Asegurar que solo root puede leer este archivo
    chmod 600 $CF_CONFIG_FILE
    
    print_status "Credenciales de Cloudflare guardadas correctamente."
    
    # Opcionalmente configurar un túnel inicial
    read -p "¿Deseas crear un túnel inicial para esta aplicación? (s/n): " create_tunnel
    if [ "$create_tunnel" = "s" ]; then
        read -p "Ingresa un nombre para el túnel: " tunnel_name
        read -p "Ingresa el dominio para acceder a esta aplicación (ej: app.midominio.com): " app_domain
        
        print_status "Creando túnel inicial '$tunnel_name'..."
        
        # Activar entorno virtual para ejecutar Python
        source $INSTALL_DIR/venv/bin/activate
        
        # Crear un script temporal para la configuración inicial
        SETUP_SCRIPT="$INSTALL_DIR/setup_initial_tunnel.py"
        
        cat > $SETUP_SCRIPT << EOF
import json
import os
import subprocess
import sys
import time

# Cargar configuración
try:
    with open('$CF_CONFIG_FILE', 'r') as f:
        cf_config = json.load(f)
    
    api_key = cf_config.get('api_key')
    email = cf_config.get('email')
    
    if not api_key or not email:
        print("Error: No se encontraron credenciales válidas de Cloudflare")
        sys.exit(1)
    
    # Verificar que cloudflared está instalado
    result = subprocess.run(['which', 'cloudflared'], capture_output=True, text=True)
    if result.returncode != 0:
        print("Error: cloudflared no está instalado")
        print("Instala cloudflared primero usando la opción en la interfaz web")
        sys.exit(1)
    
    # Autenticarse con Cloudflare primero
    print("Autenticando con Cloudflare...")
    auth_process = subprocess.run(
        ['cloudflared', 'tunnel', 'login'],
        capture_output=True, 
        text=True
    )
    
    if auth_process.returncode != 0:
        print(f"Error al autenticar con Cloudflare: {auth_process.stderr}")
        sys.exit(1)
    
    # Crear el túnel
    print(f"Creando túnel '{tunnel_name}'...")
    create_process = subprocess.run(
        ['cloudflared', 'tunnel', 'create', '$tunnel_name'],
        capture_output=True,
        text=True
    )
    
    if create_process.returncode != 0:
        print(f"Error al crear el túnel: {create_process.stderr}")
        sys.exit(1)
    
    tunnel_id = None
    for line in create_process.stdout.splitlines():
        if "Created tunnel" in line:
            tunnel_id = line.split()[-1].strip()
    
    if not tunnel_id:
        print("No se pudo obtener el ID del túnel")
        sys.exit(1)
    
    print(f"Túnel creado con ID: {tunnel_id}")
    
    # Configurar el dominio para el túnel
    print(f"Configurando dominio {app_domain} para el túnel...")
    config_dir = "/etc/cloudflared/configs"
    os.makedirs(config_dir, exist_ok=True)
    
    # Configurar el túnel para esta aplicación
    tunnel_config = {
        'tunnel_id': tunnel_id,
        'credentials_file': f'/etc/cloudflared/{tunnel_id}.json',
        'services': [
            {
                'name': 'gestor-tuneles',
                'port': '5000',
                'domain': '$app_domain'
            }
        ]
    }
    
    # Guardar configuración
    with open(f'{config_dir}/$tunnel_name.json', 'w') as f:
        json.dump(tunnel_config, f, indent=2)
    
    # Generar YAML para el túnel
    yaml_config = {
        'tunnel': '$tunnel_name',
        'credentials-file': f'/etc/cloudflared/{tunnel_id}.json',
        'ingress': [
            {
                'hostname': '$app_domain',
                'service': 'http://localhost:5000'
            },
            {
                'service': 'http_status:404'
            }
        ]
    }
    
    import yaml
    with open(f'/etc/cloudflared/$tunnel_name.yml', 'w') as f:
        yaml.dump(yaml_config, f, default_flow_style=False)
    
    print("Configuración del túnel completada.")
    
    # Intentar configurar como servicio
    print("Configurando el túnel como servicio...")
    if '$SYSTEMD_AVAILABLE' == 'true':
        # Usar systemd
        service_name = f"cloudflared-$tunnel_name"
        service_content = f"""[Unit]
Description=Cloudflare Tunnel for $tunnel_name
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/cloudflared tunnel run --no-autoupdate $tunnel_name
Restart=on-failure
RestartSec=5s
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
"""
        
        with open(f"/etc/systemd/system/{service_name}.service", "w") as f:
            f.write(service_content)
        
        subprocess.run(['systemctl', 'daemon-reload'])
        subprocess.run(['systemctl', 'enable', service_name])
        subprocess.run(['systemctl', 'start', service_name])
        print(f"Servicio {service_name} iniciado mediante systemd")
    else:
        # Usar script alternativo
        script_path = f"/usr/local/bin/cloudflared-$tunnel_name"
        script_content = f"""#!/bin/bash
# Script para iniciar el túnel CloudFlare $tunnel_name
# Uso:
#   Para iniciar: {script_path} start
#   Para detener: {script_path} stop

TUNNEL_NAME="$tunnel_name"
TUNNEL_ID="{tunnel_id}"
PID_FILE="/tmp/cloudflared-$tunnel_name.pid"

start_tunnel() {{
    echo "Iniciando túnel $TUNNEL_NAME..."
    nohup cloudflared tunnel run --no-autoupdate $TUNNEL_NAME > /var/log/cloudflared-$TUNNEL_NAME.log 2>&1 &
    echo $! > $PID_FILE
    echo "Túnel iniciado con PID $(cat $PID_FILE)"
}}

stop_tunnel() {{
    if [ -f "$PID_FILE" ]; then
        PID=$(cat $PID_FILE)
        echo "Deteniendo túnel $TUNNEL_NAME (PID: $PID)..."
        kill $PID
        rm $PID_FILE
        echo "Túnel detenido"
    else
        echo "El túnel no está en ejecución"
    fi
}}

status_tunnel() {{
    if [ -f "$PID_FILE" ]; then
        PID=$(cat $PID_FILE)
        if ps -p $PID > /dev/null; then
            echo "El túnel $TUNNEL_NAME está en ejecución (PID: $PID)"
        else
            echo "El túnel $TUNNEL_NAME no está en ejecución (PID antiguo: $PID)"
            rm $PID_FILE
        fi
    else
        echo "El túnel $TUNNEL_NAME no está en ejecución"
    fi
}}

case "$1" in
    start)
        start_tunnel
        ;;
    stop)
        stop_tunnel
        ;;
    restart)
        stop_tunnel
        sleep 2
        start_tunnel
        ;;
    status)
        status_tunnel
        ;;
    *)
        echo "Uso: $0 {{start|stop|restart|status}}"
        exit 1
        ;;
esac

exit 0
"""
        
        with open(script_path, "w") as f:
            f.write(script_content)
        
        # Hacer el script ejecutable
        import os
        os.chmod(script_path, 0o755)
        
        # Iniciar el túnel
        subprocess.run([script_path, 'start'])
        print(f"Túnel iniciado mediante script {script_path}")
    
    print("¡Felicidades! El túnel se ha configurado y debería estar funcionando.")
    print(f"La aplicación estará disponible en https://{app_domain} en unos minutos")
    print("(puede tardar hasta 5 minutos para que los cambios DNS se propaguen)")
    
except Exception as e:
    print(f"Error durante la configuración: {str(e)}")
    sys.exit(1)
EOF

        # Ejecutar el script
        python3 $SETUP_SCRIPT
        
        # Eliminar el script temporal
        rm $SETUP_SCRIPT
    fi
else
    print_status "Configuración de Cloudflare omitida. Puedes configurarla más tarde desde la interfaz web."
fi

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
