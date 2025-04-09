# 🚇 Gestor de Túneles CloudFlare

<div align="center">
  <img src="https://github.com/innovafpiesmmg/cloudflare/raw/main/static/img/logo.png" alt="ATECA TECHLAB SOFTWARE" width="300"/>
  
  ![Version](https://img.shields.io/badge/Versión-1.6-blue)
  ![Plataforma](https://img.shields.io/badge/Plataforma-Ubuntu-purple)
  ![Idioma](https://img.shields.io/badge/Idioma-Español-green)
  ![CloudFlare](https://img.shields.io/badge/CloudFlare-Zero_Trust-orange)
  ![Licencia](https://img.shields.io/badge/Licencia-MIT-yellow)
</div>

## ¿Qué es el Gestor de Túneles CloudFlare?

Una solución **todo-en-uno** con interfaz web intuitiva para gestionar túneles CloudFlare Zero Trust en servidores Ubuntu. Esta herramienta, desarrollada por ATECA TECHLAB SOFTWARE, permite exponer servicios internos a Internet de forma segura y sin necesidad de configuraciones complejas.

**Repositorio oficial:** [https://github.com/innovafpiesmmg/cloudflare](https://github.com/innovafpiesmmg/cloudflare)

### 💡 La forma más sencilla de gestionar tus túneles Zero Trust

## ✨ Características

<div class="row">
  <div class="col-md-6">
    <h3>🛠️ Instalación y Configuración</h3>
    <ul>
      <li>✅ Interfaz web moderna e intuitiva 100% en español</li>
      <li>✅ Instalación automática de CloudFlared con feedback en tiempo real</li>
      <li>✅ Creación de túneles con un solo clic</li>
      <li>✅ Configuración visual sin necesidad de editar archivos manualmente</li>
      <li>✅ No requiere Docker ni contenedores</li>
      <li>✅ Configuración de API de Cloudflare durante la instalación</li>
    </ul>
  </div>
  <div class="col-md-6">
    <h3>🔒 Seguridad y Rendimiento</h3>
    <ul>
      <li>✅ Integración con CloudFlare Zero Trust</li>
      <li>✅ Opciones avanzadas de seguridad y configuración</li>
      <li>✅ Gestión automática como servicios del sistema (systemd)</li>
      <li>✅ Monitorización en tiempo real con alertas</li>
      <li>✅ API de verificación de estado (health check)</li>
      <li>✅ Almacenamiento seguro de credenciales de Cloudflare</li>
    </ul>
  </div>
</div>

<p align="center">
  <strong>🌟 Diseñado para funcionar en cualquier servidor Ubuntu, incluso recién instalado</strong>
</p>

## 📋 Requisitos

- **Sistema:** Servidor Ubuntu 16.04 o superior
- **Permisos:** Acceso de administrador (sudo/root)
- **Red:** Conexión a Internet activa
- **Cuenta:** CloudFlare con un dominio configurado

> **¡No se preocupe por otras dependencias!** El script de instalación se encarga de todas ellas automáticamente.

## 🚀 Instalación en 3 sencillos pasos

<div class="installation-steps">
  <div class="step">
    <h3>1️⃣ Descargar</h3>
    <pre><code>curl -L -o install.sh https://raw.githubusercontent.com/innovafpiesmmg/cloudflare/main/install.sh</code></pre>
    <p>Descarga el script de instalación desde nuestro repositorio oficial</p>
  </div>
  
  <div class="step">
    <h3>2️⃣ Permiso de ejecución</h3>
    <pre><code>chmod +x install.sh</code></pre>
    <p>Otorga permisos de ejecución al script de instalación</p>
  </div>
  
  <div class="step">
    <h3>3️⃣ Ejecutar</h3>
    <pre><code>sudo ./install.sh</code></pre>
    <p>El instalador se encarga de todo automáticamente</p>
  </div>
</div>

<div class="alert alert-success">
  <p>✅ <strong>El instalador configura automáticamente:</strong></p>
  <ul>
    <li>⚙️ Actualización del sistema y repositorios</li>
    <li>📦 Instalación de todas las dependencias necesarias</li>
    <li>🔌 Configuración de la aplicación web en el puerto 5000</li>
    <li>🔄 Servicios systemd para arranque automático</li>
    <li>📊 Sistema de monitoreo y alertas</li>
    <li>🔐 Permisos necesarios para un funcionamiento seguro</li>
    <li>🔑 Opción para configurar la API key de Cloudflare durante la instalación</li>
  </ul>
</div>

<p align="center">
  <em>El script está optimizado para funcionar incluso en servidores Ubuntu recién instalados con configuración mínima</em>
</p>

## Configuración para producción

Para un entorno de producción, se recomiendan los siguientes pasos adicionales:

### 1. Configurar HTTPS

Para mayor seguridad, configure un proxy inverso como Nginx con certificados SSL:

```bash
# Instalar Nginx
sudo apt-get install nginx

# Configurar proxy inverso
cat > /etc/nginx/sites-available/gestor-tuneles-cloudflare << EOF
server {
    listen 80;
    server_name tu-dominio.com;
    
    # Redireccionar HTTP a HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name tu-dominio.com;

    ssl_certificate /ruta/al/certificado.crt;
    ssl_certificate_key /ruta/al/certificado.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    
    location / {
        proxy_pass http://localhost:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Activar configuración
sudo ln -s /etc/nginx/sites-available/gestor-tuneles-cloudflare /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

### 2. Ajustar parámetros de rendimiento

Para mejorar el rendimiento en producción, edite el archivo de servicio:

```bash
sudo systemctl edit gestor-tuneles-cloudflare
```

Añadir los siguientes parámetros:

```ini
[Service]
ExecStart=
ExecStart=/opt/gestor-tuneles-cloudflare/venv/bin/gunicorn --bind 0.0.0.0:5000 --workers 4 --timeout 120 main:app
```

### 3. Sistema de Monitoreo y Alertas

La aplicación incluye un avanzado sistema de monitoreo que verifica automáticamente el estado de los túneles y envía alertas por correo electrónico cuando detecta problemas:

```bash
# Verificar estado del servicio de monitoreo
sudo systemctl status cloudflare-monitor

# Logs del monitoreo
sudo journalctl -u cloudflare-monitor -f
```

Para configurar las notificaciones por correo electrónico:

1. Edite el archivo de configuración:
```bash
sudo nano /opt/gestor-tuneles-cloudflare/config/monitor_config.json
```

2. Configure los parámetros SMTP y activación:
```json
{
    "email_notifications": true,
    "smtp_server": "smtp.tuempresa.com",
    "smtp_port": 587,
    "smtp_user": "usuario@tuempresa.com",
    "smtp_password": "contraseña_segura",
    "notification_email": "admin@tuempresa.com",
    "from_email": "alertas@tuempresa.com",
    "check_interval_seconds": 300
}
```

3. Reinicie el servicio de monitoreo:
```bash
sudo systemctl restart cloudflare-monitor
```

### 4. API de Verificación de Estado (Health Check)

La aplicación proporciona un endpoint para verificar el estado del sistema:

```bash
# Verificar estado general
curl http://localhost:5000/health

# Obtener estadísticas detalladas del sistema
curl http://localhost:5000/api/system/stats
```

Este endpoint puede utilizarse con sistemas de monitoreo externos como Nagios, Zabbix o Prometheus.

### 5. Configuración de API de Cloudflare

Durante la instalación, el script ofrece la opción de configurar las credenciales de Cloudflare. También puedes configurarlas posteriormente desde la interfaz web:

```bash
# Acceder a la página de configuración de Cloudflare
http://tu-servidor:5000/configurar-cloudflare
```

La configuración de Cloudflare te permite:
- Autenticar automáticamente con la API de Cloudflare
- Crear túneles vinculados a tu cuenta
- Configurar dominios para tus servicios
- Gestionar el acceso Zero Trust

## Repositorio y Actualizaciones

El código fuente oficial se encuentra en:
- [GitHub: innovafpiesmmg/cloudflare](https://github.com/innovafpiesmmg/cloudflare)

Para actualizar a la última versión:
```bash
# Descargar el script de actualización
curl -L -o update.sh https://raw.githubusercontent.com/innovafpiesmmg/cloudflare/main/update.sh

# Dar permisos de ejecución
chmod +x update.sh

# Ejecutar como root o con sudo
sudo ./update.sh
```

## Solución de Problemas

### Problemas con la Instalación

Si encuentra problemas durante la instalación, revise los siguientes casos comunes:

1. **Error de conexión durante la actualización de repositorios**:
   ```bash
   # Verificar conectividad a Internet
   ping -c 3 google.com
   
   # Verificar configuración DNS
   cat /etc/resolv.conf
   ```

2. **Error al instalar dependencias de Python**:
   ```bash
   # Instalar manualmente las dependencias críticas
   apt-get install -y python3-pip python3-dev build-essential
   python3 -m pip install --upgrade pip
   python3 -m pip install flask gunicorn
   ```

3. **Error al instalar cloudflared automáticamente**:
   Si el instalador no puede instalar cloudflared correctamente, puede usar el script de instalación manual incluido:
   ```bash
   # Dar permisos de ejecución al script
   chmod +x install_cloudflared.sh
   
   # Ejecutar el script como root
   sudo ./install_cloudflared.sh
   ```
   
   O instalar manualmente siguiendo estos pasos:
   ```bash
   # Añadir la clave GPG de Cloudflare
   sudo mkdir -p --mode=0755 /usr/share/keyrings
   curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
   
   # Añadir el repositorio
   echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
   
   # Instalar cloudflared
   sudo apt-get update && sudo apt-get install -y cloudflared
   ```

4. **El servicio no inicia correctamente**:
   ```bash
   # Verificar logs detallados
   journalctl -u gestor-tuneles-cloudflare -n 50
   
   # Verificar archivos de configuración
   ls -la /opt/gestor-tuneles-cloudflare/
   ```

5. **Puerto 5000 ya en uso**:
   ```bash
   # Verificar qué está usando el puerto 5000
   lsof -i :5000
   
   # Editar el archivo de servicio para usar otro puerto
   sudo systemctl edit gestor-tuneles-cloudflare
   # Añadir: ExecStart=/opt/gestor-tuneles-cloudflare/venv/bin/gunicorn --bind 0.0.0.0:5001 --reuse-port --reload main:app
   ```

### Actualización Manual

Si necesita actualizar manualmente:

```bash
cd /opt/gestor-tuneles-cloudflare
git pull origin main
pip install -r requirements.txt
systemctl restart gestor-tuneles-cloudflare
```

## 🤝 Soporte y Comunidad

<div class="community-section">
  <div class="support-channels">
    <h3>📣 Canales de soporte</h3>
    <ul>
      <li>🐞 <a href="https://github.com/innovafpiesmmg/cloudflare/issues">Reportar un problema</a></li>
      <li>🔧 <a href="https://github.com/innovafpiesmmg/cloudflare/pulls">Enviar una mejora</a></li>
      <li>📚 <a href="https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/">Documentación oficial de CloudFlare Zero Trust</a></li>
    </ul>
  </div>

  <div class="contribution">
    <h3>👨‍💻 ¿Cómo contribuir?</h3>
    <ol>
      <li>Haz un fork del repositorio</li>
      <li>Crea una rama para tu funcionalidad (<code>git checkout -b nueva-funcionalidad</code>)</li>
      <li>Haz commit de tus cambios (<code>git commit -m 'Añade nueva funcionalidad'</code>)</li>
      <li>Sube tu rama (<code>git push origin nueva-funcionalidad</code>)</li>
      <li>Abre un Pull Request</li>
    </ol>
  </div>
</div>

---

<div align="center">
  <img src="https://github.com/innovafpiesmmg/cloudflare/raw/main/static/img/ateca-techlab-new-logo.png" alt="ATECA TECHLAB SOFTWARE" width="200"/>
  
  <p>Este proyecto está desarrollado por <a href="https://ateca.es">ATECA TECHLAB SOFTWARE</a><br>y publicado como software de código abierto bajo la <strong>Licencia MIT</strong>.</p>
  
  <p>© 2023-2025 ATECA TECHLAB SOFTWARE</p>
</div>
