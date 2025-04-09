import os
import json
import yaml
import logging
import subprocess
from pathlib import Path

# Configurar logging
logger = logging.getLogger(__name__)

# Rutas de archivos de configuración
CLOUDFLARED_CONFIG_DIR = "/etc/cloudflared"
CONFIG_DIR = os.path.join(CLOUDFLARED_CONFIG_DIR, "configs")

def ensure_config_dirs():
    """Asegurar que existen los directorios de configuración"""
    try:
        os.makedirs(CLOUDFLARED_CONFIG_DIR, exist_ok=True)
        os.makedirs(CONFIG_DIR, exist_ok=True)
        return True
    except Exception as e:
        logger.error(f"Error al crear directorios de configuración: {str(e)}")
        return False

def read_tunnel_config(tunnel_name):
    """
    Leer la configuración de un túnel
    Retorna un diccionario con la configuración o None si hay error
    """
    ensure_config_dirs()
    config_path = os.path.join(CONFIG_DIR, f"{tunnel_name}.json")
    
    try:
        if os.path.exists(config_path):
            with open(config_path, 'r') as f:
                return json.load(f)
        else:
            # Intentar buscar el archivo de configuración del túnel
            # que puede estar en la raíz del directorio de configuración
            tunnel_files = [f for f in os.listdir(CLOUDFLARED_CONFIG_DIR) 
                          if f.endswith('.json') and not f.startswith('cert')]
            
            for file in tunnel_files:
                try:
                    with open(os.path.join(CLOUDFLARED_CONFIG_DIR, file), 'r') as f:
                        data = json.load(f)
                        if 'TunnelID' in data:
                            # Verificar si es este túnel
                            result = subprocess.run(
                                ["cloudflared", "tunnel", "info", tunnel_name, "--output", "json"],
                                capture_output=True, text=True
                            )
                            if result.returncode == 0:
                                tunnel_info = json.loads(result.stdout)
                                if 'id' in tunnel_info and tunnel_info['id'] == data['TunnelID']:
                                    # Es este túnel, copiar la configuración
                                    config = {
                                        'tunnel_id': data['TunnelID'],
                                        'credentials_file': os.path.join(CLOUDFLARED_CONFIG_DIR, file),
                                        'services': []
                                    }
                                    save_tunnel_config(tunnel_name, config)
                                    return config
                except Exception as e:
                    logger.error(f"Error al leer archivo de configuración {file}: {str(e)}")
                    continue
            
            # No se encontró configuración
            return None
    except Exception as e:
        logger.error(f"Error al leer configuración del túnel {tunnel_name}: {str(e)}")
        return None

def save_tunnel_config(tunnel_name, config):
    """
    Guardar la configuración de un túnel
    Retorna True si se guardó correctamente, False en caso contrario
    """
    ensure_config_dirs()
    config_path = os.path.join(CONFIG_DIR, f"{tunnel_name}.json")
    
    try:
        with open(config_path, 'w') as f:
            json.dump(config, f, indent=2)
            
        # Verificar si necesitamos generar un archivo config.yml para el túnel
        if 'services' in config and config['services']:
            generate_tunnel_config_yaml(tunnel_name, config)
            
        return True
    except Exception as e:
        logger.error(f"Error al guardar configuración del túnel {tunnel_name}: {str(e)}")
        return False

def generate_tunnel_config_yaml(tunnel_name, config):
    """
    Generar el archivo config.yml para un túnel basado en su configuración
    """
    try:
        yaml_config = {
            'tunnel': tunnel_name,
            'credentials-file': config.get('credentials_file', ''),
            'ingress': []
        }
        
        # Añadir servicios
        for service in config['services']:
            ingress_rule = {
                'hostname': service['domain'],
                'service': f"http://localhost:{service['port']}"
            }
            yaml_config['ingress'].append(ingress_rule)
        
        # Añadir regla catch-all al final
        yaml_config['ingress'].append({
            'service': 'http_status:404'
        })
        
        # Guardar el archivo YAML
        yaml_path = os.path.join(CLOUDFLARED_CONFIG_DIR, f"{tunnel_name}.yml")
        with open(yaml_path, 'w') as f:
            yaml.dump(yaml_config, f, default_flow_style=False)
            
        return True
    except Exception as e:
        logger.error(f"Error al generar config.yml para túnel {tunnel_name}: {str(e)}")
        return False

