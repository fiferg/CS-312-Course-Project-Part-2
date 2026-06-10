# Minecraft Server on AWS — Infrastructure as Code

Fully automated provisioning and configuration of a Minecraft: Java Edition server on AWS EC2, using **Terraform** (infrastructure) and **Ansible** (server configuration). No AWS Management Console interaction required after initial credential setup.

---

## Background

### What are we doing?

This project deploys a Minecraft 1.21.4 Java Edition server on AWS. The server:

- Runs on an **EC2 t2.micro** instance (Ubuntu 24.04)
- Is accessible on the default Minecraft port **25565**
- **Auto-starts on reboot** via a `systemd` service
- **Shuts down gracefully** (world data is flushed before the process is killed)

### How does it work?

The pipeline is split into two stages:

1. **Terraform** provisions all AWS infrastructure: VPC, subnet, internet gateway, security group, key pair, and EC2 instance.
2. **Ansible** connects to the new instance over SSH and configures it: installs Java 21, downloads the Minecraft server JAR, accepts the EULA, writes `server.properties`, and installs a `systemd` service.

A single shell script (`setup.sh`) orchestrates both stages end-to-end.

---

## Requirements

### Tools

| Tool        | Minimum Version | Install                                                                 |
|-------------|-----------------|-------------------------------------------------------------------------|
| Terraform   | 1.5.0           | [developer.hashicorp.com/terraform/install](https://developer.hashicorp.com/terraform/install) |
| Ansible     | 2.14            | `pip install ansible`                                                   |
| AWS CLI     | 2.x             | [docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) |
| nmap        | any             | `brew install nmap` / `sudo apt install nmap`                           |

### AWS Credentials

This project uses **AWS Academy Learner Lab** credentials. To retrieve them:

1. Open your Learner Lab and click **AWS Details**
2. Copy the three credential values (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`)
3. Export them in your terminal before running any script:

```bash
export AWS_ACCESS_KEY_ID="your-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_SESSION_TOKEN="your-session-token"
export AWS_DEFAULT_REGION="us-east-1"
```

> ⚠️ Learner Lab sessions expire. Re-export fresh credentials if you see authentication errors.

### Your IP Address

Terraform restricts SSH access to your IP. Find it with:

```bash
curl -s https://checkip.amazonaws.com
```

You will be prompted for it during `terraform apply`, or you can set it in a `terraform.tfvars` file (see below).

---

## Pipeline Diagram

```
┌─────────────────────────────────────────────────────────────┐
│  Local Machine                                              │
│                                                             │
│  setup.sh                                                   │
│     │                                                       │
│     ├── 1. terraform init                                   │
│     │                                                       │
│     ├── 2. terraform apply ──────────────────────────────► AWS
│     │         Creates:                                      │   VPC + Subnet
│     │           • VPC / Subnet / IGW / Route Table          │   Internet Gateway
│     │           • Security Group (ports 22, 25565)          │   Security Group
│     │           • Key Pair (MC-Key.pem written locally)     │   EC2 t2.micro
│     │           • EC2 instance (Ubuntu 24.04)               │   (Ubuntu 24.04)
│     │                                                       │
│     ├── 3. Generate ansible/inventory.ini with public IP    │
│     │                                                       │
│     ├── 4. Wait for SSH to be ready on the instance         │
│     │                                                       │
│     └── 5. ansible-playbook ────────────────────────────► EC2
│               Installs:                                     │   Java 21
│                 • Java 21 (openjdk-21-jre-headless)         │   server.jar
│                 • Minecraft 1.21.4 server JAR               │   eula.txt
│                 • eula.txt (accepted)                       │   server.properties
│                 • server.properties                         │   minecraft.service
│                 • minecraft.service (systemd, auto-start)   │   (running ✅)
│                                                             │
└─────────────────────────────────────────────────────────────┘
                                                   │
                              Minecraft port 25565 │
                                                   ▼
                                         Players connect 🎮
```

---

## Commands to Run

### 1. Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/minecraft-server-iac.git
cd minecraft-server-iac
```

### 2. Export AWS credentials

```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
export AWS_DEFAULT_REGION="us-east-1"
```

### 3. (Optional) Pre-set your IP to avoid being prompted

Create `terraform/terraform.tfvars`:

```hcl
my_ip_cidr = "YOUR.PUBLIC.IP.HERE/32"
```

### 4. Make the scripts executable

```bash
chmod +x setup.sh destroy.sh
```

### 5. Run the full pipeline

```bash
./setup.sh
```

This single command runs all four stages (Terraform init → apply → inventory → Ansible). It takes roughly 3–5 minutes. When it finishes, you will see:

```
[setup] ✅ Done! Your Minecraft server is running.
[setup]    Public IP : 1.2.3.4
[setup]    Verify    : nmap -sV -Pn -p T:25565 1.2.3.4
[setup]    Connect   : add '1.2.3.4' as a server in Minecraft 1.21.4
```

### 6. Verify the server is running

```bash
nmap -sV -Pn -p T:25565 <instance_public_ip>
```

Expected output:

```
PORT      STATE SERVICE   VERSION
25565/tcp open  minecraft Minecraft 1.21.4 (Protocol: 767, ...)
```

### 7. Tear down all resources (when done)

```bash
./destroy.sh
```

---

## Connecting to the Minecraft Server

1. Launch **Minecraft: Java Edition 1.21.4**
2. Click **Multiplayer** → **Add Server** (or **Direct Connection**)
3. Enter the **Public IP** printed at the end of `setup.sh`
4. Click **Join Server**

---

## Repository Structure

```
minecraft-server-iac/
├── setup.sh                        # Orchestrates the full pipeline
├── destroy.sh                      # Tears down all AWS resources
├── .gitignore
├── terraform/
│   ├── main.tf                     # EC2, VPC, security group, key pair
│   ├── variables.tf                # Input variables (region, instance type, IP)
│   ├── outputs.tf                  # Public IP, SSH command, nmap command
│   └── providers.tf                # AWS, TLS, and local provider versions
└── ansible/
    ├── ansible.cfg                 # SSH settings, inventory path
    ├── playbook.yml                # Install Java, JAR, EULA, systemd service
    ├── inventory.ini               # Auto-generated by setup.sh
    └── templates/
        └── minecraft.service.j2    # systemd unit file (Jinja2 template)
```

---

## Design Notes

### Why not `user_data`?

The EC2 `user_data` field runs a script at boot time but offers no visibility into success or failure, no idempotency, and no easy way to parameterise the configuration. Ansible gives structured, repeatable, and inspectable configuration management.

### Graceful shutdown

A known issue in Part 1 was that the server was not shutting down properly. The `systemd` unit file in this project includes:

```ini
ExecStop=/bin/kill -s SIGTERM $MAINPID
TimeoutStopSec=60
```

`SIGTERM` triggers the Minecraft JVM's shutdown hook, which flushes all world data to disk before the process exits. The 60-second timeout gives the server time to save even large worlds cleanly.

---

## Sources

- [Terraform AWS Provider documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Ansible `systemd` module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/systemd_module.html)
- [Minecraft server download — Mojang](https://www.minecraft.net/en-us/download/server)
- [systemd unit file reference](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [GitHub Markdown syntax guide](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)
