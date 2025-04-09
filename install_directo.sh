#!/bin/bash

# Script de instalación para CloudFlare Tunnel Manager
# Versión independiente que no requiere clonar el repositorio

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
                   curl wget sudo systemd lsb-release \
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

# Crear estructura de directorios
print_status "Creando estructura de directorios..."
mkdir -p $INSTALL_DIR/static/css
mkdir -p $INSTALL_DIR/static/js
mkdir -p $INSTALL_DIR/static/img
mkdir -p $INSTALL_DIR/templates
mkdir -p $INSTALL_DIR/utils
mkdir -p $INSTALL_DIR/config

# Crear entorno virtual de Python
print_status "Creando entorno virtual de Python..."
python3 -m venv venv
source venv/bin/activate

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

# Crear archivos principales
print_status "Creando archivos principales de la aplicación..."

# Crear main.py
cat > $INSTALL_DIR/main.py << 'EOF'
import os
from flask import Flask, render_template, jsonify, request, redirect, url_for, flash, abort, Response
import logging
import yaml
import json
import psutil
import platform
from werkzeug.middleware.proxy_fix import ProxyFix
from functools import wraps
import socket
import ipaddress

app = Flask(__name__)
app.secret_key = os.urandom(24)
app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)

# Configuración de logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')

# Ruta principal
@app.route('/')
def index():
    return render_template('index.html', 
                          title='Gestor de Túneles CloudFlare',
                          page_title='Inicio',
                          version='1.2')

# Ruta de instalación
@app.route('/instalacion')
def instalacion():
    return render_template('instalacion.html', 
                          title='Instalación - Gestor de Túneles CloudFlare',
                          page_title='Instalación de CloudFlared')

# Ruta de configuración
@app.route('/configuracion')
def configuracion():
    return render_template('configuracion.html', 
                          title='Configuración - Gestor de Túneles CloudFlare',
                          page_title='Configuración de Túneles')

# Ruta de servicios
@app.route('/servicios')
def servicios():
    return render_template('servicios.html', 
                          title='Servicios - Gestor de Túneles CloudFlare',
                          page_title='Gestión de Servicios')

# Ruta de estado
@app.route('/estado')
def estado():
    return render_template('estado.html', 
                          title='Estado - Gestor de Túneles CloudFlare',
                          page_title='Estado de los Túneles')

# Ruta de ayuda
@app.route('/ayuda')
def ayuda():
    return render_template('ayuda.html', 
                          title='Ayuda - Gestor de Túneles CloudFlare',
                          page_title='Ayuda y Documentación')

# Verificación de estado (health check)
@app.route('/health')
def health_check():
    return jsonify({
        "status": "ok",
        "version": "1.2",
        "uptime": int(psutil.boot_time()),
        "timestamp": int(psutil.time.time())
    })

# Estadísticas del sistema
@app.route('/api/system/stats')
def system_stats():
    stats = {
        "cpu": psutil.cpu_percent(interval=1),
        "memory": {
            "total": psutil.virtual_memory().total,
            "available": psutil.virtual_memory().available,
            "percent": psutil.virtual_memory().percent
        },
        "disk": {
            "total": psutil.disk_usage('/').total,
            "free": psutil.disk_usage('/').free,
            "percent": psutil.disk_usage('/').percent
        },
        "system": {
            "platform": platform.system(),
            "release": platform.release(),
            "version": platform.version(),
            "hostname": socket.gethostname(),
            "uptime": int(psutil.time.time() - psutil.boot_time())
        }
    }
    return jsonify(stats)

# Cabeceras de seguridad
@app.after_request
def add_security_headers(response):
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'SAMEORIGIN'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
    response.headers['Content-Security-Policy'] = "default-src 'self'; script-src 'self' 'unsafe-inline' cdnjs.cloudflare.com cdn.jsdelivr.net; style-src 'self' 'unsafe-inline' cdnjs.cloudflare.com cdn.jsdelivr.net; img-src 'self' data:;"
    return response

