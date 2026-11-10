#!/usr/bin/env bash
# flash.sh - grava o tracker completo no Air780EG via ectool
#
# Antes de rodar:
#   1. Coloque o dongle em modo BOOT download (segure BOOT e energize).
#   2. Confirme que apareceu APENAS 1 porta /dev/ttyUSB* (modo download).
#      Antes do BOOT são 4 portas; em BOOT fica 1.
#
# Uso: ./tools/flash.sh [porta_ttyUSB]

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

SOC="build/fufu_tracker.soc"
SCRIPT_BIN="build/script.bin"

if [ ! -f "$SOC" ]; then
    echo "ERRO: $SOC não encontrado. Rode primeiro tools/mk_soc.py"
    exit 1
fi

if [ ! -f "$SCRIPT_BIN" ]; then
    echo "ERRO: $SCRIPT_BIN não encontrado. Rode primeiro tools/mk_luadb.py"
    exit 1
fi

PORT="${1:-}"
if [ -z "$PORT" ]; then
    echo "Aguardando dongle em modo BOOT (1 porta ttyUSB)..."
    echo "Pressione Ctrl+C para cancelar."
    while true; do
        PUERTAS=$(ls /dev/ttyUSB* 2>/dev/null | wc -l)
        if [ "$PUERTAS" -eq 1 ]; then
            PORT=$(ls /dev/ttyUSB*)
            echo "Porta BOOT detectada: $PORT"
            break
        fi
        if [ "$PUERTAS" -gt 0 ] && [ "$PUERTAS" -ne 1 ]; then
            echo "Ainda em modo normal ($PUERTAS portas). Coloque o dongle em BOOT."
        fi
        sleep 2
    done
fi

echo "Gravando $SOC em $PORT (escopo completo: AgentBoot+BL+AP+CP+script)..."
python -m ectool burn -f "$SOC" -p "$PORT" \
    --burn_agent y --burn_bl y --burn_ap y --burn_cp y --burn_script y --sysreset

echo "Burn concluído. O dongle reiniciará e voltará às 4 portas normais."
