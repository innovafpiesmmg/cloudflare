import os
import subprocess
import logging
import platform
import psutil
import shutil

# Configurar logging
logger = logging.getLogger(__name__)

def check_dependencies():
    """
    Verificar si las dependencias necesarias están instaladas
    Retorna una lista de dependencias con su estado
    """
    dependencies = [
        {"name": "curl", "installed": False},
        {"name": "sudo", "installed": False},
        {"name": "python3", "installed": False},
        {"name": "systemd", "installed": False, "optional": True}
    ]
    
    try:
        # Verificar cada dependencia básica
        for i, dep in enumerate(dependencies):
            if dep["name"] != "systemd":  # Systemd requiere verificación específica
                result = subprocess.run(["which", dep["name"]], capture_output=True, text=True)
                dependencies[i]["installed"] = result.returncode == 0
        
        # Verificar systemd de forma específica (es un servicio, no un comando)
        try:
            systemd_check = subprocess.run(
                ["systemctl", "--version"], 
                capture_output=True, 
                text=True
            )
            for i, dep in enumerate(dependencies):
                if dep["name"] == "systemd":
                    dependencies[i]["installed"] = systemd_check.returncode == 0
        except FileNotFoundError:
            # Si systemctl no existe, systemd no está disponible pero es opcional
            logger.warning("systemd no está disponible en este sistema")
            for i, dep in enumerate(dependencies):
                if dep["name"] == "systemd":
                    dependencies[i]["installed"] = False
                    dependencies[i]["mensaje"] = "No disponible en este sistema (opcional)"
        
        return dependencies
    except Exception as e:
        logger.error(f"Error al verificar dependencias: {str(e)}")
        return dependencies

def install_dependencies():
    """
    Instalar las dependencias necesarias
    Retorna True si todas las dependencias se instalaron correctamente
    """
    try:
        # Verificar qué dependencias necesitan ser instaladas
        deps = check_dependencies()
        deps_to_install = [dep["name"] for dep in deps if not dep["installed"] and dep["name"] != "systemd"]
        
        if not deps_to_install:
            logger.info("Todas las dependencias ya están instaladas.")
            return True
            
        # Actualizar índices de paquetes
        logger.info("Actualizando índices de paquetes...")
        update_result = subprocess.run(
            ["sudo", "apt-get", "update", "-y"],
            capture_output=True,
            text=True
        )
        
        if update_result.returncode != 0:
            logger.error(f"Error al actualizar índices: {update_result.stderr}")
            return False
            
        # Instalar cada dependencia
        for dep in deps_to_install:
            logger.info(f"Instalando {dep}...")
            install_result = subprocess.run(
                ["sudo", "apt-get", "install", "-y", dep],
                capture_output=True,
                text=True
            )
            
            if install_result.returncode != 0:
                logger.error(f"Error al instalar {dep}: {install_result.stderr}")
                return False
                
        return True
    except Exception as e:
        logger.error(f"Error al instalar dependencias: {str(e)}")
        return False

def get_system_info():
    """
    Obtener información del sistema operativo
    Retorna un diccionario con información del sistema
    """
    info = {
        "os": "Desconocido",
        "hostname": "Desconocido",
        "ip": "Desconocido",
        "ram": "Desconocido",
        "disk": "Desconocido"
    }
    
    try:
        # Sistema operativo
        info["os"] = f"{platform.system()} {platform.release()}"
        
        # Hostname
        info["hostname"] = platform.node()
        
        # IP local (primera interfaz no lo de loopback)
        ip_command = subprocess.run(
            ["hostname", "-I"], 
            capture_output=True, 
            text=True
        )
        if ip_command.returncode == 0:
            ips = ip_command.stdout.strip().split()
            if ips:
                info["ip"] = ips[0]
        
        # Memoria RAM
        ram = psutil.virtual_memory()
        ram_total_gb = ram.total / (1024**3)
        ram_used_gb = ram.used / (1024**3)
        info["ram"] = f"{ram_used_gb:.1f} GB / {ram_total_gb:.1f} GB ({ram.percent}%)"
        
        # Espacio en disco
        disk = psutil.disk_usage('/')
        disk_total_gb = disk.total / (1024**3)
        disk_used_gb = disk.used / (1024**3)
        info["disk"] = f"{disk_used_gb:.1f} GB / {disk_total_gb:.1f} GB ({disk.percent}%)"
        
        return info
    except Exception as e:
        logger.error(f"Error al obtener información del sistema: {str(e)}")
        return info

def check_service_status(service_name):
    """
    Verificar el estado de un servicio systemd
    Retorna un diccionario con información del estado del servicio
    """
    status = {
        "exists": False,
        "active": False,
        "enabled": False,
        "status": "Desconocido",
        "systemd_available": True
    }
    
    # Verificar si systemd está disponible
    try:
        # Comprobar si systemctl existe
        systemctl_exists = shutil.which('systemctl') is not None
        
        if not systemctl_exists:
            status["systemd_available"] = False
            status["status"] = "Systemd no disponible"
            logger.warning(f"No se puede verificar el servicio {service_name}: systemd no está disponible")
            return status
    
        # Verificar si el servicio existe
        status_result = subprocess.run(
            ["systemctl", "status", service_name],
            capture_output=True,
            text=True
        )
        status["exists"] = status_result.returncode != 4  # 4 significa que el servicio no existe
        
        if not status["exists"]:
            status["status"] = "No existe"
            return status
            
        # Verificar si está activo
        active_result = subprocess.run(
            ["systemctl", "is-active", service_name],
            capture_output=True,
            text=True
        )
        status["active"] = active_result.stdout.strip() == "active"
        
        # Verificar si está habilitado para iniciar con el sistema
        enabled_result = subprocess.run(
            ["systemctl", "is-enabled", service_name],
            capture_output=True,
            text=True
        )
        status["enabled"] = enabled_result.stdout.strip() == "enabled"
        
        # Obtener el estado detallado
        if status["active"]:
            status["status"] = "Activo"
        else:
            status["status"] = "Inactivo"
            
        return status
    except FileNotFoundError:
        # Si systemctl no está disponible
        status["systemd_available"] = False
        status["status"] = "Systemd no disponible"
        logger.warning(f"No se puede verificar el servicio {service_name}: systemd no está disponible")
        return status
    except Exception as e:
        logger.error(f"Error al verificar estado del servicio {service_name}: {str(e)}")
        return status
