document.addEventListener('DOMContentLoaded', function() {
    // Habilitar tooltips de Bootstrap
    var tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
    var tooltipList = tooltipTriggerList.map(function (tooltipTriggerEl) {
        return new bootstrap.Tooltip(tooltipTriggerEl);
    });

    // Gestionar instalación de cloudflared
    const installCloudflaredBtn = document.getElementById('install-cloudflared-btn');
    if (installCloudflaredBtn) {
        installCloudflaredBtn.addEventListener('click', function() {
            const spinner = this.querySelector('.spinner-border');
            const text = this.querySelector('.btn-text');
            
            spinner.classList.remove('d-none');
            text.textContent = 'Instalando...';
            this.disabled = true;
        });
    }

    // Refresh de estado de túnel cada 30 segundos en la página de estado
    if (document.querySelector('.tunnel-status-card')) {
        setInterval(refreshTunnelStatus, 30000);
    }

    // Inicializar gráficos si estamos en la página de estado
    initializeCharts();

    // Validar formularios
    validateForms();
});

// Función para refrescar el estado de los túneles
function refreshTunnelStatus() {
    const tunnelCards = document.querySelectorAll('.tunnel-status-card');
    
    tunnelCards.forEach(card => {
        const tunnelName = card.getAttribute('data-tunnel-name');
        const statusBadge = card.querySelector('.status-badge');
        const connectivityBadge = card.querySelector('.connectivity-badge');
        const lastUpdated = card.querySelector('.last-updated');
        
        fetch(`/api/estado-tunel/${tunnelName}`)
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    // Actualizar el badge de estado
                    statusBadge.className = 'badge status-badge';
                    statusBadge.classList.add(data.status.running ? 'bg-success' : 'bg-danger');
                    statusBadge.textContent = data.status.running ? 'Activo' : 'Inactivo';
                    
                    // Actualizar el badge de conectividad
                    if (data.connectivity !== null) {
                        connectivityBadge.className = 'badge connectivity-badge';
                        connectivityBadge.classList.add(data.connectivity ? 'bg-success' : 'bg-warning');
                        connectivityBadge.textContent = data.connectivity ? 'Conectado' : 'Problemas de conectividad';
                    }
                    
                    // Actualizar fecha de último refresco
                    const now = new Date();
                    lastUpdated.textContent = 'Última actualización: ' + 
                        now.getHours().toString().padStart(2, '0') + ':' + 
                        now.getMinutes().toString().padStart(2, '0') + ':' + 
                        now.getSeconds().toString().padStart(2, '0');
                    
                    // Actualizar gráficos si hay métricas
                    if (data.metrics && window.tunnelCharts && window.tunnelCharts[tunnelName]) {
                        updateCharts(tunnelName, data.metrics);
                    }
                }
            })
            .catch(error => {
                console.error('Error al actualizar el estado del túnel:', error);
            });
    });
}

