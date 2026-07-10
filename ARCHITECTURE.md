# Arquitectura de Timeshift UKI Hooks

## Alcance de los scripts

Son dos hooks que integran UKIs (Unified Kernel Images) con el sistema de snapshots Btrfs de Timeshift. Resuelven un problema de desajuste: Timeshift protege `/` pero la particion **ESP** (donde estan los UKIs `.efi`) queda fuera de los snapshots.

---

## Backup Hook (`90-backup-uki`)

Se ejecuta **antes** de cada snapshot. Su funcion es copiar los UKIs actuales desde la ESP a `/etc/timeshift/uki-backup/`. Como `/etc` esta dentro de la raiz Btrfs, los UKIs quedan **incluidos en el snapshot**.

Selecciona archivos `.efi` del directorio `EFI/Linux` en la ESP. Para cada uno calcula SHA256: si ya existe un respaldo identico en `uki-backup/`, lo salta; si cambio, lo copia y escribe su `.sha256`. Antes de copiar, limpia archivos `.sha256` huerfanos (cuyo UKI ya no existe en la ESP).

### Cobertura de escenarios

| Escenario | Comportamiento |
|---|---|
| Normal (snapshot periodico) | Copia solo UKIs cambiados a `uki-backup/`. El snapshot contiene modulos + UKI consistentes. |
| Sin cambios entre snapshots | Omite copia (SHA256 match). Cero I/O innecesario. |
| ESP montada en `/boot`, `/efi` o `/boot/efi` | Detecta dinamicamente con `findmnt -t vfat` + `EFI/Linux`. |
| Sin UKIs en ESP | Log WARN y sale con 0 (no bloquea el snapshot). |

---

## Restore Hook (`90-restore-uki`)

Se ejecuta **despues** de restaurar un snapshot. Recupera los UKIs de `uki-backup/` (que estan dentro del snapshot restaurado) y los escribe de vuelta en la ESP, asegurando que coincidan con los modulos del kernel recien restaurados.

Por cada UKI respaldado verifica su checksum SHA256 contra el `.sha256` acompanante. Si coincide el checksum y ya existe un UKI identico en el destino, lo salta. Si no, copia atomicamente: escribe a un archivo temporal con `mktemp`, verifica, luego `mv`. Verifica espacio disponible en ESP (min. 50MB). Usa `trap cleanup EXIT` que desmonta la ESP si fue montada manualmente o restaura el modo RO original.

### Cobertura de escenarios

| Escenario | Comportamiento |
|---|---|
| **Normal**: restauracion desde el sistema arrancado | ESP ya montada en `/boot` o `/efi`. Restaura solo UKIs distintos. |
| **Falla tras actualizacion de kernel**: el usuario restaura un snapshot anterior para revertir | El hook coloca en la ESP los UKIs de la version anterior (los que estaban en el snapshot). Al reiniciar, kernel + modulos + UKI estan sincronizados. |
| **Peor caso: sistema no arranca** (kernel corrupto, UKI danado, Secure Boot falla) | El usuario arranca desde un Live USB, monta su particion Btrfs, hace chroot, ejecuta Timeshift restore. El hook detecta el chroot con `systemd-detect-virt`, busca la particion EFI por PARTTYPE GUID (`c12a7328-f81f-11d2-ba4b-00a0c93ec93b`) via `lsblk`/`blkid`, la monta en `/tmp/esp-mount-XXXXXXXX`, restaura los UKIs y la desmonta al salir (trap). El usuario sale del chroot, reinicia y el sistema arranca con la version anterior. |
| **ESP montada RO** | Detecta `findmnt -O ro`, remonta RW, restaura, trap devuelve a RO. |
| Multiples ESPs | Toma la primera particion con PARTTYPE EFI. |

---

## Diagrama de flujo restore

```
Restore Timeshift
       |
       v
resolve_esp_mount()
  +- ?/boot montado?   -> si -> TARGET_MNT=/boot
  +- ?/efi montado?    -> si -> TARGET_MNT=/efi
  +- ?findmnt vfat?    -> si -> TARGET_MNT=resultado
  +- NO -> intenta montar /boot /efi /boot/efi
             |
             v
        ?sigues sin TARGET_MNT?
             |
             v
        Busca ESP por PARTTYPE GUID
        +- ?lsblk/blkid encuentra dispositivo?
             +- si -> mount en /tmp/esp-mount-XXXX
             |       ESP_MOUNTED_BY_US=true
             +- no -> ERROR + si chroot: mensaje ayuda
                      exit 1
             |
             v
        findmnt -O ro TARGET_MNT
        +- si -> remount,rw ; WAS_RO=true
             |
             v
        Verifica backup_ukis, SHA256, espacio
             |
             v
        Por cada UKI: cp atomico a EFI/Linux/
             |
             v
        trap EXIT
        +- ?ESP_MOUNTED_BY_US? -> umount + rmdir
        +- ?WAS_RO? -> remount,ro
```

---

## Resumen

Los scripts convierten un punto ciego de Timeshift (la ESP fuera de los snapshots) en un proceso automatizado y seguro. En uso normal son invisibles; en una reversion de kernel aseguran que el UKI coincida con los modulos; y en el peor caso (sistema inservible) permiten restaurar desde Live USB con deteccion y montaje automatico de la particion EFI.
