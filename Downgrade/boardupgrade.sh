#!/bin/sh
#

# R3600 upgrade file (angepasst für erzwungenes Downgrade ohne Netzwerk-Ausfall)

. /lib/upgrade/libupgrade.sh

klogger() {
    local msg1="$1"
    local msg2="$2"

    if [ "$msg1" = "-n" ]; then
        echo -n "$msg2" >> /dev/kmsg 2>/dev/null
        echo -n "$msg2"
    else
        echo "$msg1" >> /dev/kmsg 2>/dev/null
        echo "$msg1"
    fi

    return 0
}

################################################################################
# board_prepare_upgrade:
#   Wir entfernen hier alles, was Netzwerk-Interfaces oder systemweite Dienste
#   stoppte und damit SSH-Verbindungen gekillt hat. So bleibt SSH bestehen, bis
#   board_system_upgrade() tatsächlich beginnt.
################################################################################
board_prepare_upgrade() {
    klogger "@Downgrade: Bereite Upgrade-Umgebung vor – stoppe keine Netzwerk- oder Systemdienste"

    # Nur Cache flush und Meminfo dump (ohne ifdown, ohne rc.d-Loop)
    sync
    echo 3 >/proc/sys/vm/drop_caches
    klogger "@dump meminfo"
    klogger "`cat /proc/meminfo | xargs`"
}

################################################################################
# board_start_upgrade_led:
#   Schaltet die OTA-LED ein (bleibt unverändert).
################################################################################
board_start_upgrade_led() {
    /usr/sbin/xqled sys_ota > /dev/null 2>&1
}

################################################################################
# upgrade_full_image:
#   Brennt das komplette Modem-Image (falls im Paket enthalten).
################################################################################
upgrade_full_image() {
    local package=$1
    local segment_name="modem_image.zip"

    mkxqimage -c $package -f $segment_name
    if [ $? -ne 0 ]; then
        klogger "Kein modem full Image im Paket gefunden (oder ungültiges Format)"
        return 1
    fi

    cd /tmp/system_upgrade/
    mkdir -p modem_image
    mkxqimage -x $package -f $segment_name
    unzip -o -d /tmp/system_upgrade/modem_image $segment_name
    QFirehose -n -f /tmp/system_upgrade/modem_image
    if [ $? -eq 0 ]; then
        klogger "Modem-Full-Image erfolgreich geflasht"
        return 0
    else
        klogger "Fehler beim Flashen des Modem-Full-Images"
        return 1
    fi
}

################################################################################
# upgrade_diff_image:
#   Brennt ein differenzielles (diff) Modem-Image.
################################################################################
upgrade_diff_image() {
    local package=$1
    local segment_name="modem_image.zip"

    mkxqimage -c $package -f $segment_name
    if [ $? -ne 0 ]; then
        klogger "Kein modem diff Image im Paket gefunden (oder ungültiges Format)"
        return 1
    fi

    cd /tmp/system_upgrade/
    mkxqimage -x $package -f $segment_name
    quectel_fota -d $segment_name
    if [ $? -eq 0 ]; then
        klogger "Modem-Diff-Image erfolgreich geflasht"
        return 0
    else
        klogger "Fehler beim Flashen des Modem-Diff-Images"
        return 1
    fi
}

################################################################################
# upgrade_fota_image:
#   Brennt ein FOTA-Modem-Image.
################################################################################
upgrade_fota_image() {
    local package=$1
    local segment_name="modem_image.zip"

    mkxqimage -c $package -f $segment_name
    if [ $? -ne 0 ]; then
        klogger "Kein modem FOTA-Image im Paket gefunden (oder ungültiges Format)"
        return 1
    fi

    cd /tmp/system_upgrade/
    mkxqimage -x $package -f $segment_name
    quectel_fota -f $segment_name
    if [ $? -eq 0 ]; then
        klogger "Modem-FOTA-Image erfolgreich geflasht"
        return 0
    else
        klogger "Fehler beim Flashen des Modem-FOTA-Images"
        return 0
    fi
}

