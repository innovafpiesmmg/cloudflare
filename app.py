import os
import sys
import logging
import secrets
import time
from datetime import datetime
from functools import wraps
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, session, Response
from werkzeug.middleware.proxy_fix import ProxyFix
from utils.cloudflare import (
    check_cloudflared_installed, 
    install_cloudflared, 
    get_cloudflared_version,
    get_tunnel_status,
    create_tunnel,
    get_tunnels_list,
    start_tunnel,
    stop_tunnel,
    delete_tunnel,
    configure_tunnel_service
)
from utils.sistema import (
    check_dependencies, 
    install_dependencies, 
    get_system_info,
    check_service_status
)
from utils.configuracion import (
    read_tunnel_config,
    save_tunnel_config,
    get_available_services,
    add_service_to_tunnel,
    remove_service_from_tunnel
)
from utils.monitorizacion import (
    get_tunnel_metrics,
    check_tunnel_connectivity
)

# Configuración del logging para producción
log_level = logging.INFO if os.environ.get('FLASK_ENV') == 'production' else logging.DEBUG
logging.basicConfig(
    level=log_level,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

# Inicializar la aplicación Flask
app = Flask(__name__)

# Generar una clave secreta fuerte si no existe en el entorno
app.secret_key = os.environ.get("SESSION_SECRET", secrets.token_hex(32))

# Configurar la aplicación para entornos de producción detrás de proxies
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1, x_port=1, x_prefix=1)

# Configuración de seguridad para producción
if os.environ.get('FLASK_ENV') == 'production':
    # Configurar sesiones seguras en producción
    app.config['SESSION_COOKIE_SECURE'] = True
    app.config['SESSION_COOKIE_HTTPONLY'] = True
    app.config['SESSION_COOKIE_SAMESITE'] = 'Lax'
    app.config['PERMANENT_SESSION_LIFETIME'] = 3600  # 1 hora
    
    # Desactivar modo debug en producción
    app.config['DEBUG'] = False
    
    # Otras configuraciones de producción
    app.config['PREFERRED_URL_SCHEME'] = 'https'
    
# Configurar encabezados de seguridad
@app.after_request
def add_security_headers(response):
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'SAMEORIGIN'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
    return response

# Ruta principal
@app.route('/')
def index():
    # Obtener información del sistema
    system_info = get_system_info()
    
    # Verificar si cloudflared está instalado
    cloudflared_installed = check_cloudflared_installed()
    cloudflared_version = get_cloudflared_version() if cloudflared_installed else None
    
    # Obtener información de túneles si cloudflared está instalado
    tunnels = []
    if cloudflared_installed:
        try:
            tunnels = get_tunnels_list()
        except Exception as e:
            app.logger.error(f"Error al obtener túneles: {str(e)}")
    
    return render_template(
        'index.html', 
        system_info=system_info,
        cloudflared_installed=cloudflared_installed,
        cloudflared_version=cloudflared_version,
        tunnels=tunnels
    )

# Ruta para la instalación
@app.route('/instalacion')
def instalacion():
    # Obtener la información de dependencias
    deps = check_dependencies()
    cloudflared_installed = check_cloudflared_installed()
    cloudflared_version = get_cloudflared_version() if cloudflared_installed else None
    
    return render_template(
        'instalacion.html',
        dependencies=deps,
        cloudflared_installed=cloudflared_installed,
        cloudflared_version=cloudflared_version
    )

