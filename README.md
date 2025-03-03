# NAT Traversal

This tool creates a secure SSH tunnel through NAT, allowing you to access your remote machine (located behind a firewall or NAT) from anywhere. It uses a redirector (middle server) and establishes a reverse SSH tunnel to maintain connectivity.

> [!WARNING]
> For security, the redirector should only be accessible:
> 1. In the intranet of your organization, or
> 2. With a VPN service endorsed by your organization
> 
> **DISCLAIMER**: The author of this tool are not responsible for any security vulnerabilities, data breaches, or other issues that may arise from improper deployment or usage of this software. Users implement this solution at their own risk and are solely responsible for ensuring proper security measures are in place. By using this software, you acknowledge that you understand the security implications and will take appropriate precautions to protect your systems and data.

![Logo](doc/illustration.png#gh-light-mode-only)
![Logo](doc/illustration-dark.png#gh-dark-mode-only)

## Tutorial

*Table of Contents*

* [Quick Start](#quick-start)
   * [0. Get Ready](#0-get-ready)
   * [1. Configure](#1-configure)
   * [2. Install Dependencies](#2-install-dependencies)
   * [3. Run](#3-run)
   * [4. Test](#4-test)
* [Advanced Setup](#advanced-setup)
   * [1. Run as Systemd Service](#1-run-as-systemd-service)
   * [2. SSH Shortcut](#2-ssh-shortcut)
   * [3. Configure Email Notifications](#3-configure-email-notifications)
   * [Other Handy Commands](#other-handy-commands)

### Quick Start

> [!NOTE]
> The tutorial is for my fellow UM students and it's a memo for myself. :)

> [!NOTE]
> The `setup.sh` script should be executed on the remote machine.

#### 0. Get Ready

1. Make sure you are accessible to a redirector server. 

> [!TIP]
> For SKL-IOTSC students, either one is fine:
> - [UM's HPCC](https://icto.um.edu.mo/teaching-learning-research/high-performance-computing-cluster-hpcc/)
> - [SKL-IOTSC's SICC](https://skliotsc.um.edu.mo/research/super-intelligent-computing-center/)

1. Understand the setup:
    - **Remote Machine**: The computer you want to access remotely (e.g., your lab PC or office workstation). This machine is typically behind a firewall or NAT and runs the setup script to establish the tunnel.
    - **Redirector**: An accessible server with a public IP or within your organization's network (e.g., a university computing cluster) that acts as a bridge.
    - **Local Machine**: The computer you are currently using (e.g., your laptop or personal device) from which you want to connect to your remote machine.

#### 1. Configure

Create a configuration file (e.g., `.env.1`, `.env.2`) with the following parameters:

```sh
# Example './.env.1': UM's HPCC
X11_TRUSTED=true
redirector_user=<your-student-id>
redirector_hostname=login0.coral.um.edu.mo
redirector_tunnel_ssh_port=<redirector_tunnel_ssh_port>
redirector_ssh_port=22
remote_autossh_monitor_port=<remote_autossh_monitor_port>
remote_ssh_port=22
remote_user=<username>
```

> [!NOTE]
> The naming convention of configuration files, `.env.<digit>`, is for systemd convenience.

Configuration parameters explained:
- `X11_TRUSTED`: Enable trusted X11 forwarding (optional)
- `redirector_user`: Your username on the redirector server
- `redirector_hostname`: The hostname or IP of the redirector
- `redirector_tunnel_ssh_port`: The port on the redirector to forward connections through **(must be available)**
- `redirector_ssh_port`: The SSH port on the redirector (usually 22)
- `remote_autossh_monitor_port`: A port for autossh to monitor the connection **(must be available)**
- `remote_ssh_port`: The SSH port on your remote machine (usually 22)
- `remote_user`: The username on your remote machine (`echo $USER`)

<!--> [!NOTE]-->
<!--> For VNC connections, add `VNC=true` to your configuration and set `remote_ssh_port` to the appropriate VNC port (5900 + display number).-->
<!---->
#### 2. Install Dependencies

```sh
sudo ./setup.sh --install-dependencies
```

This installs `autossh` and `openssh-server` for Ubuntu systems (using APT).

#### 3. Run

Construct the tunnel for debugging.

```sh
./setup.sh --env-file ./.env.1 -y --no-autossh
```

> [!TIP]
> - `--x11-trusted` or `-y`: Enable trusted X11 forwarding
> - `--no-autossh`: Use SSH instead of autossh (for debugging)

#### 4. Test

In a new shell, run the following command to get connection instructions for your specific configuration:

```sh
./setup.sh --env-file ./.env.1 --usage
```

Execute the command on the local machine.

### Advanced Setup

#### 1. Run as Systemd Service

```sh
# Install the systemd service template
./setup.sh --install-systemd

# Enable and start the service using configuration from .env.2
systemctl --user enable nat-traversal@2 --now

# Check service status
systemctl --user status nat-traversal@2
```

#### 2. SSH Shortcut

Configure your `~/.ssh/config`. Example:

```
Host <redirector_host>
  User <redirector_user>
  Port 22
  Hostname <redirector-hostname>
  IdentityFile ~/.ssh/id_rsa
  RequestTTY force
  ForwardX11 yes
  ForwardX11Trusted yes
  Compression yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host <remote_host>
  HostName localhost
  Port <remote_ssh_port>
  User <remote_user>
  ProxyJump <redirector_host>
  ForwardX11 yes
  ForwardX11Trusted yes
  Compression yes
  RequestTTY force
```

Then you can directly connect to your machine by:

```sh
ssh <remote_host>
```


#### 3. Configure Email Notifications

> [!Note] 
> You must have `msmtp` configured for email notifications to work.

```sh
./setup.sh --install-systemd-email-notification
# No need to enable the systemd service 
```

Example:
![example-email-notification](./doc/example-email-notification.png)


#### Other Handy Commands

List all available configurations:
```sh
./setup.sh --list-env-files
```

Renumber configuration files sequentially:
```sh
./setup.sh --reindex-env-files
```

List systemd services:
```sh
./setup.sh --list-systemd-services
```

<!--## VNC Setup-->
<!---->
<!--1. Install VNC server (e.g., [TurboVNC](https://github.com/TurboVNC/turbovnc/releases)) on your remote machine-->
<!--2. Start the VNC server:-->
<!--   ```sh-->
<!--   REMOTE_USER@REMOTE_MACHINE:~$ /opt/TurboVNC/bin/vncserver-->
<!--   ```-->
<!--3. Note the display number (e.g., `:2` means display number is `2`)-->
<!--4. Create a VNC configuration file (e.g., `.env.3`):-->
<!--   ```sh-->
<!--   VNC=true-->
<!--   redirector_user=<your-student-id>-->
<!--   redirector_hostname=dgx.sicc.um.edu.mo-->
<!--   redirector_tunnel_ssh_port=37081-->
<!--   redirector_ssh_port=22-->
<!--   remote_autossh_monitor_port=45851-->
<!--   # ${remote_ssh_port} = 5900 + ${display_number}-->
<!--   remote_ssh_port=5902-->
<!--   ```-->
<!--5. Start the tunnel:-->
<!--   ```sh-->
<!--   ./setup.sh --env-file ./.env.3-->
<!--   ```-->
<!--6. For connection instructions:-->
<!--   ```sh-->
<!--   ./setup.sh --env-file ./.env.3 --usage-->
<!--   ```-->