if __name__ == "__main__":
    debug_mode = os.environ.get('FLASK_ENV') != 'production'
    app.run(host="0.0.0.0", port=5000, debug=debug_mode)
EOF

# Crear plantillas base
mkdir -p $INSTALL_DIR/templates

# Crear layout.html
cat > $INSTALL_DIR/templates/layout.html << 'EOF'
<!DOCTYPE html>
<html lang="es" data-bs-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{ title }}</title>
    <link rel="stylesheet" href="https://cdn.replit.com/agent/bootstrap-agent-dark-theme.min.css">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/5.15.4/css/all.min.css">
    <link rel="stylesheet" href="{{ url_for('static', filename='css/custom.css') }}">
    <link rel="shortcut icon" href="{{ url_for('static', filename='img/favicon.ico') }}">
</head>
<body>
    <nav class="navbar navbar-expand-lg navbar-dark bg-dark">
        <div class="container">
            <a class="navbar-brand" href="/">
                <img src="{{ url_for('static', filename='img/techlab.png') }}" alt="ATECA TECHLAB SOFTWARE" height="30">
                Gestor de Túneles CloudFlare
            </a>
            <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#navbarNav" aria-controls="navbarNav" aria-expanded="false" aria-label="Toggle navigation">
                <span class="navbar-toggler-icon"></span>
            </button>
            <div class="collapse navbar-collapse" id="navbarNav">
                <ul class="navbar-nav ms-auto">
                    <li class="nav-item">
                        <a class="nav-link" href="/"><i class="fas fa-home"></i> Inicio</a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link" href="/instalacion"><i class="fas fa-download"></i> Instalación</a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link" href="/configuracion"><i class="fas fa-cogs"></i> Configuración</a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link" href="/servicios"><i class="fas fa-server"></i> Servicios</a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link" href="/estado"><i class="fas fa-chart-line"></i> Estado</a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link" href="/ayuda"><i class="fas fa-question-circle"></i> Ayuda</a>
                    </li>
                </ul>
            </div>
        </div>
    </nav>

    <div class="container mt-4">
        <div class="row">
            <div class="col-12">
                <h1 class="mb-4">{{ page_title }}</h1>
                {% with messages = get_flashed_messages(with_categories=true) %}
                    {% if messages %}
                        {% for category, message in messages %}
                            <div class="alert alert-{{ category }} alert-dismissible fade show" role="alert">
                                {{ message }}
                                <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
                            </div>
                        {% endfor %}
                    {% endif %}
                {% endwith %}
            </div>
        </div>
        
        {% block content %}{% endblock %}
    </div>

    <footer class="footer mt-5 py-3 bg-dark">
        <div class="container">
            <div class="row">
                <div class="col-md-6 text-center text-md-start">
                    <span class="text-muted">Gestor de Túneles CloudFlare v1.2</span>
                </div>
                <div class="col-md-6 text-center text-md-end">
                    <span class="text-muted">Desarrollado por <a href="https://ateca.es" target="_blank" class="text-decoration-none">ATECA TECHLAB SOFTWARE</a></span>
                </div>
            </div>
        </div>
    </footer>

    <script src="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.0/js/bootstrap.bundle.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/3.7.0/chart.min.js"></script>
    <script src="{{ url_for('static', filename='js/script.js') }}"></script>
</body>
</html>
EOF

# Crear index.html
cat > $INSTALL_DIR/templates/index.html << 'EOF'
{% extends 'layout.html' %}

