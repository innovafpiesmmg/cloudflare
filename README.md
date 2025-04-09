# Gestor de Túneles CloudFlare

![Gestor de Túneles CloudFlare](https://img.shields.io/badge/CloudFlare-Gestor%20de%20Túneles-orange)
![Version](https://img.shields.io/badge/Versión-1.2-blue)
![Idioma](https://img.shields.io/badge/Idioma-Español-green)
![Plataforma](https://img.shields.io/badge/Plataforma-Ubuntu-purple)

Una interfaz gráfica web en español para instalar y configurar túneles CloudFlare Zero Trust en servidores Ubuntu sin Docker, desarrollada por ATECA TECHLAB SOFTWARE. Esta aplicación permite acceder a distintos servicios alojados en el servidor mediante túneles, proporcionando una gestión completa y monitorización avanzada.

**Repositorio oficial:** [https://github.com/innovafpiesmmg/cloudflare](https://github.com/innovafpiesmmg/cloudflare)

## Características

- ✅ Interfaz gráfica web completa en español
- ✅ Instalación sencilla de CloudFlare Tunnel
- ✅ Creación y gestión de túneles Zero Trust
- ✅ Configuración de servicios para acceso a través de túneles
- ✅ Monitorización del estado de los túneles con alertas automáticas
- ✅ Gestión como servicios del sistema (systemd) 
- ✅ No requiere Docker
- ✅ Optimizado para entornos de producción
- ✅ API de verificación de estado (health check)

## Requisitos

- Servidor Ubuntu (16.04+)
- Python 3.6+
- Permisos de administrador (sudo/root)
- Conexión a Internet
- Cuenta en CloudFlare con un dominio configurado

## Instalación rápida

```bash
# Descargar script de instalación desde el repositorio oficial
curl -L -o install.sh https://raw.githubusercontent.com/innovafpiesmmg/cloudflare/main/install.sh

# Dar permisos de ejecución
chmod +x install.sh

# Ejecutar como root o con sudo
sudo ./install.sh
```

La instalación configurará automáticamente:
- Actualiza el sistema y repositorios
- Instala todas las dependencias necesarias (Python, librerías, herramientas)
- Configura la aplicación web en el puerto 5000
- Configura servicios systemd para arranque automático
- Instala el sistema de monitoreo y alertas
- Configura los permisos necesarios para el funcionamiento seguro

El script está diseñado para funcionar incluso en servidores Ubuntu recién instalados con configuración mínima.

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

3. **El servicio no inicia correctamente**:
   ```bash
   # Verificar logs detallados
   journalctl -u gestor-tuneles-cloudflare -n 50
   
   # Verificar archivos de configuración
   ls -la /opt/gestor-tuneles-cloudflare/
   ```

4. **Puerto 5000 ya en uso**:
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

## Soporte y Contribuciones

Para obtener ayuda o contribuir al proyecto:

- Reportar problemas: [Abrir un Issue](https://github.com/innovafpiesmmg/cloudflare/issues)
- Enviar mejoras: [Pull Request](https://github.com/innovafpiesmmg/cloudflare/pulls)
- Documentación de CloudFlare: [CloudFlare Zero Trust](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)

## Licencia

Este proyecto está desarrollado por [ATECA TECHLAB SOFTWARE](https://ateca.es) y publicado como software de código abierto bajo la Licencia MIT.

© 2023-2025 ATECA TECHLAB SOFTWARE
