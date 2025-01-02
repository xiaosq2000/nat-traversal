#!/usr/bin/env bash
has() {
	command -v "$1" 1>/dev/null 2>&1
}

email_notify_on_failure() {
	if has 'msmtp'; then
		echo
	else
		echo "msmtp not found. Skip email notification."
		return 1
	fi

	# Store content and escape HTML special characters
	local content="$1"
	content=$(echo "$content" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'\''/\&#39;/g')
	# Convert newlines to <br> tags
	content=$(echo "$content" | sed ':a;N;$!ba;s/\n/<br>/g')

	local email="${3:-$(git config --global user.email)}"
	if [ -z "$email" ]; then
		echo "Email not provided and not found in Git global user configuration."
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
