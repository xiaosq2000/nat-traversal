#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source ${SCRIPT_DIR}/utils.sh

SYSTEMD_SERVICE_DIR="${HOME}/.config/systemd/user"

INSTALL_SYSTEMD=false
AUTOSSH=true
X11=false
X11_TRUSTED=false
VNC=false

display_topology_messages() {
	printf "%s\n" \
		"
${INDENT}+-----------------+    +--------------+               +------------------+ 
${INDENT}|                 |    |              |               |                  | 
${INDENT}|  Local Machine  |<-->|  Redirector  |<------------->|  Remote Machine  | 
${INDENT}|                 |<-->|              |<------------->|                  | 
${INDENT}|    (Internet)   |    |  (Internet)  |  Reverse SSH  |    (Intranet)    | 
${INDENT}+-----------------+    +--------------+               +------------------+ 
" \
		"${INDENT}${BOLD}Note${RESET}: this script should be executed on the remote machine." \
		"
${INDENT}+-------------------------------------------------------------+
${INDENT}|  Take Care!                                                 |
${INDENT}|  For security, the redirector should only be accessible:    |
${INDENT}|      1. in the intranet of your organization, or            |
${INDENT}|      2. with VPN service endorsed by your organization      |
${INDENT}+-------------------------------------------------------------+
"
}

display_help_messages() {
	display_topology_messages

	printf "%s\n" \
		"Usage: " \
		"${INDENT}$0 [option]" \
		""
	printf "%s\n" \
		"Options: " \
		"${INDENT}-h, --help                  Display help messages of this script" \
		"" \
		"${INDENT}-ef, --env-file ENV_FILE    Configuration file, to be named like '.env.1', '.env.2'..." \
		"" \
		"${INDENT}[--list-env-files]          List the first line of .env.* files" \
		"${INDENT}[--reindex-env-files]       Rename the .env.* files" \
		"${INDENT}[--list-systemd-services]   List systemd services" \
		"" \
		"${INDENT}[-x, --x11]                 Enable X11 forwarding" \
		"${INDENT}[-y, --x11-trusted]         Enable trusted X11 forwarding" \
		"${INDENT}[--vnc]                     Specify VNC connection" \
		"" \
		"${INDENT}[--usage]                   Display help messages based on given ENV_FILE" \
		"" \
		"${INDENT}[--install-dependencies]    Install ssh server and autossh" \
		"" \
		"${INDENT}[--install-systemd]         " \
		"${INDENT}[--install-systemd-email-notification] " \
		"${INDENT}[--uninstall-systemd]       " \
		"" \
		"${INDENT}[--verbose]                 Display help messages based on given ENV_FILE" \
		"${INDENT}[--no-autossh]              Use ssh instead of autossh for debugging" \
		"" \
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

	if [[ $VNC != true ]]; then
		printf "%s\n" "Usage: SSH twice

Step 1: on the local machine (anyuser@anyhost)

    ${GREEN}${BOLD}\$${RESET} ssh $redirector_user@$redirector_hostname -p $redirector_ssh_port [-YC]

Step 2: on the redirector ($redirector_user@$redirector_hostname) 

    ${GREEN}${BOLD}\$${RESET} ssh $USER@localhost -p $redirector_tunnel_ssh_port [-YC]
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
		error "Argument '--install-dependencies' has only been tested on Ubuntu."
	fi
	if ! has autossh; then
		sudo apt-get -qq update
		sudo apt-get install -y -qq autossh
		completed "Installed autossh by APT."
	fi
	sudo apt install -y -qq openssh-server
	sudo systemctl enable sshd --now
	completed "Enabled sshd now."
	exit 0
}

list_systemd_services() {
	SYSTEMD_COLORS=0 systemctl --user list-units -t service --full --all --no-legend --plain | grep 'nat-traversal@' | awk '{print $1}'
}

uninstall_systemd() {
	info "Uninstalling related systemd services."
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
			info "Found ${BOLD}nat-traversal@.service${RESET} in $BOLD${SYSTEMD_SERVICE_DIR}$RESET."
			info "Stopping and disabling all instances."
			list_systemd_services | xargs -i systemctl --user disable \{\} --now
			info "Removing the service template file."
			rm "${SYSTEMD_SERVICE_DIR}/nat-traversal@.service"
		fi
		set -e
	fi

	completed "Uninstalled related systemd services."
}

install_systemd() {
	sed -i "s|^Environment=SCRIPT_DIR=.*|Environment=SCRIPT_DIR=${SCRIPT_DIR}|" nat-traversal@.service

	uninstall_systemd

	info "Installing ${BOLD}nat-traversal@.service${RESET} into ${BOLD}$SYSTEMD_SERVICE_DIR${RESET}."

	cp "$SCRIPT_DIR/nat-traversal@.service" "$SYSTEMD_SERVICE_DIR/nat-traversal@.service"
	systemctl --user daemon-reload

	completed "Installed related systemd services."
}

