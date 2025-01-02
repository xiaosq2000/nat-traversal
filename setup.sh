#!/usr/bin/env bash
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
	set +u
	[ "$VERBOSE" = "true" ] && printf '%s\n' "${BOLD}${GREY}DEBUG:${RESET} $*"
	set -u
}
completed() {
	printf '%s\n' "${BOLD}${GREEN}✓${RESET} $*"
}
has() {
	command -v "$1" 1>/dev/null 2>&1
}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

INSTALL_SYSTEMD=false
SYSTEMD_SERVICE_DIR="${HOME}/.config/systemd/user"
AUTOSSH=true
X11=false
VNC=false
ENV_FILE=${SCRIPT_DIR}/.env
display_help_messages() {
	printf "%s\n" \
		"Usage: " \
		"${INDENT}$0 [option]" \
		"" \
		"${INDENT}NAT Traversal Setup:" \
		"" \
		"${INDENT}Access your PC from anywhere and anytime safely." \
		"" \
		"${INDENT}${BOLD}This script should be executed on the remote machine.${RESET}" \
		"
${INDENT}+-------------------------------------------------------------+
${INDENT}|  Take Care!                                                 |
${INDENT}|  For security, the redirector should only be accessible in  |
${INDENT}|      1. Intranet of your organization                       |
${INDENT}|      2. VPN service endorsed by your organization           |
${INDENT}+-------------------------------------------------------------+
" \
		""
	printf "%s\n" \
		"Options: " \
		"${INDENT}-h, --help                  Display help messages of this script" \
		"${INDENT}[--list-env-files]          List the first line of .env.* files" \
		"${INDENT}[--reindex-env-files]       Rename the .env.* files" \
		"" \
		"${INDENT}-ef, --env-file ENV_FILE    Default: ${ENV_FILE}" \
		"" \
		"${INDENT}-x, --x11                   Enable X11 forwarding" \
		"" \
		"${INDENT}[--install-dependencies]    " \
		"${INDENT}[--install-systemd]         " \
		"${INDENT}[--email-notify-on-failure] " \
		"${INDENT}[--uninstall-systemd]       " \
		"" \
		"${INDENT}[--usage]                   Display help messages based on given ENV_FILE" \
		"${INDENT}[--verbose]                 Display help messages based on given ENV_FILE" \
		"${INDENT}[--no-autossh]              Use ssh instead of autossh for debugging" \
		"" \
		"
${INDENT}+-----------------+       +--------------+               +------------------+ 
${INDENT}|                 |  VPN  |              |               |                  | 
${INDENT}|  Local Machine  |<----->|  Redirector  |<------------->|  Remote Machine  | 
${INDENT}|                 |<----->|              |<------------->|                  | 
${INDENT}|    (Internet)   |  SSH  |  (Intranet)  |  Reverse SSH  |    (Intranet)    | 
${INDENT}+-----------------+       +--------------+               +------------------+ 
" \
		"Template of ENV_FILE:

$(cat .env)
"
}
display_usage_messages() {
	if [ ! -f "$ENV_FILE" ]; then
		error "$ENV_FILE not found. Make sure the argument --env-file is set BEFORE --usage"
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

    ${GREEN}${BOLD}\$${RESET} ssh -L $remote_ssh_port:localhost:$redirector_tunnel_ssh_port $redirector_user@$redirector_hostname -p $redirector_ssh_port

Step 2: start a VNC client on the local machine

    localhost::$remote_ssh_port
"
	fi
}

list_env_files() {
	for file in .env.*; do echo -n "$file    " && head -n 1 "$file"; done
}

reindex_env_files() {
	# Get all .env.* files sorted numerically
	files=($(ls .env.* | sort -t. -k2 -n))

	# Rename files sequentially
	index=1
	for file in "${files[@]}"; do
		new_name=".env.$index"
		if [ "$file" != "$new_name" ]; then
			mv "$file" "$new_name"
		fi
		index=$((index + 1))
	done

	info "Environment files reindexed successfully"
	list_env_files
}

install_dependencies() {
	if [[ ! $(lsb_release -d | grep 'Ubuntu') ]]; then
		warning "Argument '--install-dependencies' has only been tested on Ubuntu."
	fi
	if ! has autossh; then
		sudo apt-get -qq update
		sudo apt-get install -y -qq autossh
	fi
	sudo apt install -y -qq openssh-server
	sudo systemctl enable ssh --now
    exit 0
}

install_systemd() {
	debug "Try to install related systemd services into $BOLD$GREEN${SYSTEMD_SERVICE_DIR}$RESET."
	cp "$SCRIPT_DIR/nat-traversal@.service" "$SYSTEMD_SERVICE_DIR/nat-traversal@.service"
	systemctl --user daemon-reload
}