{% block content %}
<div class="row">
    <div class="col-md-8">
        <div class="card mb-4">
            <div class="card-header">
                <h5 class="card-title mb-0"><i class="fas fa-info-circle"></i> Información General</h5>
            </div>
            <div class="card-body">
                <p>Bienvenido al Gestor de Túneles CloudFlare, una aplicación web para instalar, configurar y gestionar túneles CloudFlare Zero Trust en servidores Ubuntu.</p>
                
                <p>Esta herramienta te permite:</p>
                <ul>
                    <li>Instalar CloudFlared fácilmente en tu servidor</li>
                    <li>Crear y gestionar túneles de acceso seguro</li>
                    <li>Configurar servicios para acceso a través de dominios personalizados</li>
                    <li>Monitorizar el estado de tus túneles en tiempo real</li>
                </ul>
                
                <p>Para comenzar, sigue estos pasos:</p>
                <ol>
                    <li>Instala el cliente CloudFlared en tu servidor</li>
                    <li>Configura un nuevo túnel con tu cuenta de CloudFlare</li>
                    <li>Añade los servicios que deseas exponer a través del túnel</li>
                    <li>Inicia el túnel y verifica su funcionamiento</li>
                </ol>
            </div>
        </div>
    </div>
    
    <div class="col-md-4">
        <div class="card mb-4">
            <div class="card-header">
                <h5 class="card-title mb-0"><i class="fas fa-tasks"></i> Acciones Rápidas</h5>
            </div>
            <div class="card-body">
                <div class="list-group">
                    <a href="/instalacion" class="list-group-item list-group-item-action">
                        <i class="fas fa-download me-2"></i> Instalar CloudFlared
                    </a>
                    <a href="/configuracion" class="list-group-item list-group-item-action">
                        <i class="fas fa-cogs me-2"></i> Configurar Túnel
                    </a>
                    <a href="/servicios" class="list-group-item list-group-item-action">
                        <i class="fas fa-server me-2"></i> Gestionar Servicios
                    </a>
                    <a href="/estado" class="list-group-item list-group-item-action">
                        <i class="fas fa-chart-line me-2"></i> Ver Estado
                    </a>
                </div>
            </div>
        </div>
        
        <div class="card">
            <div class="card-header">
                <h5 class="card-title mb-0"><i class="fas fa-link"></i> Enlaces Útiles</h5>
            </div>
            <div class="card-body">
                <div class="list-group">
                    <a href="https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/" target="_blank" class="list-group-item list-group-item-action">
                        <i class="fas fa-external-link-alt me-2"></i> Documentación CloudFlare
                    </a>
                    <a href="https://github.com/innovafpiesmmg/cloudflare" target="_blank" class="list-group-item list-group-item-action">
                        <i class="fab fa-github me-2"></i> Repositorio en GitHub
                    </a>
                </div>
            </div>
        </div>
    </div>
</div>
{% endblock %}
EOF

# Crear plantillas adicionales con contenido básico
cat > $INSTALL_DIR/templates/instalacion.html << 'EOF'
{% extends 'layout.html' %}

{% block content %}
<div class="card">
    <div class="card-header">
        <h5 class="card-title mb-0"><i class="fas fa-download"></i> Instalación de CloudFlared</h5>
    </div>
    <div class="card-body">
        <p>Esta sección te permite instalar y verificar la instalación de CloudFlared, el cliente necesario para crear túneles Zero Trust.</p>
        
        <div class="alert alert-info">
            <i class="fas fa-info-circle"></i> CloudFlared debe estar instalado en tu servidor para poder crear y gestionar túneles.
        </div>
        
        <div class="mb-4">
            <h5>Estado actual de CloudFlared</h5>
            <div class="card">
                <div class="card-body">
                    <p>Esta funcionalidad estará disponible cuando complete la configuración del repositorio.</p>
                </div>
            </div>
        </div>
        
        <div class="mb-4">
            <h5>Instalar o actualizar CloudFlared</h5>
            <p>Haga clic en el botón para instalar o actualizar CloudFlared a la última versión disponible.</p>
            <button class="btn btn-primary" disabled>Instalar CloudFlared</button>
        </div>
    </div>
</div>
{% endblock %}
EOF

