#!/bin/bash

# Script de actualización para el Gestor de Túneles CloudFlare
# Este script actualiza la aplicación de gestión de túneles CloudFlare

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

# Función para realizar copias de seguridad
backup_app() {
    local backup_dir="/opt/gestor-tuneles-cloudflare/backup"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="${backup_dir}/backup_${timestamp}.tar.gz"
    
    print_status "Creando copia de seguridad..."
    mkdir -p "$backup_dir"
    
    # Excluir directorios que no necesitan respaldo
    tar --exclude="./backup" --exclude="./venv" --exclude="./.git" -czf "$backup_file" -C /opt/gestor-tuneles-cloudflare .
    
    if [ $? -eq 0 ]; then
        print_status "Copia de seguridad creada en: $backup_file"
        echo "$backup_file"
    else
        print_error "Error al crear la copia de seguridad"
        return 1
    fi
}

# Función para restaurar desde copia de seguridad
restore_from_backup() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        print_error "Archivo de respaldo no encontrado: $backup_file"
        return 1
    fi
    
    print_status "Restaurando desde copia de seguridad: $backup_file"
    
    # Restaurar archivos (preservando venv)
    tar --exclude="./venv" -xzf "$backup_file" -C /opt/gestor-tuneles-cloudflare
    
    if [ $? -eq 0 ]; then
        print_status "Restauración completada con éxito"
        return 0
    else
        print_error "Error al restaurar desde copia de seguridad"
        return 1
    fi
}

# Verificar que se está ejecutando como root
if [ "$EUID" -ne 0 ]; then
    print_error "Este script debe ejecutarse como root o con sudo"
    exit 1
fi

# Verificar que la aplicación está instalada
if [ ! -d "/opt/gestor-tuneles-cloudflare" ]; then
    print_error "La aplicación no está instalada en /opt/gestor-tuneles-cloudflare"
    print_error "Ejecute primero el script de instalación"
    exit 1
fi

# Directorio de la aplicación
APP_DIR="/opt/gestor-tuneles-cloudflare"
cd "$APP_DIR"

# Crear copia de seguridad antes de actualizar
BACKUP_FILE=$(backup_app)
if [ $? -ne 0 ]; then
    print_warning "No se pudo crear copia de seguridad. ¿Desea continuar de todos modos? (s/n)"
    read -r response
    if [[ "$response" != "s" ]]; then
        print_status "Actualización cancelada."
        exit 0
    fi
fi

# Verificar conexión a Internet
print_status "Verificando conexión a Internet..."
if ! ping -c 1 google.com &> /dev/null; then
    print_error "No hay conexión a Internet. Verifica la conectividad de red."
    exit 1
fi

# Actualizar desde repositorio Git
if [ -d "$APP_DIR/.git" ]; then
    print_status "Repositorio Git encontrado. Actualizando desde repositorio remoto..."
    
    # Guardar configuración personalizada
    if [ -f "$APP_DIR/config/monitor_config.json" ]; then
        cp "$APP_DIR/config/monitor_config.json" /tmp/monitor_config.json.bak
    fi
    
    # Actualizar repositorio
    git fetch --all
    git reset --hard origin/main
    
    if [ $? -ne 0 ]; then
        print_error "Error al actualizar desde repositorio Git."
        print_warning "Intentando restaurar desde copia de seguridad..."
        
        if [ -n "$BACKUP_FILE" ]; then
            restore_from_backup "$BACKUP_FILE"
        fi
        
        print_error "Actualización fallida. Por favor, intente manualmente."
        exit 1
    fi
    
    # Restaurar configuración personalizada
    if [ -f "/tmp/monitor_config.json.bak" ]; then
        cp /tmp/monitor_config.json.bak "$APP_DIR/config/monitor_config.json"
        rm /tmp/monitor_config.json.bak
    fi
