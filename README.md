# Timeshift UKI Hooks v2.4

Sistema de hooks para **Timeshift** que respalda y restaura imágenes **UKI (Unified Kernel Images)** en sistemas con **Btrfs + Secure Boot**.

## 📋 Tabla de Contenidos

- [Concepto](#concepto)
- [¿Por qué es necesario?](#por-qué-es-necesario)
- [Cómo funciona](#cómo-funciona)
- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Novedades en v2.4](#novedades-en-v24)
- [Novedades en v2.3](#novedades-en-v23)
- [Seguridad](#seguridad)
- [Depuración e Integración de Logs](#depuración-e-integración-de-logs)
- [Licencia](#licencia)

---

## 🔍 Concepto

En sistemas Arch Linux con **systemd-boot** y **Secure Boot**, las imágenes UKI (ficheros `.efi`) residen en la partición **EFI System Partition (ESP)**.

**El problema**: Timeshift protege la raíz (`/`), pero la partición ESP queda fuera. Si restauras un snapshot antiguo, el kernel en `/` (módulos) y el UKI en la ESP (kernel binario) no coincidirán, impidiendo el arranque o el funcionamiento de módulos.

---

## 🎯 Solución

Este proyecto sincroniza los UKIs con los snapshots de Btrfs mediante hooks:

1. **Backup Hook** (`/etc/timeshift/backup-hooks.d/90-backup-uki`)
   - Se ejecuta **antes** de crear el snapshot
   - Detecta dinámicamente la ESP con `findmnt` (soporta `/boot`, `/efi`, `/boot/efi`)
   - Respalda UKIs en `/etc/timeshift/uki-backup/` (dentro del snapshot)
   - **Selectivo**: solo copia UKIs que cambiaron (comparación SHA256 per-file)
   - Limpia archivos `.sha256` huérfanos automáticamente

2. **Restore Hook** (`/etc/timeshift/restore-hooks.d/90-restore-uki`)
   - Se ejecuta **después** de restaurar
   - Detecta y monta la ESP dinámicamente (incluso en entornos chroot/Live USB)
   - Verifica espacio disponible antes de copiar
   - Devuelve los UKIs a la ESP con copia atómica (`mktemp + mv`)
   - **Inteligente**: salta archivos que ya son idénticos

---

## 📦 Instalación

Hemos simplificado la instalación con un script dedicado:

```bash
git clone https://github.com/jairogaleano/timeshift-uki-hooks-v2.git
cd timeshift-uki-hooks-v2
sudo chmod +x install.sh
sudo ./install.sh
```

El instalador se encarga de:
1. Crear los directorios de hooks.
2. Limpiar versiones anteriores.
3. Instalar los scripts con nombres canónicos para compatibilidad con `run-parts`.
4. Aplicar permisos de ejecución.

---

## ✨ Novedades en v2.4

- **ESP dinámica**: Los hooks ya no dependen de rutas fijas. Detectan automáticamente
  el punto de montaje de la partición EFI via `findmnt -t vfat`, soportando
  cualquier configuración (`/boot`, `/efi`, `/boot/efi`, montajes custom).
- **Soporte chroot/Live USB**: El restore hook detecta cuando se ejecuta dentro
  de un entorno chroot (`systemd-detect-virt --chroot`) y monta la ESP
  automáticamente si no lo está. Esto permite restauraciones desde Live USB.
- **Verificación de espacio**: El restore hook comprueba que haya al menos 50MB
  libres en la ESP antes de copiar, con advertencia si el espacio es crítico.
- **Limpieza de huérfanos**: Ambos hooks limpian archivos `.sha256` que ya no
  tienen su UKI correspondiente en el directorio de respaldo.
- **Copia selectiva completa**: El backup hook itera todos los UKIs y solo
  respalda los que realmente cambiaron (SHA256 per-file), sin el antiguo
  comportamiento de "break al primer cambio".

## ✨ Novedades en v2.3

- **Backup hook**: Eliminada rotación de backups (`.bak`) que acumulaba archivos
  sin límite en cada snapshot.
- **Backup hook**: Eliminado bloque duplicado de verificación de directorio
  (código muerto).
- **Install.sh**: Agregado `SCRIPT_DIR` para rutas absolutas, ahora funciona
  desde cualquier directorio.
- **AUR**: Actualizado `.SRCINFO` y `PKGBUILD` a v2.3.

## ✨ Novedades en v2.2

- **Fix crítico**: Variable `expected_sha` inicializada correctamente para evitar `unbound variable` en restore hook.
- **Seguridad**: Uso de `mktemp` en vez de `$$` para archivos temporales en restore hook.
- **Skip condicional**: La comparación de checksums en restore salta archivos solo cuando SHA256 está disponible.
- **Limpieza**: Eliminada variable `skipped_count` sin uso y redirección redundante en restore hook.

---

## 🔒 Seguridad

- ✅ **Integridad**: Verificación SHA256 obligatoria antes de restaurar.
- ✅ **Atomicidad**: Uso de copias temporales y `mv` para evitar archivos corruptos.
- ✅ **Secure Boot**: No modifica firmas; solo preserva los binarios ya firmados.

---

## 🔧 Depuración e Integración de Logs

Este proyecto se integra directamente con el sistema de registros de **Timeshift** para facilitar el mantenimiento y la visibilidad:

- **Logs Unificados**: Los mensajes de los hooks se inyectan en `/var/log/timeshift.log`. Esto permite ver en un solo lugar tanto las acciones de Timeshift como el estado de la sincronización de los UKIs.
- **Rotación Automática**: Timeshift gestiona internamente la limpieza y rotación de estos logs (manteniendo las últimas sesiones). Al integrarse aquí, los registros de este proyecto se depuran automáticamente, evitando el crecimiento indefinido de archivos en `/var/log`.
- **Enlace Simbólico**: El script escribe en `/var/log/timeshift.log`, que es el puntero estándar de Timeshift hacia el log de la ejecución actual.

Ver logs en tiempo real:
```bash
tail -f /var/log/timeshift.log
```

---

## 📄 Licencia

Este software está bajo la licencia **GNU General Public License v3.0**.

**Contribuciones**: Proyecto mantenido por Jairo Galeano.
