# NAT Traversal

Access your PC from anywhere, anytime using a redirector for SSH reverse tunneling.

**Note: For security reasons, the redirector should only be accessible within an intranet or VPN.**

## Quick start

### 0. Get the redirector ready

For UM, either one is fine.

- [UM's HPCC](https://icto.um.edu.mo/teaching-learning-research/high-performance-computing-cluster-hpcc/).
- [SKL-IOTSC's SICC](https://skliotsc.um.edu.mo/research/super-intelligent-computing-center/)

### 1. Configuration 

By default, the configuration files are named '.env.${number}'. Here is an example for using SICC's login node as a redirector.

```sh
remote_user=${YOUR_STUDENT_ID}
remote_hostname=dgx.sicc.um.edu.mo
remote_tunnel_ssh_port=${ANY_AVAILABLE_PORT_ON_SERVER}
remote_ssh_port=22
local_autossh_monitor_port=${ANY_AVAILABLE_PORT_ON_YOUR_PC}
local_ssh_port=22
```

### 2. Install

```sh
sudo ./setup.sh --ensure-dependencies
```

### 3. Run

```sh
./setup.sh --env-file ./.env.1
```

## Run as systemd service

```sh
sudo ./setup.sh --systemd
# using .env.2 configuration
sudo systemctl enable nat-traversal@2 --now
```
