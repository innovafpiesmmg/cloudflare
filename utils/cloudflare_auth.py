import os
import json
import logging
import requests
from pathlib import Path

# Configurar logging
logger = logging.getLogger(__name__)

# Ruta del archivo de configuración
CONFIG_DIR = "/opt/gestor-tuneles-cloudflare/config"
CF_CONFIG_FILE = os.path.join(CONFIG_DIR, "cloudflare.json")


def load_cloudflare_config():
    """Cargar la configuración de Cloudflare"""
    try:
        if os.path.exists(CF_CONFIG_FILE):
            with open(CF_CONFIG_FILE, 'r') as f:
                return json.load(f)
        else:
            logger.warning(f"No se encontró el archivo de configuración: {CF_CONFIG_FILE}")
            return None
    except Exception as e:
        logger.error(f"Error al cargar configuración de Cloudflare: {str(e)}")
        return None


def is_cloudflare_configured():
    """Verificar si las credenciales de Cloudflare están configuradas"""
    config = load_cloudflare_config()
    return config is not None and config.get('configured', False) is True


def get_cloudflare_credentials():
    """Obtener las credenciales de Cloudflare"""
    config = load_cloudflare_config()
    if config:
        return {
            'api_key': config.get('api_key'),
            'email': config.get('email')
        }
    return None


def create_auth_headers():
    """Crear los headers de autenticación para las API de Cloudflare"""
    credentials = get_cloudflare_credentials()
    if not credentials:
        return None
    
    return {
        'X-Auth-Email': credentials['email'],
        'X-Auth-Key': credentials['api_key'],
        'Content-Type': 'application/json'
    }


def test_cloudflare_auth():
    """Probar la autenticación con Cloudflare"""
    headers = create_auth_headers()
    if not headers:
        return False, "No hay credenciales configuradas"
    
    try:
        # Intentar una llamada a la API de Cloudflare
        response = requests.get(
            'https://api.cloudflare.com/client/v4/user',
            headers=headers
        )
        
        if response.status_code == 200:
            return True, "Autenticación exitosa"
        else:
            error_message = response.json().get('errors', [{'message': 'Error desconocido'}])[0].get('message')
            return False, f"Error de autenticación: {error_message}"
    except Exception as e:
        return False, f"Error al conectar con Cloudflare: {str(e)}"


def save_cloudflare_config(api_key, email):
    """Guardar la configuración de Cloudflare"""
    try:
        # Asegurar que el directorio existe
        os.makedirs(CONFIG_DIR, exist_ok=True)
        
        config = {
            'api_key': api_key,
            'email': email,
            'configured': True
        }
        
        with open(CF_CONFIG_FILE, 'w') as f:
            json.dump(config, f, indent=2)
        
        # Asegurar que solo root puede leer este archivo
        os.chmod(CF_CONFIG_FILE, 0o600)
        
        return True, "Configuración guardada correctamente"
    except Exception as e:
        logger.error(f"Error al guardar configuración de Cloudflare: {str(e)}")
        return False, f"Error al guardar configuración: {str(e)}"


def remove_cloudflare_config():
    """Eliminar la configuración de Cloudflare"""
    try:
        if os.path.exists(CF_CONFIG_FILE):
            os.remove(CF_CONFIG_FILE)
            return True, "Configuración eliminada correctamente"
        return False, "No hay configuración para eliminar"
    except Exception as e:
        logger.error(f"Error al eliminar configuración de Cloudflare: {str(e)}")
        return False, f"Error al eliminar configuración: {str(e)}"