cat > $INSTALL_DIR/templates/configuracion.html << 'EOF'
{% extends 'layout.html' %}

{% block content %}
<div class="card">
    <div class="card-header">
        <h5 class="card-title mb-0"><i class="fas fa-cogs"></i> Configuración de Túneles</h5>
    </div>
    <div class="card-body">
        <p>Esta sección te permite crear, configurar y gestionar tus túneles CloudFlare Zero Trust.</p>
        
        <div class="alert alert-info">
            <i class="fas fa-info-circle"></i> Para crear un túnel, necesitas tener una cuenta en CloudFlare y un dominio configurado.
        </div>
        
        <div class="mb-4">
            <h5>Túneles configurados</h5>
            <div class="card">
                <div class="card-body">
                    <p>Esta funcionalidad estará disponible cuando complete la configuración del repositorio.</p>
                </div>
            </div>
        </div>
        
        <div class="mb-4">
            <h5>Crear nuevo túnel</h5>
            <p>Utiliza el formulario a continuación para crear un nuevo túnel.</p>
            <form>
                <div class="mb-3">
                    <label for="tunnelName" class="form-label">Nombre del túnel</label>
                    <input type="text" class="form-control" id="tunnelName" placeholder="mi-tunel" disabled>
                </div>
                <button type="submit" class="btn btn-primary" disabled>Crear túnel</button>
            </form>
        </div>
    </div>
</div>
{% endblock %}
EOF

cat > $INSTALL_DIR/templates/servicios.html << 'EOF'
{% extends 'layout.html' %}

{% block content %}
<div class="card">
    <div class="card-header">
        <h5 class="card-title mb-0"><i class="fas fa-server"></i> Gestión de Servicios</h5>
    </div>
    <div class="card-body">
        <p>Esta sección te permite añadir, configurar y gestionar los servicios que deseas exponer a través de tus túneles.</p>
        
        <div class="alert alert-info">
            <i class="fas fa-info-circle"></i> Para añadir un servicio, primero debes tener un túnel configurado.
        </div>
        
        <div class="mb-4">
            <h5>Servicios configurados</h5>
            <div class="card">
                <div class="card-body">
                    <p>Esta funcionalidad estará disponible cuando complete la configuración del repositorio.</p>
                </div>
            </div>
        </div>
        
        <div class="mb-4">
            <h5>Añadir nuevo servicio</h5>
            <p>Utiliza el formulario a continuación para añadir un nuevo servicio a un túnel existente.</p>
            <form>
                <div class="mb-3">
                    <label for="tunnelSelect" class="form-label">Túnel</label>
                    <select class="form-select" id="tunnelSelect" disabled>
                        <option selected>Seleccionar túnel</option>
                    </select>
                </div>
                <div class="mb-3">
                    <label for="serviceName" class="form-label">Nombre del servicio</label>
                    <input type="text" class="form-control" id="serviceName" placeholder="web-admin" disabled>
                </div>
                <div class="mb-3">
                    <label for="servicePort" class="form-label">Puerto del servicio</label>
                    <input type="number" class="form-control" id="servicePort" placeholder="8080" disabled>
                </div>
                <div class="mb-3">
                    <label for="domain" class="form-label">Dominio para acceso externo</label>
                    <input type="text" class="form-control" id="domain" placeholder="servicio.midominio.com" disabled>
                </div>
                <button type="submit" class="btn btn-primary" disabled>Añadir servicio</button>
            </form>
        </div>
    </div>
</div>
{% endblock %}
EOF

cat > $INSTALL_DIR/templates/estado.html << 'EOF'
{% extends 'layout.html' %}

