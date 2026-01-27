# PBJ CLI-VM

A Docker-based virtual machine packed with CLI tools for development, networking, data processing, and DevOps workflows.

## Quick Start

```bash
# Build the image
./cli-vm.sh build

# Start the VM in the background
./cli-vm.sh start

# Drop into an interactive shell
./cli-vm.sh shell
```

## Commands

| Command | Description |
|---|---|
| `./cli-vm.sh build` | Build the Docker image |
| `./cli-vm.sh start` | Start the container (detached) |
| `./cli-vm.sh stop` | Stop the container |
| `./cli-vm.sh shell` | Open an interactive bash session |
| `./cli-vm.sh exec <cmd>` | Run a one-off command inside the VM |
| `./cli-vm.sh status` | Show container status |
| `./cli-vm.sh logs` | Tail container logs |
| `./cli-vm.sh destroy` | Remove container and volumes |
| `./cli-vm.sh rebuild` | Full rebuild from scratch |

### Examples

```bash
# Run a command directly
./cli-vm.sh exec python3 -c "print('hello from the VM')"

# Process JSON
./cli-vm.sh exec bash -c "echo '{\"name\":\"pbj\"}' | jq .name"

# Check what tools are available
./cli-vm.sh exec toolbox
```

## Installed Tools

Run `toolbox` inside the VM to see all tools with versions. Here's a summary:

### Editors
vim, nano

### File & Text Processing
jq, yq, csvkit, sed, awk, ripgrep (`rg`), ag, fzf, tree, zip/unzip, p7zip, rsync

### Networking
curl, wget, httpie, nmap, netcat, socat, dig, ping, traceroute, mtr, tcpdump, whois, ssh

### Version Control
git, git-lfs, GitHub CLI (`gh`)

### Languages & Runtimes
Python 3, pip, Node.js 22.x, npm

### DevOps & Cloud
Docker CLI, kubectl, Terraform, AWS CLI v2

### Database Clients
psql (PostgreSQL), mysql, redis-cli, sqlite3

### System & Process
htop, tmux, screen, lsof, strace, sysstat

## Configuration

### Workspace

The `./workspace/` directory on the host is mounted to `/workspace` inside the VM. Place files there to access them from inside the container.

### Custom Init Script

Create a `.cli-vmrc` file in the workspace directory to run custom setup on container start:

```bash
# workspace/.cli-vmrc
export MY_VAR="hello"
alias ll="ls -la"
```

### Docker Socket

The host's Docker socket is mounted into the VM by default, allowing you to run Docker commands from inside the VM. Remove the volume mount in `docker-compose.yml` if this is not needed.

### Resource Limits

CPU and memory limits can be adjusted in `docker-compose.yml` under `deploy.resources`.

## Project Structure

```
PBJ/
├── Dockerfile           # Image definition with all CLI tools
├── docker-compose.yml   # Container orchestration config
├── cli-vm.sh            # Management script (build/start/shell/exec/etc.)
├── scripts/
│   ├── entrypoint.sh    # Container entrypoint with welcome banner
│   └── toolbox.sh       # Lists all installed CLI tools
├── workspace/           # Shared directory (host <-> VM)
├── .dockerignore
└── .gitignore
```
