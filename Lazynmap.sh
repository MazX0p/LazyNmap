#!/bin/sh
#by Mohamed Alzhrani
YELLOW='\033[33m'
LIGHT='\033[95m'
CYAN='\033[96m'
NC='\033[0m'
origIFS="${IFS}"
elapsedStart="$(date '+%H:%M:%S' | awk -F: '{print $1 * 3600 + $2 * 60 + $3}')"
REMOTE=false

while [ $# -gt 0 ]; do
        key="$1"

        case "${key}" in
        -ip)
                HOST="$2"
                shift
                shift
                ;;
        -t)
                TYPE="$2"
                shift
                shift
                ;;
        esac
done
set -- ${POSITIONAL}
if [ -z "${OUTPUTDIR}" ]; then
        OUTPUTDIR="${HOST}"
fi

if [ -z "${NMAPPATH}" ] && type nmap >/dev/null 2>&1; then
        NMAPPATH="$(type nmap | awk {'print $NF'})"
fi

PAGE1() {
  echo  "\e[33m

  <============================================================================================================>
  ||                                \"Lazy nmap tool                                                           ||
  ||                                                                                                          ||
  ||  Author  : Mohamed Alzhrani                                                                              ||
  ||  Url     : https://github.com/MazX0p                                                                     ||
  ||  usage   : Ex: LazyNmap.sh -ip 10.10.10.10 -t Hosts (add type of scan after -t)                          ||
  ||  Types   :                                                                                               ||
  ||  * Hosts   --> TO DO live hosts scan                                                                     ||
  ||  * Ports   --> TO DO port scan                                                                           ||
  ||  * Vuln    --> TO DO CVE scan                                                                            ||
  ||  * Full    --> TO DO Full Scan                                                                           ||
  ||  * All     --> TO DO all scans                                                                           ||
  <============================================================================================================>

                                                                                                                     \e[0m"
        exit 1
}

hea1() {
        echo
        if expr "${TYPE}" : '^\([Aa]ll\)$' >/dev/null; then
                printf "${LIGHT}running all scans on ${NC}${HOST}"
        else
                printf "${LIGHT}running a ${TYPE} scan on ${NC}${HOST}"
        fi

        if expr "${HOST}" : '^\(\([[:alnum:]-]\{1,63\}\.\)*[[:alpha:]]\{2,6\}\)$' >/dev/null; then
                urlIP="$(host -4 -W 1 ${HOST} ${DNSSERVER} 2>/dev/null | grep ${HOST} | head -n 1 | awk {'print $NF'})"
                if [ -n "${urlIP}" ]; then
                        printf "${LIGHT} with IP ${NC}${urlIP}\n\n"
                else
                        printf ".. ${YELLOW}Could not resolve IP of ${NC}${HOST}\n\n"
                fi
        else
                printf "\n"
        fi

        if expr "${HOST}" : '^\([0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\)$' >/dev/null; then
                subnet="$(echo "${HOST}" | cut -d "." -f 1,2,3).0"
        fi

        echo
        echo
}

sighn() {
        if [ -f "nmap/Port_$1.nmap" ]; then
                commonPorts="$(awk -vORS=, -F/ '/^[0-9]/{print $1}' "nmap/Port_$1.nmap" | sed 's/.$//')"
        fi
        if [ -f "nmap/Full_$1.nmap" ]; then
                if [ -f "nmap/Port_$1.nmap" ]; then
                        allPorts="$(awk -vORS=, -F/ '/^[0-9]/{print $1}' "nmap/Port_$1.nmap" "nmap/Full_$1.nmap" | sed 's/.$//')"
                else
                        allPorts="$(awk -vORS=, -F/ '/^[0-9]/{print $1}' "nmap/Full_$1.nmap" | sed 's/.$//')"
                fi
        fi
}

cmp() {
        extraPorts="$(echo ",${allPorts}," | sed 's/,\('"$(echo "${commonPorts}" | sed 's/,/,\\|/g')"',\)\+/,/g; s/^,\|,$//g')"
}

timer() {
        [ -z "${2##*[!0-9]*}" ] && return 1
        [ "$(stty size | cut -d ' ' -f 2)" -le 120 ] && width=50 || width=100
        fill="$(printf "%-$((width == 100 ? $2 : ($2 / 2)))s" "#" | tr ' ' '#')"
        empty="$(printf "%-$((width - (width == 100 ? $2 : ($2 / 2))))s" " ")"
        printf "Loading: $1 Scan ($3 passed - $4 remaining)   \n"
        printf "[${fill}>${empty}] $2%% done   \n"
        printf "\e[2A"
}

nmaptimer() {
        refreshRate="${2:-1}"
        outputFile="$(echo $1 | sed -e 's/.*-oN \(.*\).nmap.*/\1/').nmap"
        tmpOutputFile="${outputFile}.tmp"

        # Run the nmap command
        if [ ! -e "${outputFile}" ]; then
                $1 -stats-every "${refreshRate}s" >"${tmpOutputFile}" 2>&1 &
        fi

        while { [ ! -e "${outputFile}" ] || ! grep -q "Nmap done at" "${outputFile}"; } && { [ ! -e "${tmpOutputFile}" ] || ! grep -i -q "quitting" "${tmpOutputFile}"; }; do
                scanType="$(tail -n 2 "${tmpOutputFile}" 2>/dev/null | sed -ne '/elapsed/{s/.*undergoing \(.*\) Scan.*/\1/p}')"
                percent="$(tail -n 2 "${tmpOutputFile}" 2>/dev/null | sed -ne '/% done/{s/.*About \(.*\)\..*% done.*/\1/p}')"
                elapsed="$(tail -n 2 "${tmpOutputFile}" 2>/dev/null | sed -ne '/elapsed/{s/Stats: \(.*\) elapsed.*/\1/p}')"
                remaining="$(tail -n 2 "${tmpOutputFile}" 2>/dev/null | sed -ne '/remaining/{s/.* (\(.*\) remaining.*/\1/p}')"
                timer "${scanType:-No}" "${percent:-0}" "${elapsed:-0:00:00}" "${remaining:-0:00:00}"
                sleep "${refreshRate}"
        done
        printf "\033[0K\r\n\033[0K\r\n"

        if [ -e "${outputFile}" ]; then
                sed -n '/PORT.*STATE.*SERVICE/,/^# Nmap/H;${x;s/^\n\|\n[^\n]*\n# Nmap.*//gp}' "${outputFile}" | awk '!/^SF(:|-).*$/' | grep -v 'service unrecognized despite'
        else
                cat "${tmpOutputFile}"
        fi
        rm -f "${tmpOutputFile}"
}
host() {
        printf "${CYAN}HOST Scan\n"
        printf "${NC}\n"

        origHOST="${HOST}"
        HOST="${urlIP:-$HOST}"
                nmaptimer "nmap -T4 --max-retries 1 --max-scan-delay 20 -n -sn -oN nmap/Network_${HOST}.nmap ${subnet}/24"
                printf "${LIGHT}live hosts:${NC}\n\n"
                cat nmap/Network_${HOST}.nmap | grep -v '#' | grep "$(echo $subnet | sed 's/..$//')" | awk {'print $5'}

        HOST="${origHOST}"

        echo
        echo
        echo
}

psc() {
        printf "${CYAN}Port Scan\n"
        printf "${NC}\n"

        if ! $REMOTE; then
                nmaptimer "nmap -T4 --max-retries 1 --max-scan-delay 20 --open -oN nmap/Port_${HOST}.nmap ${HOST} ${DNSSTRING}"
                sighn "${HOST}"
        else
                printf "${LIGHT}Port Scan is not implemented yet in Remote mode.\n${NC}"
        fi

        echo
        echo
        echo
}

fus() {
        printf "${CYAN}Full Scan\n"
        printf "${NC}\n"

        if ! $REMOTE; then
                nmaptimer "nmap -p- --max-retries 1 --max-rate 500 --max-scan-delay 20 -T4 -v --open -oN nmap/Full_${HOST}.nmap ${HOST} ${DNSSTRING}" 3
                sighn "${HOST}"
                if [ -z "${commonPorts}" ]; then
                        echo
                        echo
                        printf "${LIGHT}Making a script scan on all ports\n"
                        printf "${NC}\n"
                        nmaptimer "nmap -sCV -p${allPorts} --open -oN nmap/Full_Extra_${HOST}.nmap ${HOST} ${DNSSTRING}" 2
                        sighn "${HOST}"
                else
                        cmp
                        if [ -z "${extraPorts}" ]; then
                                echo
                                echo
                                allPorts=""
                                printf "${LIGHT}No new ports\n"
                                printf "${NC}\n"
                        else
                                echo
                                echo
                                printf "${LIGHT}Making a script scan on extra ports: $(echo "${extraPorts}" | sed 's/,/, /g')\n"
                                printf "${NC}\n"
                                nmaptimer "nmap -sCV -p${extraPorts} --open -oN nmap/Full_Extra_${HOST}.nmap ${HOST} ${DNSSTRING}" 2
                                sighn "${HOST}"
                        fi
                fi
              fi

        echo
        echo
        echo
}

vuls() {
        printf "${CYAN}Vulns Scan\n"
        printf "${NC}\n"

        if ! $REMOTE; then
                if [ -z "${allPorts}" ]; then
                        portType="common"
                        ports="${commonPorts}"
                else
                        portType="all"
                        ports="${allPorts}"
                fi

                if [ ! -f /usr/share/nmap/scripts/vulners.nse ]; then
                        printf "${YELLOW}Please install 'vulners.nse' nmap script:\n"
                        printf "${YELLOW}https://github.com/vulnersCom/nmap-vulners\n"
                        printf "${YELLOW}\n"
                        printf "${YELLOW}Skipping CVE scan!\n"
                        printf "${NC}\n"
                else
                        printf "${LIGHT}running CVE scan on ${portType} ports\n"
                        printf "${NC}\n"
                        nmaptimer "nmap -sV --script vulners --script-args mincvss=7.0 -p${ports} --open -oN nmap/CVEs_${HOST}.nmap ${HOST} ${DNSSTRING}" 3
                        echo
                fi
              fi

        echo
        echo
        echo
}

lastp() {

        printf "${CYAN}DONE\n"
        printf "${NC}\n\n"

        elapsedEnd="$(date '+%H:%M:%S' | awk -F: '{print $1 * 3600 + $2 * 60 + $3}')"
        elapsedSeconds=$((elapsedEnd - elapsedStart))

        if [ ${elapsedSeconds} -gt 3600 ]; then
                hours=$((elapsedSeconds / 3600))
                minutes=$(((elapsedSeconds % 3600) / 60))
                seconds=$(((elapsedSeconds % 3600) % 60))
                printf "${LIGHT}DONE in ${hours} hour(s), ${minutes} minute(s) and ${seconds} second(s)\n"
        elif [ ${elapsedSeconds} -gt 60 ]; then
                minutes=$(((elapsedSeconds % 3600) / 60))
                seconds=$(((elapsedSeconds % 3600) % 60))
                printf "${LIGHT}DONE in ${minutes} minute(s) and ${seconds} second(s)\n"
        else
                printf "${LIGHT}DONE in ${elapsedSeconds} seconds\n"
        fi
        printf "${NC}\n"
}


main() {
        sighn "${HOST}"

        hea1

        case "${TYPE}" in
        [Hh]osts) host "${HOST}" ;;
        [Pp]orts) psc "${HOST}" ;;
        [Ff]ull) fus "${HOST}" ;;
        [Vv]uln)
                [ ! -f "nmap/Port_${HOST}.nmap" ] && psc "${HOST}"
                vuls "${HOST}"
                ;;
        [Aa]ll)
                psc "${HOST}"
                fus "${HOST}"
                vuls "${HOST}"
                ;;
        esac

        lastp
}

if [ -z "${TYPE}" ] || [ -z "${HOST}" ]; then
        PAGE1
fi

if ! expr "${HOST}" : '^\([0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\)$' >/dev/null && ! expr "${HOST}" : '^\(\([[:alnum:]-]\{1,63\}\.\)*[[:alpha:]]\{2,6\}\)$' >/dev/null; then
        printf "${YELLOW}\n"
        printf "${YELLOW}Invalid IP or URL!\n"
        PAGE1
fi

if ! case "${TYPE}" in [Hh]osts | [Pp]orts | [Ff]ull | [Vv]uln | [Aa]ll) false ;; esac then
        mkdir -p "${OUTPUTDIR}" && cd "${OUTPUTDIR}" && mkdir -p nmap/ || PAGE1
        main | tee "LazyNmap_${HOST}_${TYPE}.txt"
else
        printf "${YELLOW}\n"
        printf "${YELLOW}Invalid Type!\n"
        PAGE1
fi