{% block content %}
<div class="card">
    <div class="card-header">
        <h5 class="card-title mb-0"><i class="fas fa-chart-line"></i> Estado de los Túneles</h5>
    </div>
    <div class="card-body">
        <p>Esta sección muestra el estado actual y las métricas de tus túneles CloudFlare Zero Trust.</p>
        
        <div class="mb-4">
            <h5>Estado del sistema</h5>
            <div class="row">
                <div class="col-md-4 mb-3">
                    <div class="card bg-primary text-white">
                        <div class="card-body">
                            <h5 class="card-title"><i class="fas fa-microchip"></i> CPU</h5>
                            <h3 class="mb-0" id="cpuUsage">--</h3>
                        </div>
                    </div>
                </div>
                <div class="col-md-4 mb-3">
                    <div class="card bg-success text-white">
                        <div class="card-body">
                            <h5 class="card-title"><i class="fas fa-memory"></i> Memoria</h5>
                            <h3 class="mb-0" id="memoryUsage">--</h3>
                        </div>
                    </div>
                </div>
                <div class="col-md-4 mb-3">
                    <div class="card bg-info text-white">
                        <div class="card-body">
                            <h5 class="card-title"><i class="fas fa-hdd"></i> Disco</h5>
                            <h3 class="mb-0" id="diskUsage">--</h3>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="mb-4">
            <h5>Estado de los túneles</h5>
            <div class="card">
                <div class="card-body">
                    <p>Esta funcionalidad estará disponible cuando complete la configuración del repositorio.</p>
                </div>
            </div>
        </div>
    </div>
</div>

<script>
// Actualizar estadísticas del sistema
function updateSystemStats() {
    fetch('/api/system/stats')
        .then(response => response.json())
        .then(data => {
            document.getElementById('cpuUsage').textContent = data.cpu + '%';
            document.getElementById('memoryUsage').textContent = data.memory.percent + '%';
            document.getElementById('diskUsage').textContent = data.disk.percent + '%';
        })
        .catch(error => console.error('Error:', error));
}

// Actualizar cada 5 segundos
updateSystemStats();
setInterval(updateSystemStats, 5000);
</script>
{% endblock %}
EOF

cat > $INSTALL_DIR/templates/ayuda.html << 'EOF'
{% extends 'layout.html' %}

