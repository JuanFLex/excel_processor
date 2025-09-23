#!/bin/bash

# Excel Processor - All Logs Monitor
# Uso: ./demo_logs.sh

echo "🎯 Excel Processor - All Development Logs"
echo "========================================="
echo ""
echo "🔍 Mostrando todos los logs de desarrollo..."
echo "Presiona Ctrl+C para salir"
echo ""

# Mostrar todos los logs con colores para diferentes tipos de mensajes
tail -f log/development.log | while read line; do
    if [[ $line == *"DEMO"* ]]; then
        # Mensajes DEMO en verde brillante
        echo -e "\033[1;32m$line\033[0m"
    elif [[ $line == *"AUTO-AI"* ]]; then
        # Mensajes AUTO-AI en azul brillante
        echo -e "\033[1;34m$line\033[0m"
    elif [[ $line == *"ERROR"* ]] || [[ $line == *"Error"* ]]; then
        # Errores en rojo
        echo -e "\033[1;31m$line\033[0m"
    elif [[ $line == *"TIMING"* ]]; then
        # Timing en amarillo
        echo -e "\033[1;33m$line\033[0m"
    elif [[ $line == *"EXPORT"* ]]; then
        # Export en magenta
        echo -e "\033[1;35m$line\033[0m"
    elif [[ $line == *"TopEarAnalyzerJob"* ]]; then
        # TopEarAnalyzerJob en cyan
        echo -e "\033[1;36m$line\033[0m"
    else
        # Otros mensajes en color normal
        echo "$line"
    fi
done