################################################################################
# board_system_upgrade:
#   Überspringt alle Versionschecks und führt direkt den Flash aller Komponenten durch.
################################################################################
board_system_upgrade() {
    local filename=$1

    cd /tmp/system_upgrade

    klogger "Downgrade-Modus: Überspringe Versionsverifikation im boardupgrade"

    # 1) Modem-Image (falls enthalten, anhand IMAGE_MODULE und IMAGE_TYPE)
    mkxqimage -V $filename > /tmp/system_upgrade/xiaoqiang_version
    local image_module=$(grep IMAGE_MODULE /tmp/system_upgrade/xiaoqiang_version | awk '{print $3}' | tr -d "'")
    local image_type=$(grep IMAGE_TYPE /tmp/system_upgrade/xiaoqiang_version | awk '{print $3}' | tr -d "'")

    if [ "$image_module" = "1" ] || [ "$image_module" = "2" ]; then
        if [ "$image_type" = "2" ]; then
            klogger "Downgrade-Modus: Flashen des Modem-FOTA-Images"
            upgrade_fota_image $filename
            if [ $? -ne 0 ]; then
                klogger "Fehler beim Flashen des Modem-FOTA-Images, Abbruch."
                #return 1
            fi
        elif [ "$image_type" = "1" ]; then
            klogger "Downgrade-Modus: Flashen des Modem-Full-Images"
            upgrade_full_image $filename
            if [ $? -ne 0 ]; then
                klogger "Fehler beim Flashen des Modem-Full-Images, Abbruch."
                #return 1
            fi
        elif [ "$image_type" = "0" ]; then
            klogger "Downgrade-Modus: Flashen des Modem-Diff-Images"
            upgrade_diff_image $filename
            if [ $? -ne 0 ]; then
                klogger "Fehler beim Flashen des Modem-Diff-Images, Abbruch."
                #return 1
            fi
        else
            klogger "Unbekannter Modem-Image-Typ: $image_type, überspringe Modem-Flash."
        fi

        # Wenn nur Modem-Image (IMAGE_MODULE=1), dann Ende.
        #if [ "$image_module" = "1" ]; then
        #    return 0
        #fi
        # Bei IMAGE_MODULE=2 (beides), danach Router-Sektionen flashen.
    fi

    # 2) Router-Sektionen: sbl1, tz, devcfg, cdt, uboot, firmware
    local secList="sbl1 tz devcfg cdt uboot firmware"
    for sec in $secList; do
        klogger "Flashing Section: $sec"
        flash_section $sec $filename
        if [ $? -ne 0 ]; then
            klogger "Fehler beim Flashen von $sec, Abbruch."
            return 1
        fi
    done

    # 3) Bootconfig-Update, falls gesetzt
    if [ -f "/tmp/bootconfig_update_needed" ]; then
        klogger "Aktualisiere Bootconfig"
        update_bootconfig
        rm -f "/tmp/bootconfig_update_needed"
    fi

    # 4) Backup von /etc
    klogger "Backup der /etc-Konfiguration"
    rm -rf /data/etc_bak
    cp -prf /etc /data/etc_bak

    return 0
}

################################################################################
# flash_section:
#   Leitet jede Section an die jeweilige do_flash_<…>()-Funktion weiter.
################################################################################
flash_section() {
    local sec=$1
    local package=$2

    case "${sec}" in
        sbl1*)    do_flash_sbl1 $package ;;
        tz*)      do_flash_tz $package ;;
        devcfg*)  do_flash_devcfg $package ;;
        cdt*)     do_flash_ddr $package ;;
        uboot*)   do_flash_uboot $package ;;
        firmware*) do_flash_firmware $package ;;
        *)        echo "Section ${sec} ignored"; return 1 ;;
    esac
}

