# vim: set ft=make :
#
# 82-bazzite-sunshine.just — bazzite-mx OVERRIDE of Bazzite's upstream
# brew-flavored Sunshine recipe.
#
# bazzite-mx ships Sunshine as a system RPM (build_files/mx/65-sunshine.sh)
# with the user unit `app-dev.lizardbyte.app.Sunshine.service` (alias
# `sunshine.service`); upstream's brew-based recipe fails here because
# brew is never installed. This recipe drops the brew/Cellar references,
# `enable-beta`, `update`, and `uninstall` (Sunshine is part of the base
# image; removal is `rpm-ostree override remove Sunshine`, noted in
# `help`), keeping `status`, `enable`, `disable`, `portal`, `help`.

# Setup and configure Sunshine Game Streaming host. Options: status | enable | disable | portal | help
[group("gaming")]
setup-sunshine ACTION="":
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    OPTION={{ ACTION }}
    SUNSHINE_UNIT="app-dev.lizardbyte.app.Sunshine.service"

    get_status_token() {
      local service_state
      service_state="$(systemctl is-enabled --user $SUNSHINE_UNIT 2>/dev/null || true)"
      if [[ "$service_state" == "enabled" ]]; then
        echo "enable"
      else
        echo "disable"
      fi
    }

    if [ "$OPTION" == "help" ]; then
      echo "Usage: ujust setup-sunshine <option>"
      echo "  <option>: Specify the quick option to skip the prompt"
      echo "  Use 'status' to print the current service state"
      echo "  Use 'enable' to enable+start the Sunshine user service"
      echo "  Use 'disable' to stop+disable the Sunshine user service"
      echo "  Use 'portal' to open the Sunshine management portal in a browser"
      echo "  Use 'exit' to exit without making changes"
      echo ""
      echo "${b}Notes${n}:"
      echo "  - Sunshine is shipped at build time as a system RPM (lizardbyte/stable COPR)."
      echo "    Updates flow automatically with ${b}bootc upgrade${n} / ${b}ujust update${n}."
      echo "  - To remove Sunshine entirely: ${b}rpm-ostree override remove Sunshine${n}, then reboot."
      echo "  - Default service state on a fresh image: ${b}disabled${n} (Aurora pattern)."
      echo "  - Port forwarding for streaming over the internet: 47984 (HTTPS), 47989 (HTTP),"
      echo "    47998-48000/UDP (video/audio/control), 48010 (RTSP)."
      exit 0
    elif [ "$OPTION" == "status" ]; then
      echo "$(get_status_token)"
      exit 0
    elif [ "$OPTION" == "" ]; then
      case "$(get_status_token)" in
        "enable")
          SERVICE_STATE="${green}${b}Enabled${n}"
          ;;
        *)
          SERVICE_STATE="${yellow}${b}Disabled${n}"
          ;;
      esac
      echo "Sunshine user service is $SERVICE_STATE"
      OPTION=$(Choose "Enable" "Disable" "Open Portal" "Exit")
    fi

    if [[ "${OPTION,,}" =~ ^enable ]]; then
      echo "Enabling Sunshine user service ($SUNSHINE_UNIT)..."
      systemctl --user enable --now "$SUNSHINE_UNIT"
      echo ""
      echo "Sunshine is now ${green}${b}running${n}."
      echo "Open the management portal: ${b}ujust setup-sunshine portal${n} (or https://localhost:47990)"
      echo "First-time setup will ask you to create a credential pair to pair Moonlight clients."
    elif [[ "${OPTION,,}" =~ ^disable ]]; then
      echo "Disabling Sunshine user service ($SUNSHINE_UNIT)..."
      systemctl --user disable --now "$SUNSHINE_UNIT" || true
      echo "Sunshine is now ${yellow}${b}stopped${n}."
    elif [[ "${OPTION,,}" =~ ^(portal|open) ]]; then
      echo "Opening Sunshine management portal..."
      xdg-open https://localhost:47990
    elif [[ "${OPTION,,}" =~ ^exit ]]; then
      echo "Exiting without making changes."
      exit 0
    fi
