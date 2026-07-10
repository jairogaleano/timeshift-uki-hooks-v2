#!/bin/bash
#
# Timeshift UKI Hooks - Instalador v2.4
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta como root (sudo ./install.sh)"
  exit 1
fi

echo "Verificando dependencias del sistema..."
DEPENDENCIES=("findmnt" "mountpoint" "sha256sum" "df")
MISSING_DEPS=()

for dep in "${DEPENDENCIES[@]}"; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    MISSING_DEPS+=("$dep")
  fi
done

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
  echo "Error: Faltan las siguientes dependencias necesarias: ${MISSING_DEPS[*]}"
  echo "Por favor, instálalas antes de continuar."
  exit 1
fi
echo "Todas las dependencias encontradas."

echo "Instalando Timeshift UKI Hooks v2.4..."

# Crear directorios si no existen
mkdir -p /etc/timeshift/backup-hooks.d
mkdir -p /etc/timeshift/restore-hooks.d

# Limpiar versiones anteriores (incluyendo archivos con sufijos de versión)
echo "Limpiando instalaciones previas y experimentos de nombres..."
rm -f /etc/timeshift/backup-hooks.d/90-backup-uki*
rm -f /etc/timeshift/restore-hooks.d/90-restore-uki*

# Copiar scripts con nombres estándar
echo "Copiando scripts..."
cp "$SCRIPT_DIR/hooks.d/backup/90-backup-uki" /etc/timeshift/backup-hooks.d/
cp "$SCRIPT_DIR/hooks.d/restore/90-restore-uki" /etc/timeshift/restore-hooks.d/

# Aplicar permisos
echo "Aplicando permisos de ejecución..."
chmod +x /etc/timeshift/backup-hooks.d/90-backup-uki
chmod +x /etc/timeshift/restore-hooks.d/90-restore-uki

echo "Instalacion/Actualizacion a v2.4 completada correctamente."
echo "Los hooks han sido instalados con nombres estándar para compatibilidad con run-parts."