{% block content %}
<div class="card">
    <div class="card-header">
        <h5 class="card-title mb-0"><i class="fas fa-question-circle"></i> Ayuda y Documentación</h5>
    </div>
    <div class="card-body">
        <p>Esta sección proporciona información útil y guías para aprovechar al máximo el Gestor de Túneles CloudFlare.</p>
        
        <div class="accordion" id="accordionHelp">
            <div class="accordion-item">
                <h2 class="accordion-header" id="headingOne">
                    <button class="accordion-button" type="button" data-bs-toggle="collapse" data-bs-target="#collapseOne" aria-expanded="true" aria-controls="collapseOne">
                        ¿Qué es CloudFlare Zero Trust?
                    </button>
                </h2>
                <div id="collapseOne" class="accordion-collapse collapse show" aria-labelledby="headingOne" data-bs-parent="#accordionHelp">
                    <div class="accordion-body">
                        <p>CloudFlare Zero Trust es un conjunto de servicios que permiten una conexión segura a tus aplicaciones y recursos sin necesidad de una VPN tradicional. En lugar de confiar en una red perimetral, el acceso se basa en la identidad del usuario y el contexto de la conexión.</p>
                        <p>Los túneles de CloudFlare permiten exponer servicios internos de forma segura a Internet, sin necesidad de abrir puertos en tu firewall o tener una IP pública.</p>
                    </div>
                </div>
            </div>
            <div class="accordion-item">
                <h2 class="accordion-header" id="headingTwo">
                    <button class="accordion-button collapsed" type="button" data-bs-toggle="collapse" data-bs-target="#collapseTwo" aria-expanded="false" aria-controls="collapseTwo">
                        ¿Cómo funciona un túnel?
                    </button>
                </h2>
                <div id="collapseTwo" class="accordion-collapse collapse" aria-labelledby="headingTwo" data-bs-parent="#accordionHelp">
                    <div class="accordion-body">
                        <p>Un túnel CloudFlare funciona de la siguiente manera:</p>
                        <ol>
                            <li>El cliente CloudFlared se instala en tu servidor y establece una conexión segura saliente hacia CloudFlare.</li>
                            <li>Esta conexión se mantiene abierta y permite que el tráfico de CloudFlare llegue a tus servicios internos.</li>
                            <li>Cuando un usuario intenta acceder a tu dominio, el tráfico pasa por la red de CloudFlare y se envía a través del túnel.</li>
                            <li>CloudFlared recibe el tráfico y lo dirige al servicio local correspondiente.</li>
                        </ol>
                        <p>De esta forma, no necesitas exponer directamente tus servicios a Internet ni configurar reglas complejas de firewall.</p>
                    </div>
                </div>
            </div>
            <div class="accordion-item">
                <h2 class="accordion-header" id="headingThree">
                    <button class="accordion-button collapsed" type="button" data-bs-toggle="collapse" data-bs-target="#collapseThree" aria-expanded="false" aria-controls="collapseThree">
                        Solución de problemas comunes
                    </button>
                </h2>
                <div id="collapseThree" class="accordion-collapse collapse" aria-labelledby="headingThree" data-bs-parent="#accordionHelp">
                    <div class="accordion-body">
                        <h5>El túnel no se inicia</h5>
                        <ul>
                            <li>Verifica que CloudFlared esté instalado correctamente con <code>cloudflared --version</code></li>
                            <li>Asegúrate de que el archivo de configuración es válido</li>
                            <li>Comprueba los logs del servicio con <code>journalctl -u cloudflared-tunel</code></li>
                            <li>Verifica que hay conectividad a Internet desde el servidor</li>
                        </ul>
                        
                        <h5>No puedo acceder a mis servicios a través del túnel</h5>
                        <ul>
                            <li>Comprueba que el dominio está correctamente configurado en CloudFlare</li>
                            <li>Verifica que el servicio local está en funcionamiento y accesible desde el propio servidor</li>
                            <li>Revisa la configuración del túnel para asegurarte de que el dominio y el puerto son correctos</li>
                        </ul>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="mt-4">
            <h5>Recursos adicionales</h5>
            <ul>
                <li><a href="https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/" target="_blank">Documentación oficial de CloudFlare Tunnel</a></li>
                <li><a href="https://github.com/innovafpiesmmg/cloudflare" target="_blank">Repositorio de GitHub del proyecto</a></li>
            </ul>
        </div>
    </div>
</div>
{% endblock %}
EOF

# Crear carpetas y archivos estáticos
mkdir -p $INSTALL_DIR/static/css
mkdir -p $INSTALL_DIR/static/js
mkdir -p $INSTALL_DIR/static/img

# Crear CSS personalizado
cat > $INSTALL_DIR/static/css/custom.css << 'EOF'
/* Personalización para estilo Techlab */
:root {
    --techlab-primary: #0056b3;
    --techlab-secondary: #00a0e9;
    --techlab-accent: #00d1b2;
}

.navbar-brand img {
    margin-right: 10px;
}

.card {
    margin-bottom: 20px;
    border-radius: 8px;
    box-shadow: 0 2px 5px rgba(0, 0, 0, 0.1);
}

.card-header {
    font-weight: 600;
    background-color: rgba(0, 0, 0, 0.03);
}

.btn-primary {
    background-color: var(--techlab-primary);
    border-color: var(--techlab-primary);
}

.btn-primary:hover {
    background-color: #004494;
    border-color: #004494;
}

.bg-primary {
    background-color: var(--techlab-primary) !important;
}

.bg-success {
    background-color: var(--techlab-accent) !important;
}

.bg-info {
    background-color: var(--techlab-secondary) !important;
}

