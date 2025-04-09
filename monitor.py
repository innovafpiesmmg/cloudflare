#!/usr/bin/env python3
"""
Script de monitoreo para el Gestor de Túneles CloudFlare
Este script verifica el estado de los túneles y notifica problemas
"""

import os
import sys
import time
import json
import logging
import argparse
import smtplib
import subprocess
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime

# Configuración de logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    filename='/var/log/cloudflare-monitor.log'
)

# Variables de configuración
CONFIG_DIR = "/opt/gestor-tuneles-cloudflare/config"
ALERT_RECOVERY_MINUTES = 30  # Tiempo antes de enviar alerta de recuperación
TUNNEL_CHECK_INTERVAL = 300  # Intervalo para verificar túneles (5 min)
KNOWN_ISSUES_FILE = "/tmp/cloudflare_monitor_known_issues.json"

def load_config():
    """Cargar configuración del monitor"""
    config_path = os.path.join(CONFIG_DIR, "monitor_config.json")
    
    if not os.path.exists(config_path):
        logging.warning(f"Archivo de configuración no encontrado: {config_path}")
        return {
            "email_notifications": False,
            "smtp_server": "",
            "smtp_port": 587,
            "smtp_user": "",
            "smtp_password": "",
            "notification_email": "",
            "from_email": "cloudflare-monitor@localhost",
            "check_interval_seconds": TUNNEL_CHECK_INTERVAL,
            "alert_recovery_minutes": ALERT_RECOVERY_MINUTES
        }
    
    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
            return config
    except Exception as e:
        logging.error(f"Error al cargar configuración: {str(e)}")
        return {}

def get_tunnels():
    """Obtener lista de túneles configurados"""
    try:
        cmd = ["cloudflared", "tunnel", "list", "--output", "json"]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)
    except Exception as e:
        logging.error(f"Error al obtener túneles: {str(e)}")
        return []

def check_tunnel_status(tunnel_name):
    """Verificar el estado de un túnel específico"""
    try:
        # Comprobar si el servicio systemd está activo
        cmd_service = ["systemctl", "is-active", f"cloudflared-{tunnel_name}"]
        service_result = subprocess.run(cmd_service, capture_output=True, text=True)
        service_active = service_result.stdout.strip() == "active"
        
        # Verificar conectividad del proceso
        cmd_ps = ["pgrep", "-f", f"cloudflared.*{tunnel_name}"]
        ps_result = subprocess.run(cmd_ps, capture_output=True, text=True)
        process_running = len(ps_result.stdout.strip()) > 0
        
        # Obtener métricas si está activo
        metrics = None
        if process_running:
            try:
                # Intentar obtener métricas usando la API de cloudflared
                cmd_metrics = ["cloudflared", "tunnel", "info", tunnel_name]
                metrics_result = subprocess.run(cmd_metrics, capture_output=True, text=True, timeout=5)
                if metrics_result.returncode == 0:
                    metrics = metrics_result.stdout
            except Exception as e:
                logging.warning(f"No se pudieron obtener métricas para el túnel {tunnel_name}: {str(e)}")
        
        return {
            "tunnel_name": tunnel_name,
            "service_active": service_active,
            "process_running": process_running,
            "metrics": metrics,
            "timestamp": datetime.now().isoformat()
        }
    except Exception as e:
        logging.error(f"Error al verificar el estado del túnel {tunnel_name}: {str(e)}")
        return {
            "tunnel_name": tunnel_name,
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }

def load_known_issues():
    """Cargar problemas conocidos para evitar alertas duplicadas"""
    if not os.path.exists(KNOWN_ISSUES_FILE):
        return {}
    
    try:
        with open(KNOWN_ISSUES_FILE, 'r') as f:
            return json.load(f)
    except Exception as e:
        logging.error(f"Error al cargar problemas conocidos: {str(e)}")
        return {}

def save_known_issues(issues):
    """Guardar problemas conocidos"""
    try:
        with open(KNOWN_ISSUES_FILE, 'w') as f:
            json.dump(issues, f)
    except Exception as e:
        logging.error(f"Error al guardar problemas conocidos: {str(e)}")

