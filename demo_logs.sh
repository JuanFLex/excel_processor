#!/bin/bash

# Demo script para mostrar solo mensajes DEMO del Excel Processor
# Uso: ./demo_logs.sh

echo "🎯 Excel Processor - DEMO Messages Only"
echo "========================================"
echo ""
echo "🔍 Mostrando solo mensajes que contengan 'DEMO'..."
echo "Presiona Ctrl+C para salir"
echo ""

# Mostrar solo líneas que contengan DEMO
tail -f log/development.log | grep --line-buffered "DEMO" | while read line; do
    # Colorear los mensajes DEMO en verde brillante
    echo -e "\033[1;32m$line\033[0m"
done