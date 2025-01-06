#!/usr/bin/env bash
INDENT='  '
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
email_notify_on_failure() {
	if has 'msmtp'; then
		debug "Found msmtp. Version $(msmtp --version)."
	else
		error "msmtp not found. Skip email notification."
		return 1
	fi

	# Store content and escape HTML special characters
	local content="$1"
	local email="${2:-$(git config --global user.email)}"
	content=$(echo "$content" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'\''/\&#39;/g')
	# Convert newlines to <br> tags
	content=$(echo "$content" | sed ':a;N;$!ba;s/\n/<br>/g')
	if [ -z "$email" ]; then
		error "Email not provided and not found in Git global user configuration."
		return 1
	fi
	local subject="NAT Traversal Fails"
	local body="
<html>
    <head>
        <style>
            body {
                font-family: Arial, sans-serif;
                font-size: 12px;
            }
            .label {
                font-weight: bold;
            }
            pre {
                white-space: pre-wrap;
                margin: 0;
                font-family: monospace;
            }
        </style>
    </head>
    <body>
    <p><span class=\"label\">Content of the Environment File:</span><br><pre>$content</pre></p>
    </body>
</html>
"
	echo "Subject: $subject" >email.txt
	echo "Content-Type: text/html; charset=UTF-8" >>email.txt
	echo "MIME-Version: 1.0" >>email.txt
	echo "" >>email.txt
	echo "$body" >>email.txt
	msmtp -a default "$email" <email.txt
	rm email.txt
}
