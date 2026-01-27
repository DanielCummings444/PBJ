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
├── Dockerfile           # CLI-VM image definition
├── docker-compose.yml   # CLI-VM container config
├── cli-vm.sh            # CLI-VM management script
├── scripts/
│   ├── entrypoint.sh    # Container entrypoint with welcome banner
│   └── toolbox.sh       # Lists all installed CLI tools
├── workspace/           # Shared directory (host <-> VM)
├── sandbox/             # PBIP Analyzer MCP tool (see below)
├── .dockerignore
└── .gitignore
```

---

## PBIP Analyzer (MCP Tool)

The `sandbox/` directory contains a Power BI Project (PBIP) analysis tool
exposed as an MCP server. It parses `.pbip` projects (model.bim, TMDL,
and PBIR report formats), runs static analysis, and produces:

- **Quantitative findings** (JSON or formatted text)
- **Whitepaper-style reports** (Markdown) with executive summary,
  methodology, detailed findings, and a prioritized action plan

### Quick Start

```bash
cd sandbox

# Build the Docker image
./run.sh build

# Analyze the included sample project
./run.sh sample

# Analyze your own PBIP project
./run.sh analyze /data/projects/MyProject
```

### MCP Integration

To use as an MCP tool with Claude Desktop or any MCP client, add
`sandbox/mcp_config.json` to your MCP client configuration:

```json
{
  "mcpServers": {
    "pbip-analyzer": {
      "command": "docker",
      "args": [
        "compose", "-f", "sandbox/docker-compose.yml",
        "run", "--rm", "-i", "pbip-analyzer",
        "python", "-m", "pbip_analyzer.server"
      ]
    }
  }
}
```

### MCP Tools Exposed

| Tool | Description |
|------|-------------|
| `analyze_pbip` | Full analysis returning quantitative findings (JSON or text) |
| `analyze_pbip_report` | Full analysis returning a whitepaper-style Markdown report |
| `list_pbip_metrics` | Quick metrics-only scan (no detailed findings) |

### What Is Analyzed

| Area | Checks |
|------|--------|
| **Model Structure** | Table count, column count, calculated columns, documentation coverage, orphan tables |
| **DAX Quality** | Expression length, nesting depth, iterator usage, deprecated functions, missing VARs, format strings |
| **Relationships** | Bi-directional filters, many-to-many, inactive, circular paths, duplicate paths |
| **Report Design** | Page count, visual density, visual types, overlapping visuals |
| **Performance** | Storage modes, composite models, nested iterators, overall risk score |

### Sandbox Structure

```
sandbox/
├── Dockerfile                    # Python 3.12 slim image
├── docker-compose.yml            # Container config with volume mounts
├── run.sh                        # Management script
├── mcp_config.json               # MCP client configuration
├── requirements.txt
├── pyproject.toml
├── pbip_analyzer/
│   ├── server.py                 # MCP server (stdio)
│   ├── cli.py                    # Standalone CLI
│   ├── parsers/
│   │   ├── pbip_parser.py        # Project discovery & dispatch
│   │   ├── model_bim_parser.py   # model.bim (TMSL JSON) parser
│   │   ├── tmdl_parser.py        # TMDL format parser
│   │   └── report_parser.py      # PBIR/PBIR-Legacy parser
│   ├── analyzers/
│   │   ├── model_analyzer.py     # Schema & model structure
│   │   ├── dax_analyzer.py       # DAX expression quality
│   │   ├── relationship_analyzer.py  # Relationship design
│   │   ├── report_analyzer.py    # Report layout & UX
│   │   └── performance_analyzer.py   # Cross-cutting performance
│   ├── reporters/
│   │   ├── quantitative.py       # JSON/text metrics output
│   │   └── whitepaper.py         # Markdown whitepaper generator
│   └── models/
│       └── findings.py           # Data models (Finding, Metric, etc.)
├── samples/                      # Sample AdventureWorks PBIP project
├── projects/                     # Mount your PBIP projects here
└── reports/                      # Generated reports output
```