# Ruta para instalar cloudflared
@app.route('/instalar-cloudflared', methods=['POST'])
def instalar_cloudflared():
    try:
        # Crear sesión para seguimiento de estado de instalación
        session['instalacion_estado'] = 'iniciada'
        session['instalacion_tiempo'] = time.time()
        
        # Instalar dependencias primero
        app.logger.info("Iniciando instalación de dependencias...")
        install_result_deps = install_dependencies()
        
        if not install_result_deps:
            flash('Error al instalar dependencias necesarias. Revisar logs del sistema.', 'danger')
            session['instalacion_estado'] = 'error_dependencias'
            return redirect(url_for('instalacion'))
        
        # Instalar cloudflared con timeout
        app.logger.info("Iniciando instalación de CloudFlared...")
        session['instalacion_estado'] = 'cloudflared'
        
        # La instalación puede tardar, crear un thread para no bloquear la respuesta
        import threading
        from queue import Queue
        
        result_queue = Queue()
        def install_thread():
            try:
                result = install_cloudflared()
                result_queue.put(result)
            except Exception as e:
                app.logger.error(f"Error en thread de instalación: {str(e)}")
                result_queue.put(False)
        
        # Iniciar thread de instalación
        install_thread = threading.Thread(target=install_thread)
        install_thread.daemon = True
        install_thread.start()
        
        # Esperar resultado con timeout (10 segundos para la respuesta web)
        try:
            # Esperar brevemente para dar tiempo a que comience la instalación
            # pero no demasiado para evitar que se bloquee la interfaz
            install_thread.join(timeout=2.0)
            
            # Establecer mensaje para la interfaz
            flash('La instalación de CloudFlared está en progreso. Por favor, espere unos minutos y refresque la página.', 'info')
            flash('Si la instalación tarda más de 5 minutos, verifique los logs del sistema.', 'warning')
            
            # Guardar en sesión para mostrar progreso
            session['instalacion_estado'] = 'en_progreso'
            
            return redirect(url_for('instalacion'))
        except Exception as e:
            flash(f'La instalación continúa en segundo plano: {str(e)}', 'warning')
            return redirect(url_for('instalacion'))
        
    except Exception as e:
        flash(f'Error durante la instalación: {str(e)}', 'danger')
        app.logger.error(f"Error durante la instalación: {str(e)}")
        session['instalacion_estado'] = 'error'
        return redirect(url_for('instalacion'))

# Ruta para verificar estado de instalación
@app.route('/estado-instalacion', methods=['GET'])
def estado_instalacion():
    # Verificar si cloudflared está instalado
    cloudflared_installed = check_cloudflared_installed()
    
    if cloudflared_installed:
        version = get_cloudflared_version()
        session.pop('instalacion_estado', None)
        session.pop('instalacion_tiempo', None)
        return jsonify({
            'estado': 'completado',
            'instalado': True,
            'version': version
        })
    
    # Verificar si hay una instalación en curso
    estado = session.get('instalacion_estado', 'desconocido')
    tiempo_inicio = session.get('instalacion_tiempo', 0)
    tiempo_transcurrido = time.time() - tiempo_inicio if tiempo_inicio else 0
    
    # Si ha pasado demasiado tiempo (más de 10 minutos), considerar error
    if tiempo_inicio and tiempo_transcurrido > 600:
        session['instalacion_estado'] = 'timeout'
        estado = 'timeout'
    
    return jsonify({
        'estado': estado,
        'instalado': cloudflared_installed,
        'tiempo_transcurrido': round(tiempo_transcurrido) if tiempo_inicio else 0
    })

# Ruta para la configuración de túneles
@app.route('/configuracion')
def configuracion():
    # Verificar si cloudflared está instalado
    cloudflared_installed = check_cloudflared_installed()
    
    if not cloudflared_installed:
        flash('Primero debe instalar CloudFlared para acceder a la configuración.', 'warning')
        return redirect(url_for('instalacion'))
    
    # Obtener la lista de túneles
    tunnels = []
    try:
        tunnels = get_tunnels_list()
    except Exception as e:
        flash(f'Error al obtener la lista de túneles: {str(e)}', 'danger')
    
    return render_template('configuracion.html', tunnels=tunnels)

# Ruta para crear un nuevo túnel
@app.route('/crear-tunel', methods=['POST'])
def crear_tunel():
    nombre_tunel = request.form.get('nombre_tunel')
    
    if not nombre_tunel:
        flash('El nombre del túnel es obligatorio.', 'danger')
        return redirect(url_for('configuracion'))
    
    try:
        resultado = create_tunnel(nombre_tunel)
        if resultado['success']:
            flash(f'Túnel "{nombre_tunel}" creado exitosamente. ID: {resultado["tunnel_id"]}', 'success')
            # Guardar el token para uso futuro (configuración de servicios)
            config = {
                'tunnel_id': resultado['tunnel_id'],
                'token': resultado['token'],
                'services': []
            }
            save_tunnel_config(nombre_tunel, config)
        else:
            flash(f'Error al crear el túnel: {resultado["error"]}', 'danger')
    except Exception as e:
        flash(f'Error al crear el túnel: {str(e)}', 'danger')
        app.logger.error(f"Error al crear el túnel: {str(e)}")
    
    return redirect(url_for('configuracion'))

