import os
import json
import subprocess
import re
import logging
from datetime import datetime
import yaml
import shutil

# Configurar logging
logger = logging.getLogger(__name__)

# Rutas de archivos de cloudflared
CLOUDFLARED_CONFIG_DIR = "/etc/cloudflared"
SYSTEMD_DIR = "/etc/systemd/system"

def check_cloudflared_installed():
    """Verificar si cloudflared está instalado"""
    try:
        result = subprocess.run(["which", "cloudflared"], capture_output=True, text=True)
        return result.returncode == 0
    except Exception as e:
        logger.error(f"Error al verificar instalación de cloudflared: {str(e)}")
        return False

def get_cloudflared_version():
    """Obtener la versión de cloudflared instalada"""
    try:
        result = subprocess.run(["cloudflared", "--version"], capture_output=True, text=True)
        match = re.search(r"version\s+(\S+)", result.stdout)
        if match:
            return match.group(1)
        return "Versión desconocida"
    except Exception as e:
        logger.error(f"Error al obtener versión de cloudflared: {str(e)}")
        return None

def install_cloudflared():
    """Instalar cloudflared"""
    # Crear directorios de configuración si no existen
    if not os.path.exists(CLOUDFLARED_CONFIG_DIR):
        os.makedirs(CLOUDFLARED_CONFIG_DIR, exist_ok=True)
    
    # Intentar primero el método principal (paquete DEB)
    if _install_cloudflared_deb():
        logger.info("Cloudflared instalado correctamente mediante paquete DEB.")
        return True
    
    # Si falla el método principal, intentar el binario directo
    logger.warning("Instalación mediante paquete DEB falló, intentando método alternativo...")
    if _install_cloudflared_binary():
        logger.info("Cloudflared instalado correctamente mediante binario directo.")
        return True
    
    # Si todo falla, devolver error
    logger.error("Todos los métodos de instalación de cloudflared fallaron.")
    return False

