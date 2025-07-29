#!/bin/bash

# Demo script para mostrar logs humanizados del Excel Processor
# Uso: ./demo_logs.sh

echo "🎯 Excel Processor - Live Demo Logs"
echo "====================================="
echo ""

# Función para mostrar logs con colores
show_logs() {
    tail -f log/development.log | while read line; do
        # Timestamps en verde
        if [[ $line =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
            echo -e "\033[32m$line\033[0m"
        # Errores en rojo
        elif [[ $line =~ ERROR|error|Error ]]; then
            echo -e "\033[31m$line\033[0m"
        # INFO en azul
        elif [[ $line =~ INFO|info|Info ]]; then
            echo -e "\033[34m$line\033[0m"
        # SQL queries en amarillo
        elif [[ $line =~ SELECT|INSERT|UPDATE|DELETE ]]; then
            echo -e "\033[33m$line\033[0m"
        # Procesamiento en magenta
        elif [[ $line =~ Processing|Completed|Started ]]; then
            echo -e "\033[35m$line\033[0m"
        else
            echo "$line"
        fi
    done
}

echo "📊 Iniciando monitoreo de logs en tiempo real..."
echo "Presiona Ctrl+C para salir"
echo ""

show_logs