# Ruta para iniciar un túnel
@app.route('/iniciar-tunel/<nombre_tunel>', methods=['POST'])
def iniciar_tunel(nombre_tunel):
    try:
        resultado = start_tunnel(nombre_tunel)
        if resultado['success']:
            flash(f'Túnel "{nombre_tunel}" iniciado correctamente.', 'success')
        else:
            flash(f'Error al iniciar el túnel: {resultado["error"]}', 'danger')
    except Exception as e:
        flash(f'Error al iniciar el túnel: {str(e)}', 'danger')
        app.logger.error(f"Error al iniciar el túnel: {str(e)}")
    
    return redirect(url_for('configuracion'))

# Ruta para detener un túnel
@app.route('/detener-tunel/<nombre_tunel>', methods=['POST'])
def detener_tunel(nombre_tunel):
    try:
        resultado = stop_tunnel(nombre_tunel)
        if resultado['success']:
            flash(f'Túnel "{nombre_tunel}" detenido correctamente.', 'success')
        else:
            flash(f'Error al detener el túnel: {resultado["error"]}', 'danger')
    except Exception as e:
        flash(f'Error al detener el túnel: {str(e)}', 'danger')
        app.logger.error(f"Error al detener el túnel: {str(e)}")
    
    return redirect(url_for('configuracion'))

# Ruta para eliminar un túnel
@app.route('/eliminar-tunel/<nombre_tunel>', methods=['POST'])
def eliminar_tunel(nombre_tunel):
    try:
        resultado = delete_tunnel(nombre_tunel)
        if resultado['success']:
            flash(f'Túnel "{nombre_tunel}" eliminado correctamente.', 'success')
        else:
            flash(f'Error al eliminar el túnel: {resultado["error"]}', 'danger')
    except Exception as e:
        flash(f'Error al eliminar el túnel: {str(e)}', 'danger')
        app.logger.error(f"Error al eliminar el túnel: {str(e)}")
    
    return redirect(url_for('configuracion'))

# Ruta para configurar un túnel como servicio
@app.route('/configurar-servicio-tunel/<nombre_tunel>', methods=['POST'])
def configurar_servicio_tunel(nombre_tunel):
    try:
        resultado = configure_tunnel_service(nombre_tunel)
        if resultado['success']:
            flash(f'Túnel "{nombre_tunel}" configurado como servicio correctamente.', 'success')
        else:
            flash(f'Error al configurar el túnel como servicio: {resultado["error"]}', 'danger')
    except Exception as e:
        flash(f'Error al configurar el túnel como servicio: {str(e)}', 'danger')
        app.logger.error(f"Error al configurar el túnel como servicio: {str(e)}")
    
    return redirect(url_for('configuracion'))

# Ruta para gestionar servicios
@app.route('/servicios')
def servicios():
    # Verificar si cloudflared está instalado
    cloudflared_installed = check_cloudflared_installed()
    
    if not cloudflared_installed:
        flash('Primero debe instalar CloudFlared para acceder a la gestión de servicios.', 'warning')
        return redirect(url_for('instalacion'))
    
    # Obtener la lista de túneles
    tunnels = []
    try:
        tunnels = get_tunnels_list()
    except Exception as e:
        flash(f'Error al obtener la lista de túneles: {str(e)}', 'danger')
    
    # Obtener servicios disponibles en el sistema
    available_services = get_available_services()
    
    return render_template('servicios.html', tunnels=tunnels, available_services=available_services)