def send_email_alert(config, subject, message):
    """Enviar alerta por correo electrónico"""
    if not config.get("email_notifications"):
        logging.info("Notificaciones por correo electrónico desactivadas")
        return False
    
    try:
        msg = MIMEMultipart()
        msg['From'] = config.get("from_email")
        msg['To'] = config.get("notification_email")
        msg['Subject'] = subject
        
        msg.attach(MIMEText(message, 'plain'))
        
        with smtplib.SMTP(config.get("smtp_server"), config.get("smtp_port")) as server:
            server.starttls()
            if config.get("smtp_user") and config.get("smtp_password"):
                server.login(config.get("smtp_user"), config.get("smtp_password"))
            server.send_message(msg)
            
        logging.info(f"Alerta enviada por correo electrónico: {subject}")
        return True
    except Exception as e:
        logging.error(f"Error al enviar alerta por correo electrónico: {str(e)}")
        return False

def monitor_tunnels():
    """Función principal para monitorizar túneles"""
    config = load_config()
    known_issues = load_known_issues()
    current_time = time.time()  # Definir current_time para resolver el problema
    
    # Cargar lista de túneles
    tunnels = get_tunnels()
    if not tunnels:
        logging.warning("No se encontraron túneles para monitorizar")
        return
    
    logging.info(f"Iniciando monitorización de {len(tunnels)} túneles")
    
    # Verificar el estado de cada túnel
    for tunnel in tunnels:
        tunnel_name = tunnel.get("name")
        tunnel_id = tunnel.get("id")
        
        if not tunnel_name:
            continue
        
        status = check_tunnel_status(tunnel_name)
        
        # Determinar si hay problemas
        has_issue = False
        issue_description = ""
        
        if status.get("error"):
            has_issue = True
            issue_description = f"Error al verificar estado: {status.get('error')}"
        elif not status.get("service_active"):
            has_issue = True
            issue_description = "El servicio systemd no está activo"
        elif not status.get("process_running"):
            has_issue = True
            issue_description = "El proceso no está en ejecución"
        
        current_time = time.time()
        
        # Gestionar alertas y recuperaciones
        if has_issue:
            if tunnel_name not in known_issues:
                # Nuevo problema detectado
                known_issues[tunnel_name] = {
                    "first_detected": current_time,
                    "last_notified": current_time,
                    "description": issue_description,
                    "resolved": False
                }
                
                # Enviar alerta
                subject = f"⚠️ ALERTA: Problema en túnel CloudFlare '{tunnel_name}'"
                message = f"""
Se ha detectado un problema en el túnel CloudFlare '{tunnel_name}':

{issue_description}

Fecha y hora: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
ID del túnel: {tunnel_id}

Por favor, revise el estado del túnel en la interfaz web del gestor.
"""
                send_email_alert(config, subject, message)
                logging.warning(f"Problema detectado en túnel '{tunnel_name}': {issue_description}")
        else:
            # Verificar si hay una recuperación
            if tunnel_name in known_issues and known_issues[tunnel_name]["resolved"] == False:
                # Túnel recuperado
                recovery_time = current_time - known_issues[tunnel_name]["first_detected"]
                recovery_minutes = recovery_time / 60
                
                known_issues[tunnel_name]["resolved"] = True
                known_issues[tunnel_name]["resolved_at"] = current_time
                
                # Enviar alerta de recuperación
                subject = f"✅ RECUPERADO: Túnel CloudFlare '{tunnel_name}'"
                message = f"""
El túnel CloudFlare '{tunnel_name}' se ha recuperado:

Problema anterior: {known_issues[tunnel_name]["description"]}
Duración del problema: {int(recovery_minutes)} minutos
Fecha y hora de recuperación: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

No se requiere acción adicional.
"""
                send_email_alert(config, subject, message)
                logging.info(f"Túnel '{tunnel_name}' recuperado después de {int(recovery_minutes)} minutos")
    
    # Limpiar problemas muy antiguos ya resueltos
    clean_time = current_time - (config.get("alert_recovery_minutes", ALERT_RECOVERY_MINUTES) * 60 * 2)
    tunnels_to_remove = []
    
    for tunnel_name, issue in known_issues.items():
        if issue["resolved"] and issue.get("resolved_at", 0) < clean_time:
            tunnels_to_remove.append(tunnel_name)
    
    for tunnel_name in tunnels_to_remove:
        del known_issues[tunnel_name]
    
    # Guardar estado actual de problemas conocidos
    save_known_issues(known_issues)
    
    logging.info("Monitorización de túneles completada")

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