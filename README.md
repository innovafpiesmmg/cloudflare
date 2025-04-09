# Gestor de Túneles CloudFlare

![Gestor de Túneles CloudFlare](https://img.shields.io/badge/CloudFlare-Gestor%20de%20Túneles-orange)
![Version](https://img.shields.io/badge/Versión-1.0-blue)
![Idioma](https://img.shields.io/badge/Idioma-Español-green)

Una aplicación web para instalar, configurar y gestionar túneles CloudFlare Zero Trust en servidores Ubuntu sin Docker.

## Características

- ✅ Interfaz gráfica web completa en español
- ✅ Instalación sencilla de CloudFlare Tunnel
- ✅ Creación y gestión de túneles Zero Trust
- ✅ Configuración de servicios para acceso a través de túneles
- ✅ Monitorización del estado de los túneles
- ✅ Gestión como servicios del sistema (systemd)
- ✅ No requiere Docker

## Requisitos

- Servidor Ubuntu (16.04+)
- Python 3.6+
- Permisos de administrador (sudo/root)
- Conexión a Internet
- Cuenta en CloudFlare con un dominio configurado

## Instalación rápida

```bash
# Descargar script de instalación
curl -L -o install.sh https://raw.githubusercontent.com/innovafpiesmmg/cloudflare/main/install.sh

# Dar permisos de ejecución
chmod +x install.sh

# Ejecutar como root o con sudo
sudo ./install.sh
```

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

### 3. Monitoreo del servicio

Configurar monitoreo básico:

```bash
# Instalar herramientas de monitoreo
sudo apt-get install -y prometheus-node-exporter

# Verificar logs regularmente
echo "0 */6 * * * root journalctl -u gestor-tuneles-cloudflare --since '6 hours ago' | grep -i error | mail -s 'Alerta: Errores en Gestor de Túneles CloudFlare' tu-email@ejemplo.com" > /etc/cron.d/monitoreo-cloudflare
```

## Soporte y Contribuciones

Para obtener ayuda o contribuir al proyecto:

- Reportar problemas: [Abrir un Issue](https://github.com/innovafpiesmmg/cloudflare/issues)
- Documentación de CloudFlare: [CloudFlare Zero Trust](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)

## Licencia

Este proyecto está desarrollado por [ATECA TECHLAB SOFTWARE](https://ateca.es) y publicado como software de código abierto.
