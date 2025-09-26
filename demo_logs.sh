#!/bin/bash

# Excel Processor - Proposal Quotes Debug Monitor
# Uso: ./demo_logs.sh

echo "🎯 Excel Processor - Proposal Quotes Debug Logs"
echo "==============================================="
echo ""
echo "🔍 Filtrando logs de proposal quotes debug..."
echo "🎯 Buscando específicamente: DFS-640N0203"
echo "Presiona Ctrl+C para salir"
echo ""

# Filtrar y colorear logs específicos de proposal quotes
tail -f log/development.log | grep -E "(DEBUG CACHE|DEBUG QUOTE|DEBUG EXCEL|DFS-640N0203|Proposal quotes cache loaded|Processing item.*DFS|Proposal result.*DFS)" | while read line; do
    if [[ $line == *"DEBUG CACHE"* ]]; then
        # Logs de cache en verde brillante
        echo -e "\033[1;32m$line\033[0m"
    elif [[ $line == *"DEBUG QUOTE"* ]] && [[ $line == *"Found"* ]]; then
        # Item encontrado en cache - verde
        echo -e "\033[1;32m$line\033[0m"
    elif [[ $line == *"DEBUG QUOTE"* ]] && [[ $line == *"NOT in cache"* ]]; then
        # Item NO encontrado en cache - rojo
        echo -e "\033[1;31m$line\033[0m"
    elif [[ $line == *"DEBUG QUOTE"* ]]; then
        # Otros logs de quote en cyan
        echo -e "\033[1;36m$line\033[0m"
    elif [[ $line == *"DFS-640N0203"* ]]; then
        # Cualquier mención de DFS-640N0203 en amarillo brillante
        echo -e "\033[1;33m$line\033[0m"
    elif [[ $line == *"Processing item"* ]]; then
        # Processing item en azul
        echo -e "\033[1;34m$line\033[0m"
    elif [[ $line == *"Proposal result"* ]] && [[ $line == *"YES"* ]]; then
        # Resultado YES en verde
        echo -e "\033[1;32m$line\033[0m"
    elif [[ $line == *"Proposal result"* ]] && [[ $line == *"NO"* ]]; then
        # Resultado NO en rojo
        echo -e "\033[1;31m$line\033[0m"
    elif [[ $line == *"cache loaded"* ]]; then
        # Cache loaded en magenta
        echo -e "\033[1;35m$line\033[0m"
    else
        # Otros mensajes en color normal
        echo "$line"
    fi
done