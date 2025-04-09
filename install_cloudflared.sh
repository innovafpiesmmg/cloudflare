#!/bin/bash
# Script para instalar Cloudflared utilizando el método oficial de Cloudflare
# Este script es útil cuando el método automático del gestor de túneles no funciona correctamente

# Función para imprimir mensajes con formato
print_status() {
    echo -e "\e[1;34m[*] $1\e[0m"
}

print_success() {
    echo -e "\e[1;32m[+] $1\e[0m"
}

print_error() {
    echo -e "\e[1;31m[!] $1\e[0m"
}

# Verificar si se está ejecutando como root
if [ "$EUID" -ne 0 ]; then
    print_error "Este script debe ejecutarse como root (sudo)"
    exit 1
fi

print_status "Iniciando instalación de cloudflared..."

# Crear el directorio para las claves GPG si no existe
print_status "Configurando repositorio oficial de Cloudflare..."
mkdir -p --mode=0755 /usr/share/keyrings

# Añadir la clave GPG de Cloudflare
print_status "Añadiendo clave GPG de Cloudflare..."
if ! curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null; then
    print_error "Error al añadir la clave GPG de Cloudflare"
    exit 1
fi

# Añadir el repositorio de Cloudflare
print_status "Añadiendo repositorio de Cloudflare a APT..."
if ! echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list; then
    print_error "Error al añadir el repositorio de Cloudflare"
    exit 1
fi

# Actualizar la lista de paquetes e instalar cloudflared
print_status "Actualizando APT e instalando cloudflared..."
if ! apt-get update; then
    print_error "Error al actualizar la lista de paquetes"
    exit 1
fi

if ! apt-get install -y cloudflared; then
    print_error "Error al instalar cloudflared"
    exit 1
fi

# Verificar que cloudflared se ha instalado correctamente
if command -v cloudflared >/dev/null 2>&1; then
    CLOUDFLARED_VERSION=$(cloudflared --version | head -n 1)
    print_success "cloudflared se ha instalado correctamente: $CLOUDFLARED_VERSION"
    print_status "Ahora puedes usar el Gestor de Túneles CloudFlare normalmente"
else
    print_error "No se pudo verificar la instalación de cloudflared"
    exit 1
fi

# Establecer los permisos adecuados para CloudFlared
print_status "Configurando permisos para CloudFlared..."
if [ -f "/usr/local/bin/cloudflared" ]; then
    chmod 755 /usr/local/bin/cloudflared
    print_success "Permisos configurados para /usr/local/bin/cloudflared"
elif [ -f "/usr/bin/cloudflared" ]; then
    chmod 755 /usr/bin/cloudflared
    print_success "Permisos configurados para /usr/bin/cloudflared"
fi

print_success "Instalación de cloudflared completada con éxito."
print_status "Ahora puedes usar el Gestor de Túneles CloudFlare normalmente."