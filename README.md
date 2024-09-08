# NAT Traversal

Access your PC from anywhere, anytime using a redirector for SSH reverse tunneling.

**Note: For security reasons, the redirector should only be accessible within an intranet or VPN!**

## Quick start

### 0. Get the redirector ready

For the University of Macau, either one is fine.

- [UM's HPCC](https://icto.um.edu.mo/teaching-learning-research/high-performance-computing-cluster-hpcc/).
- [SKL-IOTSC's SICC](https://skliotsc.um.edu.mo/research/super-intelligent-computing-center/)

### 1. Configuration 

Here is an example for using SICC's login node as a redirector. Save the file as './.env.1'.

```sh
VNC=false
redirector_user=学号
redirector_hostname=login0.coral.um.edu.mo
redirector_tunnel_ssh_port=36324
redirector_ssh_port=22
remote_autossh_monitor_port=45861
remote_ssh_port=22
```

### 2. Install

```sh
sudo ./setup.sh [--install-dependencies] [--install-systemd]
```

### 3. Run

```sh
./setup.sh --env-file ./.env.1
```

### 4. Use

For guidance, check it out.

```sh
./setup.sh --env-file ./.env.1 --usage
```

## Run as systemd service

Note: your configuration path must be './.env.${number}' to use the provided systemd service template.

```sh
sudo ./setup.sh --install-systemd
# For example, use '.env.2' file as your configuration.
sudo systemctl enable nat-traversal@2 --now
# You may have a check on it.
sudo systemctl status nat-traversal@2 
```

## VNC

Install VNC server on your remote machine and VNC client on your local machine. 

[TurboVNC](https://github.com/TurboVNC/turbovnc/releases).

Start VNC server on your remote PC. For example,

```sh
REMOTE_USER@REMOTE_MACHINE:~$ /opt/TurboVNC/bin/vncserver
```

It may give,

```sh
Desktop 'TurboVNC: REMOTE_MACHINE:2 (REMOTE_USER)' started on display REMOTE_MACHINE:2

Starting applications specified in /opt/TurboVNC/bin/xstartup.turbovnc
Log file is ~/.vnc/REMOTE_MACHINE:2.log
```

Note that the display number is "2". Then modify the configuration file, for example, './.env.3'.

```sh
VNC=true
redirector_user=学号
redirector_hostname=dgx.sicc.um.edu.mo
redirector_tunnel_ssh_port=37081
redirector_ssh_port=22
remote_autossh_monitor_port=45851
# ${remote_ssh_port} = 5900 + ${display_number}
remote_ssh_port=5902
```

For guidance, check it out.

```sh
./setup.sh --env-file ./.env.3 --usage
```