################################################################################
# update_bootconfig:
#   Schreibt bootconfig und bootconfig1, falls nötig.
################################################################################
update_bootconfig() {
    do_flash_bootconfig bootconfig "0:BOOTCONFIG"
    if [ $? -eq 0 ]; then
        klogger "Bootconfig erfolgreich geflasht"
    else
        klogger "Fehler beim Flashen von Bootconfig"
        uperr
    fi

    do_flash_bootconfig bootconfig1 "0:BOOTCONFIG1"
    if [ $? -eq 0 ]; then
        klogger "Bootconfig1 erfolgreich geflasht"
    else
        klogger "Fehler beim Flashen von Bootconfig1"
        uperr
    fi
}

################################################################################
# do_flash_failsafe_partition:
#   Allgemeine Funktion, um ein Segment in eine failsafe-MTD-Partition zu brennen.
################################################################################
do_flash_failsafe_partition() {
    local bin=$1
    local segment_name=$2
    local mtdname=$3
    local primaryboot
    local mtd_dev=""
    local ret=0

    mkxqimage -c $bin -f $segment_name
    if [ $? -eq 0 ]; then
        [ -f /proc/boot_info/$mtdname/upgradepartition ] && {
            default_mtd=$mtdname
            mtdname=$(cat /proc/boot_info/$mtdname/upgradepartition)
            primaryboot=$(cat /proc/boot_info/$default_mtd/primaryboot)
            if [ $primaryboot -eq 0 ]; then
                echo 1 > /proc/boot_info/$default_mtd/primaryboot
            else
                echo 0 > /proc/boot_info/$default_mtd/primaryboot
            fi
        }

        mtd_dev=$(grep "\"${mtdname}\"" /proc/mtd | awk -F: '{print $1}')

        klogger -n "Burning $segment_name to $mtd_dev ..."
        exec 9>&1
        local pipestatus0=`( (mkxqimage -x $bin -f $segment_name -n || echo $? >&8) | \
            mtd write - /dev/$mtd_dev ) 8>&1 >&9`
        if [ -z "$pipestatus0" -a $? -eq 0 ]; then
            ret=0
        else
            ret=1
        fi
        exec 9>&-

        [ $ret -eq 0 ] && touch "/tmp/bootconfig_update_needed"
    fi

    return $ret
}

################################################################################
# do_flash_sbl1:
#   Brennt das sbl1-Segment in die entsprechende MTD-Partition.
################################################################################
do_flash_sbl1() {
    local package=$1
    local segment_name="sbl1_nand.mbn.padded"
    local mtdpart=$(grep "\"0:SBL1\"" /proc/mtd | awk -F: '{print substr($1,4)}')

    if [ -n "$package" ]; then
        pipe_upgrade_generic $package ${segment_name} $mtdpart
        if [ $? -eq 0 ]; then
            klogger "sbl1 gebrannt"
        else
            klogger "Fehler beim Flashen von sbl1"
            uperr
        fi
    fi
}

################################################################################
# do_flash_tz:
#   Brennt das tz-Segment (TrustZone) in die entsprechende Partition.
################################################################################
do_flash_tz() {
    local package=$1
    local segment_name="tz.mbn.padded"

    do_flash_failsafe_partition $package $segment_name "0:QSEE"
    if [ $? -eq 0 ]; then
        klogger "tz gebrannt"
    else
        klogger "Fehler beim Flashen von tz"
        uperr
    fi
}

################################################################################
# do_flash_devcfg:
#   Brennt das devcfg-Segment.
################################################################################
do_flash_devcfg() {
    local package=$1
    local segment_name="devcfg.mbn.padded"

    do_flash_failsafe_partition $package $segment_name "0:DEVCFG"
    if [ $? -eq 0 ]; then
        klogger "devcfg gebrannt"
    else
        klogger "Fehler beim Flashen von devcfg"
        uperr
    fi
}

################################################################################
# do_flash_ddr:
#   Brennt das cdt-Segment (DRAM-Config).
################################################################################
do_flash_ddr() {
    local package=$1
    local segment_name="cdt.bin.padded"

    do_flash_failsafe_partition $package $segment_name "0:CDT"
    if [ $? -eq 0 ]; then
        klogger "cdt gebrannt"
    else
        klogger "Fehler beim Flashen von cdt"
        uperr
    fi
}