def get_available_services():
    """
    Detectar servicios disponibles en el sistema
    Retorna una lista de servicios con su información
    """
    services = []
    
    # Servicios comunes y sus puertos por defecto
    common_services = [
        {"name": "HTTP", "port": 80, "running": False},
        {"name": "HTTPS", "port": 443, "running": False},
        {"name": "SSH", "port": 22, "running": False},
        {"name": "FTP", "port": 21, "running": False},
        {"name": "MySQL", "port": 3306, "running": False},
        {"name": "PostgreSQL", "port": 5432, "running": False},
        {"name": "Redis", "port": 6379, "running": False},
        {"name": "MongoDB", "port": 27017, "running": False},
        {"name": "SMTP", "port": 25, "running": False},
        {"name": "POP3", "port": 110, "running": False},
        {"name": "IMAP", "port": 143, "running": False}
    ]
    
    try:
        # Verificar qué servicios están escuchando en los puertos
        netstat_result = subprocess.run(
            ["ss", "-tulpn"],
            capture_output=True,
            text=True
        )
        
        if netstat_result.returncode == 0:
            output = netstat_result.stdout
            
            # Verificar cada servicio
            for service in common_services:
                # Buscar puerto en el output de netstat
                port_str = f":{service['port']}"
                service["running"] = port_str in output
                services.append(service)
                
        # Detectar servicios específicos mediante systemctl
        systemctl_services = {
            "nginx": {"name": "Nginx", "port": 80},
            "apache2": {"name": "Apache", "port": 80},
            "mysql": {"name": "MySQL", "port": 3306},
            "postgresql": {"name": "PostgreSQL", "port": 5432},
            "redis-server": {"name": "Redis", "port": 6379},
            "mongodb": {"name": "MongoDB", "port": 27017},
            "sshd": {"name": "SSH", "port": 22},
            "vsftpd": {"name": "FTP", "port": 21},
            "postfix": {"name": "SMTP", "port": 25}
        }
        
        for service_name, service_info in systemctl_services.items():
            result = subprocess.run(
                ["systemctl", "is-active", service_name],
                capture_output=True,
                text=True
            )
            
            if result.stdout.strip() == "active":
                # Evitar duplicados
                if not any(s["name"] == service_info["name"] for s in services):
                    services.append({
                        "name": service_info["name"],
                        "port": service_info["port"],
                        "running": True
                    })
                # Actualizar estado si ya existe
                else:
                    for i, s in enumerate(services):
                        if s["name"] == service_info["name"]:
                            services[i]["running"] = True
                            
        return services
    except Exception as e:
        logger.error(f"Error al detectar servicios disponibles: {str(e)}")
        return common_services

def add_service_to_tunnel(tunnel_name, service_name, service_port, domain):
    """
    Añadir un servicio a un túnel
    Retorna un diccionario con el resultado de la operación
    """
    try:
        # Cargar configuración actual
        config = read_tunnel_config(tunnel_name)
        if not config:
            return {"success": False, "error": f"No se encontró configuración para el túnel {tunnel_name}"}
        
        # Verificar si el servicio ya existe
        if 'services' in config:
            for service in config['services']:
                if service['name'] == service_name:
                    return {"success": False, "error": f"Ya existe un servicio con nombre {service_name} en este túnel"}
                if service['domain'] == domain:
                    return {"success": False, "error": f"Ya existe un servicio usando el dominio {domain} en este túnel"}
        else:
            config['services'] = []
        
        # Añadir el servicio
        service = {
            "name": service_name,
            "port": service_port,
            "domain": domain
        }
        
        config['services'].append(service)
        
        # Guardar la configuración actualizada
        if save_tunnel_config(tunnel_name, config):
            # Regenerar la configuración YAML
            generate_tunnel_config_yaml(tunnel_name, config)
            
            # Reiniciar el servicio si está configurado
            service_name = f"cloudflared-{tunnel_name}"
            restart_result = subprocess.run(
                ["systemctl", "is-active", service_name],
                capture_output=True,
                text=True
            )
            
            if restart_result.stdout.strip() == "active":
                subprocess.run(
                    ["sudo", "systemctl", "restart", service_name],
                    capture_output=True,
                    text=True
                )
            
            return {"success": True}
        else:
            return {"success": False, "error": "Error al guardar la configuración"}
    except Exception as e:
        logger.error(f"Error al añadir servicio al túnel {tunnel_name}: {str(e)}")
        return {"success": False, "error": str(e)}

def remove_service_from_tunnel(tunnel_name, service_name):
    """
    Eliminar un servicio de un túnel
    Retorna un diccionario con el resultado de la operación
    """
    try:
        # Cargar configuración actual
        config = read_tunnel_config(tunnel_name)
        if not config:
            return {"success": False, "error": f"No se encontró configuración para el túnel {tunnel_name}"}
        
        # Verificar si el servicio existe
        if 'services' not in config or not config['services']:
            return {"success": False, "error": f"No hay servicios configurados en el túnel {tunnel_name}"}
        
        # Buscar y eliminar el servicio
        service_found = False
        for i, service in enumerate(config['services']):
            if service['name'] == service_name:
                del config['services'][i]
                service_found = True
                break
        
        if not service_found:
            return {"success": False, "error": f"No se encontró el servicio {service_name} en el túnel {tunnel_name}"}
        
        # Guardar la configuración actualizada
        if save_tunnel_config(tunnel_name, config):
            # Regenerar la configuración YAML
            generate_tunnel_config_yaml(tunnel_name, config)
            
            # Reiniciar el servicio si está configurado
            service_name = f"cloudflared-{tunnel_name}"
            restart_result = subprocess.run(
                ["systemctl", "is-active", service_name],
                capture_output=True,
                text=True
            )
            
            if restart_result.stdout.strip() == "active":
                subprocess.run(
                    ["sudo", "systemctl", "restart", service_name],
                    capture_output=True,
                    text=True
                )
            
            return {"success": True}
        else:
            return {"success": False, "error": "Error al guardar la configuración"}
    except Exception as e:
        logger.error(f"Error al eliminar servicio del túnel {tunnel_name}: {str(e)}")
        return {"success": False, "error": str(e)}
