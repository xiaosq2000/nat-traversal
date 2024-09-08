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
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

INSTALL_DEPENDENCIES=false
INSTALL_SYSTEMD=false
UNINSTALL_SYSTEMD=false
AUTOSSH=true
ENV_FILE=${SCRIPT_DIR}/.env
display_help_messages() {
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
		"${INDENT}[--install-dependencies]    " \
		"${INDENT}[--install-systemd]         " \
		"${INDENT}[--uninstall-systemd]       " \
		"${INDENT}[--no-autossh]              " \
		""
}
usage() {
	if [ ! -f "$ENV_FILE" ]; then
		error "$ENV_FILE not found."
		exit 1
	fi

	set -o allexport && source ${ENV_FILE} && set +o allexport

	if [ $VNC != true ]; then
		printf "%s\n" "Usage: SSH twice

Step 1: on the local machine (anyuser@anyhost)

    ${GREEN}${BOLD}\$${RESET} ssh $redirector_user@$redirector_hostname -p $redirector_ssh_port [-X]

Step 2: on the redirector ($redirector_user@$redirector_hostname) 

    ${GREEN}${BOLD}\$${RESET} ssh $USER@localhost -p $redirector_tunnel_ssh_port [-Y]
"
	else
		printf "%s\n" "Usage: 

Step 1: on the local machine (anyuser@anyhost)

    ${GREEN}${BOLD}\$${RESET} ssh -L $remote_ssh_port:localhost:$redirector_ssh_port $redirector_user@$redirector_hostname -p $redirector_ssh_port

Step 2: start a VNC client on the local machine

    localhost::$remote_ssh_port
"
	fi
}
while [[ $# -gt 0 ]]; do
	case "$1" in
	-h | --help)
		display_help_messages
		shift 1
		exit 0
		;;
	--usage)
		usage
		shift 1
		exit 0
		;;
	-ef | --env-file)
		ENV_FILE="$2"
		shift 2
		;;
	--install-dependencies)
		INSTALL_DEPENDENCIES=true
		shift 1
		;;
	--install-systemd)
		INSTALL_SYSTEMD=true
		shift 1
		;;
	--uninstall-systemd)
		UNINSTALL_SYSTEMD=true
		shift 1
		;;
	--no-autossh)
		AUTOSSH=false
		shift 1
		;;
	*)
		error "Unknown argument: $1"
		display_help_messages
		exit 1
		;;
	esac
done

if $INSTALL_DEPENDENCIES = true || $INSTALL_SYSTEMD = true; then
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

check_port_availability() {
	if [[ $(id -u) -eq 0 ]]; then
		if [[ -z $(sudo lsof -i:$1) ]]; then
			return 0
		else
			return 1
		fi
	else
		if [[ -z $(lsof -i:$1) ]]; then
			return 0
		else
			return 1
		fi
	fi
}

SYSTEMD_SERVICE_DIR="/etc/systemd/system"
install_systemd() {
	if [[ $(id -u) -eq 0 ]]; then
		sudo cp "$SCRIPT_DIR/nat-traversal@.service" "$SYSTEMD_SERVICE_DIR/nat-traversal@.service"
		sudo systemctl daemon-reload
	fi
}
uninstall_systemd() {
	if [[ $(id -u) -eq 0 ]]; then
		set +e
		if [[ ! -z "$(ls $SYSTEMD_SERVICE_DIR | grep 'nat-traversal@.service')" ]]; then
			debug "Found nat-traversal@.service in $SYSTEMD_SERVICE_DIR. Try to stop and disable all instances and remove the service template file."
			systemctl list-units -t service --full --all | grep 'nat-traversal' | awk '{print $1}' | xargs -i systemctl disable \{\} --now
			sudo rm "${SYSTEMD_SERVICE_DIR}/nat-traversal@.service"
		fi
		set -e
	fi
}

if $INSTALL_DEPENDENCIES = true; then
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

if $INSTALL_SYSTEMD = true; then

	# Replace the User line
	sed -i "/^\[Service\]/,/\[/s/^User=.*/User=$SUDO_USER/" $SCRIPT_DIR/nat-traversal@.service
	# Replace the ExecStart line
	sed -i "/^\[Service\]/,/\[/s|ExecStart=.*|ExecStart=$SCRIPT_DIR/setup.sh --env-file $SCRIPT_DIR/.env.%i|" $SCRIPT_DIR/nat-traversal@.service

	debug "Try to uninstall related systemd services first before installation."
	uninstall_systemd
	install_systemd
	exit 0
fi

if $UNINSTALL_SYSTEMD = true; then
	uninstall_systemd
	exit 0
fi

if [ ! -f "$ENV_FILE" ]; then
	error "$ENV_FILE not found."
	exit 1
fi

set -o allexport && source ${ENV_FILE} && set +o allexport

usage

warning "Make sure the port ${BOLD}${YELLOW}$redirector_tunnel_ssh_port${RESET} is available on ${BOLD}${YELLOW}$redirector_hostname${RESET}"
if ! check_port_availability $remote_autossh_monitor_port; then
	error "remote_autossh_monitor_port=$remote_autossh_monitor_port is unavailable."
	exit 1
fi

set +e
ssh-keygen -R $redirector_hostname >/dev/null 2>&1
set -e

debug "Try to construct SSH reverse tunnel."
if $AUTOSSH = true; then
	autossh -M $remote_autossh_monitor_port -XNR "$redirector_tunnel_ssh_port:localhost:$remote_ssh_port" "$redirector_user@$redirector_hostname" -p $redirector_ssh_port
else
	ssh -XNR "$redirector_tunnel_ssh_port:localhost:$remote_ssh_port" "$redirector_user@$redirector_hostname" -p $redirector_ssh_port
fi

completed "Done."
