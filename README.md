# CloudFlare Tunnel Manager

![CloudFlare Tunnel Manager](https://img.shields.io/badge/CloudFlare-Tunnel%20Manager-orange)
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
curl -L -o install.sh https://raw.githubusercontent.com/usuario/cloudflare-tunnel-manager/main/install.sh

# Dar permisos de ejecución
chmod +x install.sh

# Ejecutar como root o con sudo
sudo ./install.sh