uninstall_systemd() {
	debug "Try to uninstall previous systemd services from $BOLD$GREEN${SYSTEMD_SERVICE_DIR}$RESET before installation."
	local to_uninstall=true
	set +u
	if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
		set -u
		warning "Uninstall may kill the current SSH session."
		read -p "Do you want to proceed? (y/N) " yn
		case $yn in
		yes | y)
			to_uninstall=true
			return 0
			;;
		no | n)
			to_uninstall=false
			return 0
			;;
		*)
			to_uninstall=false
			return 0
			;;
		esac
	fi

	if [[ $to_uninstall == "true" ]]; then
		set +e
		if [[ ! -z "$(ls $SYSTEMD_SERVICE_DIR | grep 'nat-traversal@.service')" ]]; then
			debug "Found nat-traversal@.service in $SYSTEMD_SERVICE_DIR. Try to stop and disable all instances and remove the service template file."
			SYSTEMD_COLORS=0 systemctl --user list-units -t service --full --all --no-legend --plain | grep 'nat-traversal@' | awk '{print $1}' | xargs -i systemctl --user disable \{\} --now
			rm "${SYSTEMD_SERVICE_DIR}/nat-traversal@.service"
		fi
		set -e
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
		display_usage_messages
		shift 1
		exit 0
		;;
	--list-env-files)
		list_env_files
		shift 1
		exit 0
		;;
	--reindex-env-files)
		reindex_env_files
		shift 1
		exit 0
		;;
	--install-dependencies)
		install_dependencies
		shift 1
		;;
	--install-systemd)
		INSTALL_SYSTEMD=true
		shift 1
		;;
	--email-notify-on-failure)
        cp $SCRIPT_DIR/nat-traversal-notify@.service $SYSTEMD_SERVICE_DIR
        info "Make sure install and configure your ${BOLD}mstmp${RESET} at first."
		shift 1
		;;
	-ef | --env-file)
		ENV_FILE="$2"
		shift 2
		;;
	--verbose)
		VERBOSE=true
		shift 1
		;;
	--x11 | -x)
		X11=true
		shift 1
		;;
	--uninstall-systemd)
		uninstall_systemd
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

if $INSTALL_SYSTEMD = true; then

	# Replace the User line
	# sed -i "/^\[Service\]/,/\[/s/^User=.*/User=$SUDO_USER/" $SCRIPT_DIR/nat-traversal@.service
	# Replace the ExecStart line
	sed -i "/^\[Service\]/,/\[/s|ExecStart=.*|ExecStart=$SCRIPT_DIR/setup.sh --env-file $SCRIPT_DIR/.env.%i|" $SCRIPT_DIR/nat-traversal@.service

	uninstall_systemd
	install_systemd
    exit 0
fi

if [ ! -f "$ENV_FILE" ]; then
	error "$ENV_FILE not found."
	exit 1
fi

set -o allexport && source ${ENV_FILE} && set +o allexport

display_usage_messages

warning "Make sure the port ${BOLD}${YELLOW}$redirector_tunnel_ssh_port${RESET} is available on ${BOLD}${YELLOW}$redirector_hostname${RESET}"
warning "To check port availability: 
1. port is not in use, e.g.
$redirector_user@$redirector_hostname $BOLD$GREEN\$$RESET sudo lsof -i :$redirector_tunnel_ssh_port
2. firewall rules, e.g.
$redirector_user@$redirector_hostname $BOLD$GREEN\$$RESET sudo ufw status | grep '$redirector_tunnel_ssh_port'"

debug 'Execute "ssh-keygen -R $redirector_hostname"'
set +e
ssh-keygen -R $redirector_hostname >/dev/null 2>&1
set -e

# Verify SSH connection first
info "Testing SSH connection to $redirector_user@$redirector_hostname..."
if ! ssh -o ConnectTimeout=5 -p $redirector_ssh_port $redirector_user@$redirector_hostname "echo SSH connection test successful"; then
	error "Failed to establish SSH connection to redirector"
	exit 1
fi

debug "Try to construct SSH reverse tunnel."
if $AUTOSSH = true; then
	# Create log directory
	LOG_DIR="$SCRIPT_DIR/logs"
	mkdir -p "$LOG_DIR"
	# Extract the suffix number from ENV_FILE (e.g., .env.7 -> 7)
	ENV_SUFFIX=$(basename "$ENV_FILE" | awk -F. '{print $NF}')
	LOG_FILE="$LOG_DIR/nat-traversal-$ENV_SUFFIX-$(date +%Y%m%d).log"
	info "Starting autossh tunnel, logging to $LOG_FILE"
	if $X11 = true; then
		autossh -M $remote_autossh_monitor_port -XNCR "$redirector_tunnel_ssh_port:localhost:$remote_ssh_port" "$redirector_user@$redirector_hostname" -p $redirector_ssh_port \
			-v -E "$LOG_FILE" \
			-o "ExitOnForwardFailure=yes" \
			-o "ServerAliveInterval=60" \
			-o "ServerAliveCountMax=3"
	else
		autossh -M $remote_autossh_monitor_port -NR "$redirector_tunnel_ssh_port:localhost:$remote_ssh_port" "$redirector_user@$redirector_hostname" -p $redirector_ssh_port \
			-v -E "$LOG_FILE" \
			-o "ExitOnForwardFailure=yes" \
			-o "ServerAliveInterval=60" \
			-o "ServerAliveCountMax=3"
	fi
else
	if $X11 = true; then
		ssh -XNCR "$redirector_tunnel_ssh_port:localhost:$remote_ssh_port" "$redirector_user@$redirector_hostname" -p $redirector_ssh_port
	else
		ssh -NR "$redirector_tunnel_ssh_port:localhost:$remote_ssh_port" "$redirector_user@$redirector_hostname" -p $redirector_ssh_port
	fi
fi

completed "Done."
