import os
import logging
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, session
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

# Configuración del logging
logging.basicConfig(level=logging.DEBUG)

# Inicializar la aplicación Flask
app = Flask(__name__)
app.secret_key = os.environ.get("SESSION_SECRET", "cloudflare_tunnel_config_secret")

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
        # Instalar dependencias primero
        install_result_deps = install_dependencies()
        
        # Instalar cloudflared
        install_result = install_cloudflared()
        
        if install_result:
            flash('CloudFlared ha sido instalado correctamente.', 'success')
        else:
            flash('Error al instalar CloudFlared.', 'danger')
            
        return redirect(url_for('instalacion'))
    except Exception as e:
        flash(f'Error durante la instalación: {str(e)}', 'danger')
        app.logger.error(f"Error durante la instalación: {str(e)}")
        return redirect(url_for('instalacion'))

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

# Ruta para la página de ayuda
@app.route('/ayuda')
def ayuda():
    return render_template('ayuda.html')

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