################################################################################
# do_flash_uboot:
#   Brennt das uboot-Segment (Bootloader).
################################################################################
do_flash_uboot() {
    local package=$1
    local segment_name="uboot.bin"

    do_flash_failsafe_partition $package $segment_name "0:APPSBL"
    if [ $? -eq 0 ]; then
        klogger "uboot gebrannt"
    else
        klogger "Fehler beim Flashen von uboot"
        uperr
    fi
}

################################################################################
# do_flash_firmware:
#   Brennt das Firmware-Segment (RootFS). Ermittelt automatisch, welche
#   RootFS-Partition gerade aktiv ist, und schreibt in die andere.
################################################################################
do_flash_firmware() {
    local package=$1
    local rootfs0_mtd=$(grep '"rootfs"' /proc/mtd | awk -F: '{print substr($1,4)}')
    local rootfs1_mtd=$(grep '"rootfs_1"' /proc/mtd | awk -F: '{print substr($1,4)}')

    local os_idx=$(nvram get flag_boot_rootfs)
    local rootfs_mtd_current=$(($rootfs0_mtd+${os_idx:-0}))
    local rootfs_mtd_target=$(($rootfs0_mtd+$rootfs1_mtd-$rootfs_mtd_current))

    pipe_upgrade_rootfs_ubi $rootfs_mtd_target $package
    if [ $? -eq 0 ]; then
        klogger "RootFS (firmware) erfolgreich geflasht"
    else
        klogger "Fehler beim Flashen der RootFS (firmware)"
        uperr
    fi
}

################################################################################
# do_flash_bootconfig:
#   Brennt bootconfig und bootconfig1, falls benötigt.
################################################################################
do_flash_bootconfig() {
    local bin=$1
    local mtdname=$2
    local mtdpart=$(grep "\"${mtdname}\"" /proc/mtd | awk -F: '{print $1}')
    local pgsz=$(cat /sys/class/mtd/${mtdpart}/writesize)

    klogger -n "Burning ${bin}.bin to /dev/${mtdpart} ..."

    if [ -f /proc/boot_info/getbinary_${bin} ]; then
        cat /proc/boot_info/getbinary_${bin} > /tmp/${bin}.bin
        dd if=/tmp/${bin}.bin bs=${pgsz} conv=sync | mtd -e "/dev/${mtdpart}" write - "/dev/${mtdpart}"
    fi
}

################################################################################
# Die Funktionen upgrade_diff_image() und upgrade_fota_image() am Ende
# bleiben unverändert, da sie bereits oben definiert sind.
################################################################################

upgrade_diff_image() {
    local package=$1
    local segment_name="modem_image.zip"

    mkxqimage -c $package -f $segment_name
    if [ $? -ne 0 ]; then
        klogger "Kein modem diff Image im Paket gefunden (oder ungültiges Format)"
        return 1
    fi

    cd /tmp/system_upgrade/
    mkxqimage -x $package -f $segment_name
    quectel_fota -d $segment_name
    if [ $? -eq 0 ]; then
        klogger "Modem-Diff-Image erfolgreich geflasht"
        return 0
    else
        klogger "Fehler beim Flashen des Modem-Diff-Images"
        return 1
    fi
}

upgrade_fota_image() {
    local package=$1
    local segment_name="modem_image.zip"

    mkxqimage -c $package -f $segment_name
    if [ $? -ne 0 ]; then
        klogger "Kein modem FOTA-Image im Paket gefunden (oder ungültiges Format)"
        return 1
    fi

    cd /tmp/system_upgrade/
    mkxqimage -x $package -f $segment_name
    quectel_fota -f $segment_name
    if [ $? -eq 0 ]; then
        klogger "Modem-FOTA-Image erfolgreich geflasht"
        return 0
    else
        klogger "Fehler beim Flashen des Modem-FOTA-Images"
        return 1
    fi
}