def _install_cloudflared_deb():
    """Método principal: instalar cloudflared mediante paquete DEB"""
    try:
        # Descargar el paquete más reciente para Ubuntu/Debian con timeout
        logger.info("Descargando cloudflared (método DEB)...")
        curl_cmd = [
            "curl", "-L", "--connect-timeout", "30", "--max-time", "120",
            "--output", "/tmp/cloudflared.deb",
            "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
        ]
        
        # Ejecutar con timeout
        curl_process = subprocess.Popen(curl_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            stdout, stderr = curl_process.communicate(timeout=180)  # 3 minutos como máximo
            if curl_process.returncode != 0:
                logger.error(f"Error al descargar: {stderr.decode() if stderr else 'Desconocido'}")
                return False
        except subprocess.TimeoutExpired:
            curl_process.kill()
            logger.error("Timeout al descargar cloudflared.")
            return False
        
        # Verificar que el archivo se descargó correctamente
        if not os.path.exists("/tmp/cloudflared.deb") or os.path.getsize("/tmp/cloudflared.deb") < 1000:
            logger.error("El archivo descargado está vacío o es demasiado pequeño.")
            return False
        
        # Instalar el paquete con timeout
        logger.info("Instalando cloudflared mediante dpkg...")
        dpkg_cmd = ["sudo", "dpkg", "-i", "/tmp/cloudflared.deb"]
        
        dpkg_process = subprocess.Popen(dpkg_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            stdout, stderr = dpkg_process.communicate(timeout=120)  # 2 minutos como máximo
            if dpkg_process.returncode != 0:
                logger.error(f"Error al instalar: {stderr.decode() if stderr else 'Desconocido'}")
                
                # Intentar solucionar dependencias
                logger.info("Intentando solucionar dependencias...")
                fix_process = subprocess.run(["sudo", "apt-get", "install", "-f", "-y"], 
                                             capture_output=True, timeout=120)
                if fix_process.returncode != 0:
                    logger.error("No se pudieron solucionar las dependencias.")
                    return False
                
                # Volver a intentar la instalación
                retry_process = subprocess.run(dpkg_cmd, capture_output=True, timeout=120)
                if retry_process.returncode != 0:
                    logger.error("Falló el segundo intento de instalación.")
                    return False
        except subprocess.TimeoutExpired:
            dpkg_process.kill()
            logger.error("Timeout al instalar cloudflared.")
            return False
        
        # Verificar que cloudflared se instaló correctamente
        verify_cmd = ["which", "cloudflared"]
        verify_process = subprocess.run(verify_cmd, capture_output=True, timeout=10)
        if verify_process.returncode != 0:
            logger.error("No se pudo verificar la instalación de cloudflared.")
            return False
        
        logger.info("Cloudflared instalado correctamente mediante paquete DEB.")
        return True
        
    except Exception as e:
        logger.error(f"Error durante la instalación de cloudflared (método DEB): {str(e)}")
        return False

def _install_cloudflared_binary():
    """Método alternativo: instalar cloudflared como binario directo"""
    try:
        # Descargar el binario directamente
        logger.info("Descargando cloudflared (método binario)...")
        curl_cmd = [
            "curl", "-L", "--connect-timeout", "30", "--max-time", "120",
            "--output", "/usr/local/bin/cloudflared",
            "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
        ]
        
        # Ejecutar con timeout
        curl_process = subprocess.Popen(curl_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            stdout, stderr = curl_process.communicate(timeout=180)
            if curl_process.returncode != 0:
                logger.error(f"Error al descargar binario: {stderr.decode() if stderr else 'Desconocido'}")
                return False
        except subprocess.TimeoutExpired:
            curl_process.kill()
            logger.error("Timeout al descargar binario cloudflared.")
            return False
        
        # Dar permisos de ejecución
        logger.info("Dando permisos de ejecución...")
        chmod_cmd = ["sudo", "chmod", "+x", "/usr/local/bin/cloudflared"]
        chmod_process = subprocess.run(chmod_cmd, capture_output=True, timeout=10)
        if chmod_process.returncode != 0:
            logger.error("Error al dar permisos de ejecución.")
            return False
        
        # Verificar que cloudflared se instaló correctamente
        verify_cmd = ["which", "cloudflared"]
        verify_process = subprocess.run(verify_cmd, capture_output=True, timeout=10)
        if verify_process.returncode != 0:
            logger.error("No se pudo verificar la instalación binaria de cloudflared.")
            return False
        
        # Crear enlace simbólico si es necesario
        if not os.path.exists("/usr/bin/cloudflared"):
            try:
                os.symlink("/usr/local/bin/cloudflared", "/usr/bin/cloudflared")
            except Exception as e:
                logger.warning(f"No se pudo crear enlace simbólico: {str(e)}")
        
        logger.info("Cloudflared instalado correctamente mediante binario directo.")
        return True
        
    except Exception as e:
        logger.error(f"Error durante la instalación de cloudflared (método binario): {str(e)}")
        return False

def get_tunnels_list():
    """Obtener lista de túneles configurados"""
    try:
        result = subprocess.run(["cloudflared", "tunnel", "list", "--output", "json"], capture_output=True, text=True)
        if result.returncode != 0:
            logger.error(f"Error al obtener lista de túneles: {result.stderr}")
            return []
        
        tunnels_data = json.loads(result.stdout)
        
        # Añadir información de estado (running o no)
        for tunnel in tunnels_data:
            tunnel['running'] = is_tunnel_running(tunnel['name'])
        
        return tunnels_data
    except Exception as e:
        logger.error(f"Error al obtener lista de túneles: {str(e)}")
        return []

def is_tunnel_running(tunnel_name):
    """Verificar si un túnel está en ejecución"""
    try:
        # Comprobar si el servicio systemd está activo
        if os.path.exists(f"{SYSTEMD_DIR}/cloudflared-{tunnel_name}.service"):
            result = subprocess.run(["systemctl", "is-active", f"cloudflared-{tunnel_name}"], capture_output=True, text=True)
            return result.stdout.strip() == "active"
        
        # Alternativa: buscar el proceso
        ps_result = subprocess.run(["pgrep", "-f", f"cloudflared.*{tunnel_name}"], capture_output=True, text=True)
        return ps_result.returncode == 0
    except Exception as e:
        logger.error(f"Error al verificar estado del túnel {tunnel_name}: {str(e)}")
        return False

def create_tunnel(tunnel_name):
    """Crear un nuevo túnel"""
    try:
        # Crear el túnel
        result = subprocess.run(
            ["cloudflared", "tunnel", "create", tunnel_name],
            capture_output=True, text=True
        )
        
        if result.returncode != 0:
            logger.error(f"Error al crear túnel: {result.stderr}")
            return {"success": False, "error": result.stderr}
        
        # Extraer el ID del túnel del output
        tunnel_id_match = re.search(r"Created tunnel ([\w-]+) with ID ([0-9a-f-]+)", result.stdout)
        if not tunnel_id_match:
            logger.error(f"No se pudo obtener el ID del túnel. Output: {result.stdout}")
            return {"success": False, "error": "No se pudo obtener el ID del túnel"}
        
        tunnel_id = tunnel_id_match.group(2)
        
        # Obtener el token del túnel
        token_result = subprocess.run(
            ["cloudflared", "tunnel", "token", "--id", tunnel_id],
            capture_output=True, text=True
        )
        
        if token_result.returncode != 0:
            logger.error(f"Error al obtener token del túnel: {token_result.stderr}")
            return {"success": True, "tunnel_id": tunnel_id, "token": None}
        
        return {
            "success": True, 
            "tunnel_id": tunnel_id,
            "token": token_result.stdout.strip()
        }
    except Exception as e:
        logger.error(f"Error al crear túnel: {str(e)}")
        return {"success": False, "error": str(e)}

def get_tunnel_status(tunnel_name):
    """Obtener el estado de un túnel"""
    try:
        tunnel_running = is_tunnel_running(tunnel_name)
        status = {
            "running": tunnel_running,
            "pid": None,
            "uptime": None,
            "connectivity": False,
            "last_updated": datetime.now().strftime("%H:%M:%S")
        }
        
        if tunnel_running:
            # Obtener PID
            ps_result = subprocess.run(
                ["pgrep", "-f", f"cloudflared.*{tunnel_name}"], 
                capture_output=True, text=True
            )
            if ps_result.returncode == 0:
                status["pid"] = ps_result.stdout.strip()
                
                # Obtener uptime
                if status["pid"]:
                    uptime_result = subprocess.run(
                        ["ps", "-p", status["pid"], "-o", "etime="], 
                        capture_output=True, text=True
                    )
                    if uptime_result.returncode == 0:
                        status["uptime"] = uptime_result.stdout.strip()
            
            # Verificar conectividad
            status["connectivity"] = check_tunnel_connectivity(tunnel_name)
            
        return status
    except Exception as e:
        logger.error(f"Error al obtener estado del túnel {tunnel_name}: {str(e)}")
        return {
            "running": False,
            "pid": None,
            "uptime": None,
            "connectivity": False,
            "last_updated": datetime.now().strftime("%H:%M:%S"),
            "error": str(e)
        }

def start_tunnel(tunnel_name):
    """Iniciar un túnel"""
    try:
        # Comprobar si existe un servicio systemd para este túnel
        service_path = f"{SYSTEMD_DIR}/cloudflared-{tunnel_name}.service"
        if os.path.exists(service_path):
            # Iniciar el servicio
            result = subprocess.run(
                ["sudo", "systemctl", "start", f"cloudflared-{tunnel_name}"],
                capture_output=True, text=True
            )
            
            if result.returncode != 0:
                logger.error(f"Error al iniciar servicio del túnel: {result.stderr}")
                return {"success": False, "error": result.stderr}
        else:
            # Ejecutar en segundo plano
            result = subprocess.run(
                ["cloudflared", "tunnel", "run", tunnel_name],
                capture_output=True, text=True
            )
            
            if result.returncode != 0:
                logger.error(f"Error al iniciar túnel: {result.stderr}")
                return {"success": False, "error": result.stderr}
        
        return {"success": True}
    except Exception as e:
        logger.error(f"Error al iniciar túnel {tunnel_name}: {str(e)}")
        return {"success": False, "error": str(e)}

def stop_tunnel(tunnel_name):
    """Detener un túnel"""
    try:
        # Comprobar si existe un servicio systemd para este túnel
        service_path = f"{SYSTEMD_DIR}/cloudflared-{tunnel_name}.service"
        if os.path.exists(service_path):
            # Detener el servicio
            result = subprocess.run(
                ["sudo", "systemctl", "stop", f"cloudflared-{tunnel_name}"],
                capture_output=True, text=True
            )
            
            if result.returncode != 0:
                logger.error(f"Error al detener servicio del túnel: {result.stderr}")
                return {"success": False, "error": result.stderr}
        else:
            # Matar el proceso
            ps_result = subprocess.run(
                ["pgrep", "-f", f"cloudflared.*{tunnel_name}"], 
                capture_output=True, text=True
            )
            
            if ps_result.returncode == 0:
                pid = ps_result.stdout.strip()
                kill_result = subprocess.run(
                    ["sudo", "kill", pid],
                    capture_output=True, text=True
                )
                
                if kill_result.returncode != 0:
                    logger.error(f"Error al matar proceso del túnel: {kill_result.stderr}")
                    return {"success": False, "error": kill_result.stderr}
        
        return {"success": True}
    except Exception as e:
        logger.error(f"Error al detener túnel {tunnel_name}: {str(e)}")
        return {"success": False, "error": str(e)}

def delete_tunnel(tunnel_name):
    """Eliminar un túnel"""
    try:
        # Primero detener el túnel si está en ejecución
        if is_tunnel_running(tunnel_name):
            stop_result = stop_tunnel(tunnel_name)
            if not stop_result["success"]:
                logger.error(f"Error al detener túnel antes de eliminarlo: {stop_result['error']}")
                return {"success": False, "error": f"No se pudo detener el túnel: {stop_result['error']}"}
        
        # Eliminar el túnel
        result = subprocess.run(
            ["cloudflared", "tunnel", "delete", tunnel_name],
            capture_output=True, text=True
        )
        
        if result.returncode != 0:
            logger.error(f"Error al eliminar túnel: {result.stderr}")
            return {"success": False, "error": result.stderr}
        
        # Eliminar archivo de servicio systemd si existe
        service_path = f"{SYSTEMD_DIR}/cloudflared-{tunnel_name}.service"
        if os.path.exists(service_path):
            try:
                os.remove(service_path)
                # Recargar systemd
                subprocess.run(["sudo", "systemctl", "daemon-reload"], check=True)
            except Exception as e:
                logger.warning(f"No se pudo eliminar el archivo de servicio: {str(e)}")
        
        # Eliminar archivos de configuración
        config_dir = f"{CLOUDFLARED_CONFIG_DIR}"
        if os.path.exists(config_dir):
            try:
                # Buscar archivos relacionados con este túnel y eliminarlos
                for filename in os.listdir(config_dir):
                    if tunnel_name in filename:
                        os.remove(os.path.join(config_dir, filename))
            except Exception as e:
                logger.warning(f"No se pudieron eliminar todos los archivos de configuración: {str(e)}")
        
        return {"success": True}
    except Exception as e:
        logger.error(f"Error al eliminar túnel {tunnel_name}: {str(e)}")
        return {"success": False, "error": str(e)}

def configure_tunnel_service(tunnel_name):
    """Configurar un túnel como servicio del sistema"""
    try:
        # Buscar el ID del túnel
        tunnel_id = None
        tunnels = get_tunnels_list()
        for tunnel in tunnels:
            if tunnel["name"] == tunnel_name:
                tunnel_id = tunnel["id"]
                break
        
        if not tunnel_id:
            return {"success": False, "error": f"No se encontró el túnel {tunnel_name}"}
        
        # Verificar si systemd está disponible
        systemd_available = shutil.which('systemctl') is not None
        
        if systemd_available:
            # Crear el archivo de servicio systemd
            service_content = f"""[Unit]
Description=Cloudflare Tunnel for {tunnel_name}
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/cloudflared tunnel run --no-autoupdate {tunnel_name}
Restart=on-failure
RestartSec=5s
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
"""
            
            service_path = f"{SYSTEMD_DIR}/cloudflared-{tunnel_name}.service"
            with open(service_path, "w") as f:
                f.write(service_content)
            
            # Recargar systemd y habilitar el servicio
            subprocess.run(["sudo", "systemctl", "daemon-reload"], check=True)
            subprocess.run(["sudo", "systemctl", "enable", f"cloudflared-{tunnel_name}"], check=True)
            
            return {"success": True, "method": "systemd"}
        else:
            # Si systemd no está disponible, generar un script de inicio
            # que se puede usar manualmente o configurarse con otros servicios
            
            # Crear directorio para scripts si no existe
            script_dir = "/usr/local/bin"
            if not os.path.exists(script_dir):
                os.makedirs(script_dir, exist_ok=True)
            
            # Crear script de inicio
            script_content = f"""#!/bin/bash
# Script para iniciar el túnel CloudFlare {tunnel_name}
# Uso:
#   Para iniciar: {script_dir}/cloudflared-{tunnel_name} start
#   Para detener: {script_dir}/cloudflared-{tunnel_name} stop

TUNNEL_NAME="{tunnel_name}"
TUNNEL_ID="{tunnel_id}"
PID_FILE="/tmp/cloudflared-{tunnel_name}.pid"

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
            
            script_path = f"{script_dir}/cloudflared-{tunnel_name}"
            with open(script_path, "w") as f:
                f.write(script_content)
            
            # Hacer el script ejecutable
            os.chmod(script_path, 0o755)
            
            return {
                "success": True, 
                "method": "script", 
                "script_path": script_path, 
                "instructions": "Systemd no está disponible. Se ha creado un script ejecutable para gestionar manualmente el túnel."
            }
            
    except Exception as e:
        logger.error(f"Error al configurar servicio para túnel {tunnel_name}: {str(e)}")
        return {"success": False, "error": str(e)}

def check_tunnel_connectivity(tunnel_name):
    """Verificar la conectividad del túnel"""
    try:
        if not is_tunnel_running(tunnel_name):
            return False
        
        # Verificar la salida de cloudflared status
        result = subprocess.run(
            ["cloudflared", "tunnel", "info", tunnel_name],
            capture_output=True, text=True
        )
        
        if result.returncode != 0:
            logger.error(f"Error al verificar info del túnel: {result.stderr}")
            return False
        
        # Buscar indicaciones de que está conectado
        if "Active connectors" in result.stdout and "Connection" in result.stdout:
            return True
        
        return False
    except Exception as e:
        logger.error(f"Error al verificar conectividad del túnel {tunnel_name}: {str(e)}")
        return False