// Función para inicializar gráficos
function initializeCharts() {
    // Verificar si estamos en la página de estado y si Chart.js está disponible
    if (!document.querySelector('.tunnel-metrics') || typeof Chart === 'undefined') {
        return;
    }
    
    // Crear objeto global para almacenar referencias a los gráficos
    window.tunnelCharts = {};
    
    // Inicializar gráficos para cada túnel
    const metricContainers = document.querySelectorAll('.tunnel-metrics');
    
    metricContainers.forEach(container => {
        const tunnelName = container.getAttribute('data-tunnel-name');
        const canvasConnections = container.querySelector('.chart-connections');
        const canvasBandwidth = container.querySelector('.chart-bandwidth');
        
        if (canvasConnections) {
            window.tunnelCharts[tunnelName] = window.tunnelCharts[tunnelName] || {};
            window.tunnelCharts[tunnelName].connections = new Chart(canvasConnections, {
                type: 'line',
                data: {
                    labels: Array(10).fill(''),
                    datasets: [{
                        label: 'Conexiones',
                        data: Array(10).fill(0),
                        borderColor: '#0d6efd',
                        backgroundColor: 'rgba(13, 110, 253, 0.1)',
                        tension: 0.4,
                        fill: true
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        y: {
                            beginAtZero: true
                        }
                    },
                    plugins: {
                        legend: {
                            display: true
                        }
                    }
                }
            });
        }
        
        if (canvasBandwidth) {
            window.tunnelCharts[tunnelName] = window.tunnelCharts[tunnelName] || {};
            window.tunnelCharts[tunnelName].bandwidth = new Chart(canvasBandwidth, {
                type: 'line',
                data: {
                    labels: Array(10).fill(''),
                    datasets: [{
                        label: 'Subida (KB/s)',
                        data: Array(10).fill(0),
                        borderColor: '#198754',
                        backgroundColor: 'rgba(25, 135, 84, 0.1)',
                        tension: 0.4,
                        fill: true
                    }, {
                        label: 'Bajada (KB/s)',
                        data: Array(10).fill(0),
                        borderColor: '#dc3545',
                        backgroundColor: 'rgba(220, 53, 69, 0.1)',
                        tension: 0.4,
                        fill: true
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        y: {
                            beginAtZero: true
                        }
                    },
                    plugins: {
                        legend: {
                            display: true
                        }
                    }
                }
            });
        }
    });
}

// Función para actualizar los gráficos con nuevas métricas
function updateCharts(tunnelName, metrics) {
    if (!window.tunnelCharts || !window.tunnelCharts[tunnelName]) {
        return;
    }
    
    const charts = window.tunnelCharts[tunnelName];
    const now = new Date();
    const timeLabel = now.getHours().toString().padStart(2, '0') + ':' + 
                     now.getMinutes().toString().padStart(2, '0');
    
    // Actualizar gráfico de conexiones
    if (charts.connections && metrics.connections !== undefined) {
        const connectionsChart = charts.connections;
        connectionsChart.data.labels.push(timeLabel);
        connectionsChart.data.labels.shift();
        
        connectionsChart.data.datasets[0].data.push(metrics.connections);
        connectionsChart.data.datasets[0].data.shift();
        
        connectionsChart.update();
    }
    
    // Actualizar gráfico de ancho de banda
    if (charts.bandwidth && metrics.upload !== undefined && metrics.download !== undefined) {
        const bandwidthChart = charts.bandwidth;
        bandwidthChart.data.labels.push(timeLabel);
        bandwidthChart.data.labels.shift();
        
        // Convertir bytes/s a KB/s
        const uploadKB = metrics.upload / 1024;
        const downloadKB = metrics.download / 1024;
        
        bandwidthChart.data.datasets[0].data.push(uploadKB);
        bandwidthChart.data.datasets[0].data.shift();
        
        bandwidthChart.data.datasets[1].data.push(downloadKB);
        bandwidthChart.data.datasets[1].data.shift();
        
        bandwidthChart.update();
    }
}

// Función para validar formularios
function validateForms() {
    // Formulario de creación de túnel
    const createTunnelForm = document.getElementById('create-tunnel-form');
    if (createTunnelForm) {
        createTunnelForm.addEventListener('submit', function(event) {
            const tunnelName = this.querySelector('input[name="nombre_tunel"]');
            
            if (!tunnelName.value.trim()) {
                event.preventDefault();
                showValidationError(tunnelName, 'El nombre del túnel es obligatorio');
            } else {
                // Mostrar spinner durante el envío
                const submitBtn = this.querySelector('button[type="submit"]');
                submitBtn.innerHTML = '<span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span> Creando...';
                submitBtn.disabled = true;
            }
        });
    }
    
    // Formulario de añadir servicio
    const addServiceForm = document.getElementById('add-service-form');
    if (addServiceForm) {
        addServiceForm.addEventListener('submit', function(event) {
            let isValid = true;
            
            const serviceName = this.querySelector('input[name="service_name"]');
            const servicePort = this.querySelector('input[name="service_port"]');
            const domain = this.querySelector('input[name="domain"]');
            
            if (!serviceName.value.trim()) {
                isValid = false;
                showValidationError(serviceName, 'El nombre del servicio es obligatorio');
            }
            
            if (!servicePort.value.trim()) {
                isValid = false;
                showValidationError(servicePort, 'El puerto del servicio es obligatorio');
            } else if (!/^\d+$/.test(servicePort.value) || parseInt(servicePort.value) < 1 || parseInt(servicePort.value) > 65535) {
                isValid = false;
                showValidationError(servicePort, 'El puerto debe ser un número entre 1 y 65535');
            }
            
            if (!domain.value.trim()) {
                isValid = false;
                showValidationError(domain, 'El dominio es obligatorio');
            }
            
            if (!isValid) {
                event.preventDefault();
            } else {
                // Mostrar spinner durante el envío
                const submitBtn = this.querySelector('button[type="submit"]');
                submitBtn.innerHTML = '<span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span> Añadiendo...';
                submitBtn.disabled = true;
            }
        });
    }
}

// Función para mostrar errores de validación
function showValidationError(inputElement, message) {
    inputElement.classList.add('is-invalid');
    
    // Verificar si ya existe un div de feedback
    let feedback = inputElement.nextElementSibling;
    if (!feedback || !feedback.classList.contains('invalid-feedback')) {
        feedback = document.createElement('div');
        feedback.className = 'invalid-feedback';
        inputElement.parentNode.insertBefore(feedback, inputElement.nextSibling);
    }
    
    feedback.textContent = message;
    
    // Eliminar el estilo de error cuando el usuario comience a corregirlo
    inputElement.addEventListener('input', function() {
        this.classList.remove('is-invalid');
    }, { once: true });
}

// Función para confirmar eliminación
function confirmarEliminacion(formId, mensaje) {
    if (confirm(mensaje)) {
        document.getElementById(formId).submit();
    }
    return false;
}
