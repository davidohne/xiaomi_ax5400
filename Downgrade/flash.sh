#!/bin/sh
#
# flash.sh (Downgrade-fähig, mit Log in /tmp/flash.log)

LOGFILE="/tmp/flash.log"
exec > "$LOGFILE" 2>&1

# Board-spezifische Upgrade-Funktionen laden (inkl. flash_section, board_prepare_upgrade, board_system_upgrade, usw.)
. /data/boardupgrade.sh

################################################################################
# klogger: schreibt sowohl in /dev/kmsg als auch in STDOUT (jetzt umgeleitet nach $LOGFILE)
################################################################################
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
# hndmsg: Behandelt einen Fehlerstring in $msg, loggt und beendet
################################################################################
hndmsg() {
    if [ -n "$msg" ]; then
        echo "$msg" >> /dev/kmsg 2>/dev/null
        echo "$msg"
        if [ `pwd` = "/tmp" ]; then
            rm -rf "$filename" 2>/dev/null
        fi
        exit 1
    fi
}

################################################################################
# upgrade_param_check: Überprüft, ob das Eingabe-Image existiert, und liest aktuelle Version
################################################################################
upgrade_param_check() {
    if [ -z "$1" -o ! -f "$1" ]; then
        klogger "USAGE: $0 input.bin [1:restore defaults, 0:don't] [1:don't reboot, 0:reboot]"
        exit 1
    fi

    flg_ota=`nvram get flag_ota_reboot`
    if [ "$flg_ota" = "1" ]; then
        klogger "flag_ota_reboot ist gesetzt. Abbruch."
        exit 1
    fi

    # Versionsprüfung überspringen und nur ausgeben
    cur_ver=`cat /usr/share/xiaoqiang/xiaoqiang_version || echo "unknown"`
    klogger "Begin Downgrading (Versionscheck ignoriert)..., current version: $cur_ver"
    sync

    model=`cat /proc/xiaoqiang/model`
    [ "$model" != "R4A" -a "$model" != "R3GV2" ] && echo 3 > /proc/sys/vm/drop_caches
}

################################################################################
# upgrade_prepare_dir: Kopiert bzw. verschiebt das Image nach /tmp/system_upgrade/
################################################################################
upgrade_prepare_dir() {
    local src="$1"
    absolute_path=`echo "$(cd "$(dirname "$src")"; pwd)/$(basename "$src")"`
    mount -o remount,size=100% /tmp
    rm -rf /tmp/system_upgrade
    mkdir -p /tmp/system_upgrade

    if [ "${absolute_path:0:4}" = "/tmp" ]; then
        file_in_tmp=1
        mv "$absolute_path" /tmp/system_upgrade/
    else
        file_in_tmp=0
        cp "$absolute_path" /tmp/system_upgrade/
    fi
}

################################################################################
# upgrade_done_set_flags: Setzt NVRAM-Flags und rebootet (sofern nicht 3. Parameter = 1)
################################################################################
upgrade_done_set_flags() {
    # Informiert Server, dass Upgrade beendet ist
    [ -f /etc/config/messaging -a -f /sbin/uci ] && {
        /sbin/uci set /etc/config/messaging.deviceInfo.UPGRADE_STATUS_UPLOAD=0
        /sbin/uci commit
        klogger "messaging.deviceInfo.UPGRADE_STATUS_UPLOAD=`uci get /etc/config/messaging.deviceInfo.UPGRADE_STATUS_UPLOAD`"
        klogger "/etc/config/messaging : `cat /etc/config/messaging`"
    }

    # NVRAM: restore_defaults setzen, falls 2. Parameter = 1
    if [ "$2" = "1" ]; then
        nvram set restore_defaults=1
        klogger "Restore defaults ist gesetzt."
    else
        nvram set restore_defaults=2
    fi

    [ "$upkernel" = "true" ] && nvram set flag_ota_reboot=1
    nvram set flag_upgrade_push=1
    nvram commit

    if [ "$3" = "1" ]; then
        klogger "Skip rebooting..."
    else
        klogger "Rebooting..."
        reboot
    fi
}