install_systemd_email_notification() {
	if has "msmtp"; then
		completed "msmtp is found."
		warning "${BOLD}msmtp${RESET} should be configured manually."
		info "Installing ${BOLD}nat-traversal-notify@.service${RESET} into ${BOLD}$SYSTEMD_SERVICE_DIR${RESET}."

		sed -i "s|^Environment=SCRIPT_DIR=.*|Environment=SCRIPT_DIR=${SCRIPT_DIR}|" nat-traversal-notify@.service
		cp $SCRIPT_DIR/nat-traversal-notify@.service $SYSTEMD_SERVICE_DIR
		systemctl --user daemon-reload

		completed "Installed ${BOLD}nat-traversal-notify@.service${RESET} into ${BOLD}$SYSTEMD_SERVICE_DIR${RESET}."
	else
		error "msmtp not found."
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
	-ef | --env-file)
		ENV_FILE="$2"
		shift 2
		;;
	--x11 | -x)
		X11=true
		shift 1
		;;
	--x11-trusted | -y)
		X11_TRUSTED=true
		shift 1
		;;
	--vnc)
		VNC=true
		shift 1
		;;
	--install-dependencies)
		install_dependencies
		shift 1
		;;
	--install-systemd)
		install_systemd
		shift 1
		;;
	--install-systemd-email-notification)
		install_systemd_email_notification
		shift 1
		;;
	--uninstall-systemd)
		uninstall_systemd
		shift 1
		exit 0
		;;
	--list-env-files)
		list_env_files
		shift 1
		exit 0
		;;
	--list-systemd-services)
		list_systemd_services
		shift 1
		exit 0
		;;
	--reindex-env-files)
		reindex_env_files
		shift 1
		exit 0
		;;
	--verbose)
		VERBOSE=true
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

# Check if ENV_FILE is set
if [ -z "${ENV_FILE+x}" ]; then
	info "Configuration file is not given. Exiting."
	exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
	error "${ENV_FILE} not found. Exiting."
	exit 1
fi

info "Loading environment variables from the configuration file ${ENV_FILE}."
set -o allexport && source ${ENV_FILE} && set +o allexport

warning "The port ${BOLD}${YELLOW}$redirector_tunnel_ssh_port${RESET} should be available on ${BOLD}${YELLOW}$redirector_hostname${RESET}."
warning "To check port availability (for Ubuntu server $redirector_user@$redirector_hostname): 
1. port is not in use, e.g.
$BOLD$GREEN\$$RESET sudo lsof -i :$redirector_tunnel_ssh_port
2. firewall rules, e.g.
$BOLD$GREEN\$$RESET sudo ufw status | grep '$redirector_tunnel_ssh_port'"

debug 'Execute "ssh-keygen -R $redirector_hostname"'
set +e
ssh-keygen -R $redirector_hostname >/dev/null 2>&1
set -e

# Verify SSH connection first
info "Testing SSH connection to $redirector_user@$redirector_hostname..."
if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -p $redirector_ssh_port $redirector_user@$redirector_hostname "echo SSH connection test successful"; then
	error "Failed to establish SSH connection to redirector"
	exit 1
fi
completed "Tested SSH connection to $redirector_user@$redirector_hostname"

info "Constructing SSH reverse tunnel."
if $AUTOSSH = true; then
	# Create log directory
	LOG_DIR="$SCRIPT_DIR/logs"
	mkdir -p "$LOG_DIR"
	# Extract the suffix number from ENV_FILE (e.g., .env.7 -> 7)
	ENV_SUFFIX=$(basename "$ENV_FILE" | awk -F. '{print $NF}')
	LOG_FILE="$LOG_DIR/nat-traversal-$ENV_SUFFIX-$(date +%Y%m%d).log"
	info "Starting autossh tunnel, logging to $LOG_FILE"
	if $X11 = true; then
		autossh -M $remote_autossh_monitor_port -X -N -C -R "$redirector_tunnel_ssh_port:localhost:$remote_ssh_port" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$redirector_user@$redirector_hostname" -p $redirector_ssh_port \
			-v -E "$LOG_FILE" \
			-o "ExitOnForwardFailure=yes" \
			-o "ServerAliveInterval=60" \
			-o "ServerAliveCountMax=3"
	elif $X11_TRUSTED = true; then
		autossh -M $remote_autossh_monitor_port -Y -N -C -R "$redirector_tunnel_ssh_port:localhost:$remote_ssh_port" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$redirector_user@$redirector_hostname" -p $redirector_ssh_port \
			-v -E "$LOG_FILE" \
			-o "ExitOnForwardFailure=yes" \
			-o "ServerAliveInterval=60" \
			-o "ServerAliveCountMax=3"
	else
		autossh -M $remote_autossh_monitor_port -N -R "$redirector_tunnel_ssh_port:localhost:$remote_ssh_port" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$redirector_user@$redirector_hostname" -p $redirector_ssh_port \
			-v -E "$LOG_FILE" \
			-o "ExitOnForwardFailure=yes" \
			-o "ServerAliveInterval=60" \
			-o "ServerAliveCountMax=3"
	fi
else
	if $X11 = true; then
		ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -X -N -C -R "$redirector_tunnel_ssh_port:localhost:$remote_ssh_port" "$redirector_user@$redirector_hostname" -p $redirector_ssh_port
	elif $X11_TRUSTED = true; then
        echo "Hi"
		ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -Y -N -C -R "$redirector_tunnel_ssh_port:localhost:$remote_ssh_port" "$redirector_user@$redirector_hostname" -p $redirector_ssh_port
	else
		ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -N -R "$redirector_tunnel_ssh_port:localhost:$remote_ssh_port" "$redirector_user@$redirector_hostname" -p $redirector_ssh_port
	fi
fi
completed "Constructed SSH reverse tunnel."
completed "Done!"