# Ruta para añadir un servicio a un túnel
@app.route('/anadir-servicio', methods=['POST'])
def anadir_servicio():
    tunnel_name = request.form.get('tunnel_name')
    service_name = request.form.get('service_name')
    service_port = request.form.get('service_port')
    domain = request.form.get('domain')
    
    if not all([tunnel_name, service_name, service_port, domain]):
        flash('Todos los campos son obligatorios.', 'danger')
        return redirect(url_for('servicios'))
    
    try:
        resultado = add_service_to_tunnel(tunnel_name, service_name, service_port, domain)
        if resultado['success']:
            flash(f'Servicio "{service_name}" añadido correctamente al túnel "{tunnel_name}".', 'success')
        else:
            flash(f'Error al añadir el servicio: {resultado["error"]}', 'danger')
    except Exception as e:
        flash(f'Error al añadir el servicio: {str(e)}', 'danger')
        app.logger.error(f"Error al añadir el servicio: {str(e)}")
    
    return redirect(url_for('servicios'))

# Ruta para eliminar un servicio de un túnel
@app.route('/eliminar-servicio', methods=['POST'])
def eliminar_servicio():
    tunnel_name = request.form.get('tunnel_name')
    service_name = request.form.get('service_name')
    
    if not all([tunnel_name, service_name]):
        flash('Todos los campos son obligatorios.', 'danger')
        return redirect(url_for('servicios'))
    
    try:
        resultado = remove_service_from_tunnel(tunnel_name, service_name)
        if resultado['success']:
            flash(f'Servicio "{service_name}" eliminado correctamente del túnel "{tunnel_name}".', 'success')
        else:
            flash(f'Error al eliminar el servicio: {resultado["error"]}', 'danger')
    except Exception as e:
        flash(f'Error al eliminar el servicio: {str(e)}', 'danger')
        app.logger.error(f"Error al eliminar el servicio: {str(e)}")
    
    return redirect(url_for('servicios'))

# Ruta para monitorizar el estado
@app.route('/estado')
def estado():
    # Verificar si cloudflared está instalado
    cloudflared_installed = check_cloudflared_installed()
    
    if not cloudflared_installed:
        flash('Primero debe instalar CloudFlared para acceder al estado.', 'warning')
        return redirect(url_for('instalacion'))
    
    # Obtener la lista de túneles
    tunnels = []
    tunnel_statuses = {}
    tunnel_metrics = {}
    
    try:
        tunnels = get_tunnels_list()
        
        # Obtener el estado de cada túnel
        for tunnel in tunnels:
            status = get_tunnel_status(tunnel['name'])
            tunnel_statuses[tunnel['name']] = status
            
            # Obtener métricas si el túnel está activo
            if status['running']:
                metrics = get_tunnel_metrics(tunnel['name'])
                tunnel_metrics[tunnel['name']] = metrics
            else:
                tunnel_metrics[tunnel['name']] = None
                
    except Exception as e:
        flash(f'Error al obtener información de los túneles: {str(e)}', 'danger')
        app.logger.error(f"Error al obtener información de los túneles: {str(e)}")
    
    return render_template(
        'estado.html', 
        tunnels=tunnels, 
        tunnel_statuses=tunnel_statuses,
        tunnel_metrics=tunnel_metrics
    )

# Ruta para refrescar el estado de un túnel
@app.route('/api/estado-tunel/<nombre_tunel>')
def api_estado_tunel(nombre_tunel):
    try:
        status = get_tunnel_status(nombre_tunel)
        metrics = get_tunnel_metrics(nombre_tunel) if status['running'] else None
        connectivity = check_tunnel_connectivity(nombre_tunel) if status['running'] else False
        
        return jsonify({
            'success': True,
            'status': status,
            'metrics': metrics,
            'connectivity': connectivity
        })
    except Exception as e:
        app.logger.error(f"Error al obtener estado del túnel: {str(e)}")
        return jsonify({
            'success': False,
            'error': str(e)
        })