################################################################################
# uploadUpgrade: Dummy-Funktion, kann entfernte Statistiken anstoßen
################################################################################
uploadUpgrade() {
    [ "1" = "`cat /proc/xiaoqiang/ft_mode`" ] && return 0
    [ "YES" != "`uci -q get xiaoqiang.common.INITTED`" ] && return 0

    wanstatus=`ubus call network.interface.wan status | grep up | grep false`
    if [ "$wanstatus" = "" ]; then
        logger stat_points_none upgrade=start
        [ -f /usr/sbin/doStatPoints ] && /usr/sbin/doStatPoints
    fi
}

################################################################################
# upgrade_verify_image: Überspringt jegliche Checks, gibt immer Erfolg zurück
################################################################################
upgrade_verify_image() {
    local image_path="$1"
    return 0
}

################################################################################
# PID-Check: Verhindert, dass mehrere Instanzen gleichzeitig laufen
################################################################################
pid_file="/tmp/pid_xxxx"
if [ -f "$pid_file" ]; then
    exist_pid=`cat "$pid_file"`
    if [ -n "$exist_pid" ]; then
        kill -0 $exist_pid 2>/dev/null
        if [ $? -eq 0 ]; then
            klogger "Ein Upgrade/downgrade läuft bereits (PID $exist_pid), Abbruch."
            exit 1
        else
            echo $$ > "$pid_file"
        fi
    else
        echo $$ > "$pid_file"
    fi
else
    echo $$ > "$pid_file"
fi

################################################################################
# Hauptablauf
################################################################################

# 1) Parameter prüfen
upgrade_param_check "$1"

# 2) Image-Verifikation (übersprungen)
klogger "-n Verify Image (übersprungen): $1..."
upgrade_verify_image "$1"
if [ "$?" = "0" ]; then
    klogger "Verification übersprungen: O.K."
    uploadUpgrade
else
    msg="Check Failed!!!"
    hndmsg
fi

# 3) Falls NETMODE = whc_cap/whc_re, 10 Sekunden warten
netmode="`uci -q get xiaoqiang.common.NETMODE`"
if [ "$netmode" = "whc_cap" -o "$netmode" = "whc_re" ]; then
    sleep 10
fi

# 4) „mobile“-Konfiguration festschreiben
klogger "Commit mobile-Config."
uci commit mobile

# 5) Board-Umgebung vorbereiten (hier killen wir keine Netzwerk-/Systemdienste mehr)
klogger "Rufe board_prepare_upgrade() auf..."
board_prepare_upgrade
klogger "board_prepare_upgrade() ist fertig."

# 6) OTA-LED starten
board_start_upgrade_led

# 7) Arbeitsverzeichnis vorbereiten: kopiere das Image nach /tmp/system_upgrade
filename=`basename "$1"`
upgrade_prepare_dir "$1"
cd /tmp/system_upgrade || {
    klogger "FEHLER: konnte nicht nach /tmp/system_upgrade wechseln"
    exit 1
}

# 8) Board-spezifisches Downgrade (überspringt Versionschecks, flasht alles)
klogger "Begin Downgrading und Rebooting (jetzt board_system_upgrade)..."
board_system_upgrade "$filename" "$2" "$3"
klogger "board_system_upgrade() ist beendet."

# 9) Nacharbeiten und Reboot (sofern kein Skip)
if [ $? -eq 0 ]; then
    klogger "Downgrade erfolgreich abgeschlossen"
    cd /
    cap=700
    curcap=`du -sk /tmp/system_upgrade/ | awk '{print $1}'`
    if [ "$curcap" -gt "$cap" ]; then
        upkernel=true
    fi
    rm -rf /tmp/system_upgrade

    upgrade_done_set_flags "$1" "$2" "$3"
else
    klogger "Downgrade fehlgeschlagen, bitte erneut versuchen"
    rm -rf /tmp/system_upgrade
    klogger "Rebooting..."
    reboot
fi