else
    print_warning "No se encontró repositorio Git. Intentando actualizar desde GitHub..."
    
    # Crear directorio temporal
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"
    
    # Intentar clonar repositorio
    if git clone https://github.com/innovafpiesmmg/cloudflare.git .; then
        print_status "Repositorio descargado correctamente. Actualizando archivos..."
        
        # Guardar configuración personalizada
        if [ -f "$APP_DIR/config/monitor_config.json" ]; then
            cp "$APP_DIR/config/monitor_config.json" /tmp/monitor_config.json.bak
        fi
        
        # Copiar archivos nuevos (excluyendo config)
        rsync -av --exclude="config" --exclude="venv" ./ "$APP_DIR/"
        
        # Restaurar configuración
        if [ -f "/tmp/monitor_config.json.bak" ]; then
            cp /tmp/monitor_config.json.bak "$APP_DIR/config/monitor_config.json"
            rm /tmp/monitor_config.json.bak
        fi
        
        # Inicializar repositorio Git para futuras actualizaciones
        cd "$APP_DIR"
        git init
        git remote add origin https://github.com/innovafpiesmmg/cloudflare.git
        git fetch
        git checkout -f -t origin/main || git checkout -f main
    else
        print_error "No se pudo clonar el repositorio desde GitHub."
        print_warning "Intentando actualización alternativa..."
        
        # Intentar descargar archivo zip desde GitHub
        cd "$TMP_DIR"
        if wget -q https://github.com/innovafpiesmmg/cloudflare/archive/refs/heads/main.zip; then
            print_status "Archivo zip descargado. Extrayendo..."
            apt-get install -y unzip
            unzip -q main.zip
            
            # Guardar configuración personalizada
            if [ -f "$APP_DIR/config/monitor_config.json" ]; then
                cp "$APP_DIR/config/monitor_config.json" /tmp/monitor_config.json.bak
            fi
            
            # Copiar archivos nuevos (excluyendo config)
            rsync -av --exclude="config" --exclude="venv" cloudflare-main/ "$APP_DIR/"
            
            # Restaurar configuración
            if [ -f "/tmp/monitor_config.json.bak" ]; then
                cp /tmp/monitor_config.json.bak "$APP_DIR/config/monitor_config.json"
                rm /tmp/monitor_config.json.bak
            fi
        else
            print_error "No se pudo descargar el archivo zip desde GitHub."
            print_warning "Actualizando archivos críticos manualmente..."
            
            # Actualizar archivos críticos si no hay otra forma
            mkdir -p "$TMP_DIR/manual"
            cd "$TMP_DIR/manual"
            
            # Intentar descargar archivos críticos uno por uno
            wget -q https://raw.githubusercontent.com/innovafpiesmmg/cloudflare/main/main.py -O main.py || true
            wget -q https://raw.githubusercontent.com/innovafpiesmmg/cloudflare/main/app.py -O app.py || true
            wget -q https://raw.githubusercontent.com/innovafpiesmmg/cloudflare/main/monitor.py -O monitor.py || true
            
            # Copiar archivos que se pudieron descargar
            find . -type f -name "*.py" -exec cp {} "$APP_DIR/" \;
            
            if [ "$(find . -type f -name "*.py" | wc -l)" -eq 0 ]; then
                print_error "No se pudo descargar ningún archivo crítico."
                print_warning "Restaurando desde copia de seguridad..."
                
                if [ -n "$BACKUP_FILE" ]; then
                    restore_from_backup "$BACKUP_FILE"
                fi
                
                print_error "Actualización fallida. Por favor, intente manualmente."
                rm -rf "$TMP_DIR"
                exit 1
            fi
        fi
    fi
    
    # Limpiar
    rm -rf "$TMP_DIR"
fi

# Actualizar entorno virtual y dependencias
cd "$APP_DIR"
print_status "Actualizando dependencias de Python..."

if [ -f "$APP_DIR/requirements.txt" ]; then
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
    deactivate
else
    print_warning "No se encontró archivo requirements.txt. Actualizando dependencias básicas..."
    source venv/bin/activate
    pip install --upgrade pip flask pyyaml psutil requests pillow gunicorn
    deactivate
fi

# Asegurar permisos correctos
print_status "Configurando permisos..."
chmod 700 "$APP_DIR/config"
chmod -R 644 "$APP_DIR/static"
chmod -R 644 "$APP_DIR/templates"
find "$APP_DIR" -name "*.py" -exec chmod 755 {} \;
find "$APP_DIR" -name "*.sh" -exec chmod 755 {} \;

# Reiniciar servicios
print_status "Reiniciando servicios..."
systemctl daemon-reload
systemctl restart gestor-tuneles-cloudflare
systemctl restart cloudflare-monitor

# Verificar estado de los servicios
if systemctl is-active --quiet gestor-tuneles-cloudflare; then
    print_status "Servicio principal reiniciado correctamente."
else
    print_error "Error al reiniciar el servicio principal."
    print_warning "Restaurando desde copia de seguridad..."
    
    if [ -n "$BACKUP_FILE" ]; then
        restore_from_backup "$BACKUP_FILE"
        systemctl restart gestor-tuneles-cloudflare
    fi
    
    if ! systemctl is-active --quiet gestor-tuneles-cloudflare; then
        print_error "No se pudo restaurar el servicio. Verificando logs:"
        journalctl -u gestor-tuneles-cloudflare -n 20
    fi
fi

if systemctl is-active --quiet cloudflare-monitor; then
    print_status "Servicio de monitoreo reiniciado correctamente."
else
    print_warning "El servicio de monitoreo no pudo reiniciarse. Verificando logs:"
    journalctl -u cloudflare-monitor -n 10
    print_warning "Esto no afecta al funcionamiento principal de la aplicación."
fi

# Mostrar información final
IP_ADDRESS=$(hostname -I | awk '{print $1}')
CURRENT_VERSION=$(grep -o '"version": "[^"]*"' "$APP_DIR/config/monitor_config.json" 2>/dev/null | cut -d'"' -f4 || echo "Desconocida")

print_status "====================================================="
print_status "  Gestor de Túneles CloudFlare actualizado correctamente  "
print_status "====================================================="
print_status "Versión: $CURRENT_VERSION"
print_status "Puedes acceder a la interfaz web en:"
print_status "http://$IP_ADDRESS:5000"
print_status ""
print_status "Para verificar el estado de los servicios:"
print_status "- systemctl status gestor-tuneles-cloudflare"
print_status "- systemctl status cloudflare-monitor"
print_status ""
print_status "En caso de problemas, se ha creado una copia de seguridad en:"
if [ -n "$BACKUP_FILE" ]; then
    print_status "$BACKUP_FILE"
    print_status "Para restaurar: tar -xzf $BACKUP_FILE -C $APP_DIR"
fi
print_status "====================================================="

exit 0