.footer {
    margin-top: 3rem;
    padding-top: 1.5rem;
    padding-bottom: 1.5rem;
    border-top: 1px solid rgba(255, 255, 255, 0.1);
}

.status-badge {
    font-size: 0.8rem;
    padding: 0.25rem 0.5rem;
    border-radius: 50px;
}

.status-running {
    background-color: #00d1b2;
    color: white;
}

.status-stopped {
    background-color: #f14668;
    color: white;
}

.status-unknown {
    background-color: #ffdd57;
    color: black;
}

/* Animación para cargas */
.loading {
    position: relative;
}

.loading:after {
    content: "";
    display: block;
    width: 1.2em;
    height: 1.2em;
    position: absolute;
    right: 10px;
    top: calc(50% - 0.6em);
    border: 2px solid rgba(255, 255, 255, 0.5);
    border-top: 2px solid white;
    border-radius: 50%;
    animation: spin 1s linear infinite;
}

@keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
}
EOF

# Crear JavaScript para la aplicación
cat > $INSTALL_DIR/static/js/script.js << 'EOF'
// Código JavaScript para la aplicación
document.addEventListener('DOMContentLoaded', function() {
    // Inicializar tooltips de Bootstrap
    var tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'))
    var tooltipList = tooltipTriggerList.map(function (tooltipTriggerEl) {
        return new bootstrap.Tooltip(tooltipTriggerEl)
    });
    
    // Validación de formularios si existen
    const forms = document.querySelectorAll('.needs-validation');
    if (forms.length > 0) {
        Array.from(forms).forEach(form => {
            form.addEventListener('submit', event => {
                if (!form.checkValidity()) {
                    event.preventDefault();
                    event.stopPropagation();
                }
                form.classList.add('was-validated');
            }, false);
        });
    }
    
    // Actualizar estado de túneles si estamos en la página de estado
    if (window.location.pathname === '/estado') {
        updateSystemStats();
        setInterval(updateSystemStats, 5000);
    }
});

// Función para actualizar estadísticas del sistema
function updateSystemStats() {
    fetch('/api/system/stats')
        .then(response => response.json())
        .then(data => {
            if (document.getElementById('cpuUsage')) {
                document.getElementById('cpuUsage').textContent = data.cpu + '%';
            }
            if (document.getElementById('memoryUsage')) {
                document.getElementById('memoryUsage').textContent = data.memory.percent + '%';
            }
            if (document.getElementById('diskUsage')) {
                document.getElementById('diskUsage').textContent = data.disk.percent + '%';
            }
        })
        .catch(error => console.error('Error:', error));
}

// Función para confirmar acciones peligrosas
function confirmarAccion(mensaje, formularioId) {
    if (confirm(mensaje)) {
        document.getElementById(formularioId).submit();
    }
    return false;
}
EOF

# Crear script de monitoreo
cat > $INSTALL_DIR/monitor.py << 'EOF'
#!/usr/bin/env python3
import argparse
import json
import logging
import os
import sys
import time
from datetime import datetime
import requests

# Configuración de logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('/var/log/cloudflare-monitor.log')
    ]
)

TUNNEL_CHECK_INTERVAL = 300  # 5 minutos por defecto
CONFIG_DIR = '/opt/gestor-tuneles-cloudflare/config'
CONFIG_FILE = os.path.join(CONFIG_DIR, 'monitor_config.json')
KNOWN_ISSUES_FILE = os.path.join(CONFIG_DIR, 'known_issues.json')

def load_config():
    """Cargar configuración del monitor"""
    if not os.path.exists(CONFIG_FILE):
        logging.warning(f"Archivo de configuración no encontrado: {CONFIG_FILE}")
        return {}
    
    try:
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    except Exception as e:
        logging.error(f"Error al cargar configuración: {str(e)}")
        return {}

