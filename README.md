# Timeshift UKI Hooks v2

Sistema de hooks para **Timeshift** que respalda y restaura imágenes **UKI (Unified Kernel Images)** en sistemas con **Btrfs + Secure Boot**.

## 📋 Tabla de Contenidos

- [Concepto](#concepto)
- [¿Por qué es necesario?](#por-qué-es-necesario)
- [Cómo funciona](#cómo-funciona)
- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Diferencias con v1](#diferencias-con-v1)
- [Seguridad](#seguridad)
- [Depuración](#depuración)
- [Licencia](#licencia)

---

## 🔍 Concepto

En sistemas Arch Linux con **systemd-boot** y **Secure Boot**, las imágenes UKI (ficheros `.efi`) residen en la partición **EFI System Partition (ESP)**, típicamente montada en `/boot/EFI/Linux` o `/efi/EFI/Linux`.

Cuando usas **Timeshift** con **Btrfs**, el sistema crea snapshots que protegen la partición raíz (`/`), pero **la partición ESP queda fuera** del snapshot porque es FAT32 y está en un dispositivo diferente.

**El problema**: Si restauras un snapshot de hace 30 días que contiene kernel 6.9.x, pero tu ESP still tiene un UKI firmado para kernel 6.10.x, el sistema arrancará pero fallará al cargar los módulos porque no coinciden con el kernel restaurado.

---

## 🎯 Solución

Este proyecto proporciona hooks para **Timeshift** que sincronizan los UKIs con los snapshots de Btrfs:

1. **Backup Hook** (`/etc/timeshift/backup-hooks.d/90-backup-uki`)
   - Se ejecuta **antes** de crear el snapshot
   - Copia los UKIs actuales a `/etc/timeshift/uki-backup/`
   - Calcula checksums SHA256 para verificación futura
   - Los UKIs se incluyen en el snapshot de Btrfs (porque `/etc` está dentro de `/`)

2. **Restore Hook** (`/etc/timeshift/restore-hooks.d/90-restore-uki`)
   - Se ejecuta **después** de restaurar un snapshot
   - Recupera los UKIs respaldados y los devuelve a la partición ESP
   - Verifica checksums para garantizar integridad
   - Usa copias atómicas para evitar estados parciales

---

## 🔄 Cómo funciona (Diagrama de Flujo)

```
┌─────────────────────────────────────────────────────────────┐
│                    Timeshift ejecuta_snapshot                │
└─────────────────┬───────┬─────────────────────┬─────────────┘
                  │       │                     │
                  ▼       ▼                     ▼
        ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐
        │ Backup Hook     │  │ Btrfs Snapshot  │  │ Restore Hook │
        │ (antes)         │  │ (crea snapshot) │  │ (después)    │
        │ - UKIs → /etc   │  │ - Incluye /etc  │  │ - UKIs ↓ ESP │
        │ - SHA256 calcul │  │ - UKIs protegidos│ │ - Verif SHA256 │
        └────────┬────────┘  └─────────────────┘  └──────────────┘
                 │                                   │
                 └───────────────────────────────────┘
                              (mismo snapshot)
```

### Momento a momento:

| Tiempo | Acción | ¿Qué protege? |
|--------|--------|---------------|
| **T-1min** | Backup Hook ejecuta | UKIs actuales → `/etc/timeshift/uki-backup` |
| **T=0** | Timeshift crea snapshot | Snapshot incluye `/etc` → UKIs incluidos |
| **T=+1min** | Restore Hook ejecuta | UKIs desde snapshot → ESP |

---

## 📋 Requisitos

### Sistema
- **Distribución**: Arch Linux o derivada
- **Arranque**: systemd-boot con UKIs
- **Filesystem**: Btrfs con snapshots (Timeshift)
- **Secure Boot**: Activado (SBCTL o MOK)

### Archivos de UKI
- UKIs ubicados en `/boot/EFI/Linux` **o** `/efi/EFI/Linux`

### Permisos
- Scripts ejecutados como **root** (Timeshift requirement)
- ESP montable con `mount` (si está RO, se remonta a RW temporalmente)

### Timeshift
- `timeshift` instalado
- `timeshift-autosnap` (opcional, para automatización en actualizaciones)

---

## 📦 Instalación

### 1. Copiar los scripts

```bash
sudo mkdir -p /etc/timeshift/backup-hooks.d
sudo mkdir -p /etc/timeshift/restore-hooks.d

sudo cp hooks.d/backup/90-backup-uki /etc/timeshift/backup-hooks.d/90-backup-uki
sudo cp hooks.d/restore/90-restore-uki /etc/timeshift/restore-hooks.d/90-restore-uki

sudo chmod +x /etc/timeshift/backup-hooks.d/90-backup-uki
sudo chmod +x /etc/timeshift/restore-hooks.d/90-restore-uki
```

### 2. Verificar instalación

```bash
# Verificar que los hooks existen
ls -la /etc/timeshift/backup-hooks.d/90-backup-uki
ls -la /etc/timeshift/restore-hooks.d/90-restore-uki

# Verificar que Timeshift los detecta
timeshift --list
```

### 3. Prueba (opcional)

```bash
# Simular una restauración para verificar que el hook funciona
sudo timeshift --restore --dry-run --snapshot <nombre-snapshot>
```

---

## 🆚 Diferencias con v1

| Característica | v1 (anterior) | v2 (actual) |
|----------------|---------------|-------------|
| **Checksums** | ❌ No | ✅ SHA256 por archivo |
| **Logging** | ❌ Solo stdout | ✅ `/var/log/timeshift.log` |
| **Atomicidad** | ❌ Copia directa `cp` | ✅ `cp temp → mv` |
| **Rotación** | ❌ Borra todo antes | ✅ Timestamps en nombres |
| **Verificación** | ❌ Solo verifica existencia | ✅ Verifica checksums antes de copiar |
| **Detección de errores** | ⚠️ Básica | ✅ `set -euo pipefail` |

### Mejoras clave:

1. **Integridad verificada**:
   ```bash
   # v1
   cp "$uki" "$BACKUP_DIR/"
   
   # v2
   cp "$uki" "$BACKUP_DIR/$basename"
   sha256sum "$uki" > "$BACKUP_DIR/$basename.sha256"
   # Restore: verifica checksums antes de copiar
   ```

2. **Copias atómicas**:
   ```bash
   # v1 (riesgo: copia parcial)
   cp "$BACKUP_DIR/*.efi" "$UKI_DIR/"
   
   # v2 (seguro: solo move si copia completa)
   temp="$UKI_DIR/.tmp_$$"
   cp "$uki_backup" "$temp"
   mv "$temp" "$UKI_DIR/$basename"
   ```

3. **Logging estructurado**:
   ```bash
   # v1
   echo "[UKI Backup Hook] Archivos copiados exitosamente"
   
   # v2
   log "INFO" "SHA256 verificado para $basename"
   echo "[$(date)] [UKI Backup Hook] [INFO] $message" >> /var/log/timeshift.log
   ```

---

## 🔒 Seguridad

### Secure Boot
- ✅ Los UKIs ya están **firmados y verificados** por Secure Boot antes de ejecutarse
- ✅ Los hooks **solo copian archivos existentes** - no modifican firmas
- ✅ No hay riesgo de inyección de código malicioso (igual que v1)

### Verificación de integridad (v2)
- ✅ SHA256 calculado durante backup
- ✅ SHA256 verificado durante restore
- ✅ Si el checksum falla → restore aborta → Timeshift marca error
- ✅ ESP no se corrompe (nunca se copia con checksum inválido)

### Confiabilidad
- ✅ **Backup falla** → Timeshift continúa, solo no hay respaldo (no afecta arranque)
- ✅ **Restore falla** → Timeshift marca error, usuario puede retry (no arranca mal)
- ✅ **Copia parcial** → se detecta y aborta antes de afectar ESP

---

## 🔧 Depuración

### Ver logs en tiempo real
```bash
sudo journalctl -f -u timeshift
# o directamente
tail -f /var/log/timeshift.log
```

### Verificar hook individualmente

```bash
# Test backup (sin Timeshift)
sudo /etc/timeshift/backup-hooks.d/90-backup-uki
echo "Exit code: $?"

# Test restore (sin Timeshift)
sudo /etc/timeshift/restore-hooks.d/90-restore-uki
echo "Exit code: $?"
```

### Problemas comunes

| Error | Causa | Solución |
|-------|-------|----------|
| `No se encontraron UKIs` | Directorio `/boot/EFI/Linux` o `/efi/EFI/Linux` no existe | Verificar ubicación de UKIs con `ls /boot/EFI/Linux` |
| `No se pudo montar /boot` | ESP no montado y permissions insuficientes | Verificar `/etc/fstab` y permisos de montaje |
| `Checksum falló` | Archivo corrupto o modificado entre backup y restore | Verificar integridad con `sha256sum -c` |
| `No se pudo remontar RW` | Sistema de archivos readonly sin modo de recuperación | Verificar `/dev/disk/by-uuid/...` y options de montaje |

---

## 📊 Estructura de archivo

```
hooks.d/
├── backup/90-backup-uki      # Hook de respaldo (ejecuta antes de snapshot)
└── restore/90-restore-uki    # Hook de restauración (ejecuta después de restore)
```

### Nombres de archivos en backup

Después de múltiples snapshots, `/etc/timeshift/uki-backup/` contendrá:

```
uki-file-name.efi                  # UKI actual
uki-file-name.bak.1718273654.efi   # UKI anterior (rotado)
uki-file-name.bak.1718187234.efi   # UKI aún más antiguo
uki-file-name.sha256              # Checksum actual
uki-file-name.bak.1718273654.sha256
uki-file-name.bak.1718187234.sha256
```

---

## 🤝 Contribuciones

Este proyecto nació de la necesidad de Jairo Galeano en sistemas Arch Linux con:
- Raspberry Pi 3B como servidor
- ASROCK (estación principal)
- ThinkPad L15 G4 (apoyo móvil)

Todos con Btrfs + Timeshift + Secure Boot.

---

## 📄 Licencia

Este software está bajo la licencia **GNU General Public License v3.0**. Consulta el archivo `LICENSE` para más detalles.

**Avisos**: 
- No me hago responsable de daños en el sistema.
- Siempre verificar logs después de actualizaciones críticas.
- Si el hook falla, el sistema no arrancará (Timeshift marcará error).

---

**Uso bajo tu propio riesgo**. Hacer backups antes de actualizaciones grandes siempre es una buena práctica 🛡️