# Decorator para limitar el acceso por IP
def restrict_access_by_ip(allowed_networks=['127.0.0.1/8', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16']):
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            # Implementación básica para comprobar si la IP está en una red permitida
            client_ip = request.remote_addr
            
            # Para producción utilizar una biblioteca como 'ipaddress' para verificar correctamente
            # Esta es una implementación simple
            is_allowed = any(client_ip.startswith(net.split('/')[0]) for net in allowed_networks)
            
            if not is_allowed and os.environ.get('FLASK_ENV') == 'production':
                app.logger.warning(f"Intento de acceso no autorizado a ruta protegida desde IP: {client_ip}")
                return Response("Acceso no autorizado", status=403)
            
            return f(*args, **kwargs)
        return decorated_function
    return decorator

# Ruta de estado de salud para monitoreo
@app.route('/health')
def health_check():
    # Verificar componentes críticos
    try:
        # Verificar que podemos acceder al sistema de archivos
        os.access('.', os.R_OK)
        
        # Verificar si podemos ejecutar comandos de sistema (básico)
        import subprocess
        subprocess.run(["echo", "test"], capture_output=True, check=True)
        
        # Comprobar espacio en disco
        disk_usage = os.statvfs('.')
        free_space_gb = (disk_usage.f_bavail * disk_usage.f_frsize) / (1024**3)
        
        # Si tenemos menos de 100MB de espacio libre, mostrar advertencia
        disk_status = "ok" if free_space_gb > 0.1 else "low"
        
        # Verificar tiempo de actividad
        uptime = time.time() - os.path.getmtime('/proc/1/cmdline')
        
        # Información de versión
        version_info = {
            "app_version": "1.0.0",
            "python_version": os.environ.get('PYTHON_VERSION', '.'.join(map(str, tuple(sys.version_info)[:3]))),
            "cloudflared_version": get_cloudflared_version() if check_cloudflared_installed() else "No instalado"
        }
        
        return jsonify({
            "status": "ok",
            "timestamp": datetime.now().isoformat(),
            "uptime_seconds": uptime,
            "disk_space": {
                "free_gb": round(free_space_gb, 2),
                "status": disk_status
            },
            "components": {
                "filesystem": "ok",
                "system": "ok"
            },
            "version": version_info
        })
    except Exception as e:
        app.logger.error(f"Error en health check: {str(e)}")
        return jsonify({
            "status": "error",
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }), 500

# Ruta protegida para estadísticas detalladas del sistema
@app.route('/system-stats')
@restrict_access_by_ip()
def system_stats():
    try:
        import psutil
        
        # Información del sistema
        cpu_usage = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory()
        disk = psutil.disk_usage('/')
        
        # Procesos relacionados con CloudFlare
        cloudflare_processes = []
        for proc in psutil.process_iter(['pid', 'name', 'cmdline', 'cpu_percent', 'memory_percent']):
            try:
                if 'cloudflared' in proc.info['name'] or \
                   any('cloudflared' in cmd for cmd in proc.info['cmdline'] if cmd):
                    cloudflare_processes.append({
                        'pid': proc.info['pid'],
                        'cpu_percent': proc.info['cpu_percent'],
                        'memory_percent': proc.info['memory_percent'],
                        'cmdline': ' '.join(proc.info['cmdline']) if proc.info['cmdline'] else ''
                    })
            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                pass
        
        # Información de túneles
        tunnels = get_tunnels_list() if check_cloudflared_installed() else []
        
        return jsonify({
            'system': {
                'cpu_percent': cpu_usage,
                'memory': {
                    'total_gb': round(memory.total / (1024**3), 2),
                    'used_gb': round(memory.used / (1024**3), 2),
                    'percent': memory.percent
                },
                'disk': {
                    'total_gb': round(disk.total / (1024**3), 2),
                    'used_gb': round(disk.used / (1024**3), 2),
                    'percent': disk.percent
                }
            },
            'cloudflared_processes': cloudflare_processes,
            'tunnels_count': len(tunnels)
        })
    except Exception as e:
        app.logger.error(f"Error al generar estadísticas del sistema: {str(e)}")
        return jsonify({
            'status': 'error',
            'error': str(e)
        }), 500

# Ruta para la página de ayuda
@app.route('/ayuda')
def ayuda():
    return render_template('ayuda.html')

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