def get_tunnels():
    """Obtener lista de túneles configurados"""
    try:
        # En una implementación real, esto obtendría la lista de túneles
        # Simplificado para este script básico
        return []
    except Exception as e:
        logging.error(f"Error al obtener lista de túneles: {str(e)}")
        return []

def monitor_tunnels():
    """Función principal para monitorizar túneles"""
    config = load_config()
    current_time = time.time()
    logging.info("Monitor de túneles iniciado")
    
    # Lógica de monitoreo (simplificada)
    tunnels = get_tunnels()
    if not tunnels:
        logging.warning("No se encontraron túneles para monitorizar")
    else:
        logging.info(f"Monitorizando {len(tunnels)} túneles")
    
    # Verificar estado del servidor web
    try:
        response = requests.get('http://localhost:5000/health', timeout=5)
        if response.status_code == 200:
            logging.info("Servidor web funcionando correctamente")
        else:
            logging.warning(f"El servidor web respondió con estado: {response.status_code}")
    except Exception as e:
        logging.error(f"Error al verificar el estado del servidor web: {str(e)}")

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
EOF
chmod +x $INSTALL_DIR/monitor.py

# Crear archivo de servicio systemd para el monitor
cat > "/etc/systemd/system/cloudflare-monitor.service" << EOF
[Unit]
Description=Monitor de Túneles CloudFlare
After=network.target gestor-tuneles-cloudflare.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/monitor.py --daemon
Restart=on-failure
RestartSec=10s
StandardOutput=append:/var/log/cloudflare-monitor.log
StandardError=append:/var/log/cloudflare-monitor.log

[Install]
WantedBy=multi-user.target
EOF

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

# Crear directorio de logs y config
mkdir -p $INSTALL_DIR/config
mkdir -p /var/log/cloudflare
touch /var/log/cloudflare-monitor.log
chmod 700 $INSTALL_DIR/config
chmod 640 /var/log/cloudflare-monitor.log

# Configuración de monitoreo
cat > "$INSTALL_DIR/config/monitor_config.json" << 'EOF'
{
    "email_notifications": false,
    "smtp_server": "smtp.example.com",
    "smtp_port": 587,
    "smtp_user": "usuario@example.com",
    "smtp_password": "contraseña_segura",
    "notification_email": "admin@example.com",
    "from_email": "cloudflare-monitor@example.com",
    "check_interval_seconds": 300,
    "alert_recovery_minutes": 30,
    "enable_system_stats": true,
    "allowed_ip_networks": [
        "127.0.0.1/8",
        "10.0.0.0/8",
        "172.16.0.0/12",
        "192.168.0.0/16"
    ]
}
EOF
chmod 600 "$INSTALL_DIR/config/monitor_config.json"

# Variable para entorno de producción
grep -q "FLASK_ENV=production" /etc/environment || echo "FLASK_ENV=production" >> /etc/environment

# Recargar systemd
systemctl daemon-reload

# Habilitar e iniciar el servicio
print_status "Habilitando e iniciando el servicio..."
systemctl enable gestor-tuneles-cloudflare
systemctl start gestor-tuneles-cloudflare

# Configuración del servicio de monitoreo
print_status "Configurando servicio de monitoreo..."
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
print_status "Monitoreo:"
print_status "- Estado del servicio principal: systemctl status gestor-tuneles-cloudflare"
print_status "- Estado del servicio de monitoreo: systemctl status cloudflare-monitor"
print_status "- Logs: journalctl -u gestor-tuneles-cloudflare -f"
print_status "- API de salud: http://$IP_ADDRESS:5000/health"
print_status ""
print_status "Para configurar notificaciones por correo, edita el archivo:"
print_status "$INSTALL_DIR/config/monitor_config.json"
print_status "====================================================="

print_status "NOTA IMPORTANTE: Esta es una instalación básica funcional."
print_status "Para la implementación completa, visita:"
print_status "https://github.com/innovafpiesmmg/cloudflare"
print_status "====================================================="

exit 0