#!/bin/bash
set -euo pipefail
INDENT='    '
BOLD="$(tput bold 2>/dev/null || printf '')"
GREY="$(tput setaf 0 2>/dev/null || printf '')"
UNDERLINE="$(tput smul 2>/dev/null || printf '')"
RED="$(tput setaf 1 2>/dev/null || printf '')"
GREEN="$(tput setaf 2 2>/dev/null || printf '')"
YELLOW="$(tput setaf 3 2>/dev/null || printf '')"
BLUE="$(tput setaf 4 2>/dev/null || printf '')"
MAGENTA="$(tput setaf 5 2>/dev/null || printf '')"
RESET="$(tput sgr0 2>/dev/null || printf '')"
error() {
	printf '%s\n' "${BOLD}${RED}ERROR:${RESET} $*" >&2
}
warning() {
	printf '%s\n' "${BOLD}${YELLOW}WARNING:${RESET} $*"
}
info() {
	printf '%s\n' "${BOLD}${GREEN}INFO:${RESET} $*"
}
debug() {
	printf '%s\n' "${BOLD}${GREY}DEBUG:${RESET} $*"
}
completed() {
	printf '%s\n' "${BOLD}${GREEN}✓${RESET} $*"
}
has() {
	command -v "$1" 1>/dev/null 2>&1
}
check_port_availability() {
	if [[ -z $(lsof -i:$1) ]]; then
		return 0
	else
		return 1
	fi
}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

ENSURE_DEPENDENCIES=false
AUTOSSH=true
SYSTEMD=false
ENV_FILE=${SCRIPT_DIR}/.env
usage() {
	printf "%s\n" \
		"Usage: " \
		"${INDENT}$0 [option]" \
		"" \
		"${INDENT}For NAT Traversal" \
		""
	printf "%s\n" \
		"Options: " \
		"${INDENT}-h, --help                  Display help messages" \
		"${INDENT}-ef, --env-file ENV_FILE    Default: ${ENV_FILE}" \
		"${INDENT}[--ensure-dependencies]     " \
		"${INDENT}[--systemd]                 " \
		"${INDENT}[--no-autossh]              " \
		""
}
while [[ $# -gt 0 ]]; do
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	-ef | --env-file)
		ENV_FILE="$2"
		shift 2
		;;
	--ensure-dependencies)
		ENSURE_DEPENDENCIES=true
		shift 1
		;;
	--systemd)
		SYSTEMD=true
		shift 1
		;;
	--no-autossh)
		AUTOSSH=false
		shift 1
		;;
	*)
		error "Unknown argument: $1"
		usage
		;;
	esac
done

if $ENSURE_DEPENDENCIES = true || $SYSTEMD = true; then
	if [[ $(id -u) -ne 0 ]]; then
		error "Try again with sudo."
		exit 1
	fi
else
	if [[ $(id -u) -eq 0 ]]; then
		error "Do not run with sudo."
		exit 1
	fi
fi

if $ENSURE_DEPENDENCIES = true; then
	if [[ ! $(lsb_release -d | grep 'Ubuntu') ]]; then
		warning "The script has only been tested on Ubuntu."
	fi
	if ! has autossh; then
		sudo apt-get -qq update
		sudo apt-get install -y -qq autossh
	fi
	sudo apt install -y -qq openssh-server
	sudo systemctl enable ssh --now
fi

set +e
if $SYSTEMD = true; then
	# Replace the User line
	sed -i "/^\[Service\]/,/\[/s/^User=.*/User=$SUDO_USER/" $SCRIPT_DIR/nat-traversal@.service
	# Replace the ExecStart line
	sed -i "/^\[Service\]/,/\[/s|ExecStart=.*|ExecStart=$SCRIPT_DIR/setup.sh --env-file $SCRIPT_DIR/.env.%i|" $SCRIPT_DIR/nat-traversal@.service

	SYSTEMD_SERVICE_DIR="/etc/systemd/system"

	systemd_clear() {
		if [[ ! -z "$(ls $SYSTEMD_SERVICE_DIR | grep 'nat-traversal@.service')" ]]; then
			debug "Found nat-traversal@.service in $SYSTEMD_SERVICE_DIR. Try to stop and disable all instances and remove the service template file."
			systemctl list-units -t service --full --all | grep 'nat-traversal' | awk '{print $1}' | xargs -i systemctl disable \{\} --now
			sudo rm "${SYSTEMD_SERVICE_DIR}/nat-traversal@.service"
		fi
	}
	systemd_clear

	sudo cp "$SCRIPT_DIR/nat-traversal@.service" "$SYSTEMD_SERVICE_DIR/nat-traversal@.service"
	sudo systemctl daemon-reload
else
	if [ ! -f "$ENV_FILE" ]; then
		error "$ENV_FILE not found."
		exit 1
	fi
	set -o allexport && source ${ENV_FILE} && set +o allexport

	printf "%s\n" "Usage: ssh twice

${GREEN}anyuser@anyhost:~${BOLD}\$${RESET} ssh $remote_user@$remote_hostname -p $remote_ssh_port
${GREEN}$remote_user@$remote_hostname:~${BOLD}\$${RESET} ssh $USER@localhost -p $remote_tunnel_ssh_port
"

	warning "Make sure the port ${BOLD}${YELLOW}$remote_tunnel_ssh_port${RESET} is available on ${BOLD}${YELLOW}$remote_hostname${RESET}"
	if ! check_port_availability $local_autossh_monitor_port; then
		error "local_autossh_monitor_port=$local_autossh_monitor_port is unavailable."
		exit 1
	fi

	ssh-keygen -R $remote_hostname >/dev/null 2>&1
	if $AUTOSSH = true; then
		autossh -M $local_autossh_monitor_port -N -R "$remote_tunnel_ssh_port:localhost:$local_ssh_port" "$remote_user@$remote_hostname" -X -p $remote_ssh_port
	else
		ssh -N -R "$remote_tunnel_ssh_port:localhost:$local_ssh_port" "$remote_user@$remote_hostname" -X -p $remote_ssh_port
	fi
fi
set -e

if [ $? -ne 0 ]; then
	error "Something goes wrong."
	exit 1
else
	completed "Done."
fi
