#!/bin/bash

set -e

echo "📦 Installing Ansible and dependencies..."
sudo apt update -y
sudo apt install -y software-properties-common curl gnupg2 lsb-release ca-certificates apt-transport-https

echo "📦 Adding Ansible PPA..."
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt update -y
sudo apt install -y ansible

# Confirm Ansible is installed
if ! command -v ansible-galaxy >/dev/null 2>&1; then
  echo "❌ Ansible was not installed correctly or ansible-galaxy not found in PATH."
  exit 1
fi

echo "📁 Installing MariaDB 11.4 APT repo..."
curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | sudo bash -s -- --mariadb-server-version="mariadb-11.4"

echo "📦 Installing MariaDB Server..."
sudo apt update -y
sudo apt install -y mariadb-server mariadb-client python3-pymysql

echo "🚀 Starting and enabling MariaDB..."
sudo systemctl enable mariadb
sudo systemctl restart mariadb

echo "🔐 Creating Zabbix Proxy database and user..."
sudo mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS zabbix_proxy CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY 'zabbix';
GRANT ALL PRIVILEGES ON zabbix_proxy.* TO 'zabbix'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "📁 Creating Ansible project directory..."
mkdir -p ~/zabbix-local-setup
cd ~/zabbix-local-setup

echo "⬇️ Installing Ansible Galaxy Zabbix collection..."
ansible-galaxy collection install community.zabbix

echo "📄 Writing inventory.ini..."
cat > inventory.ini <<EOF
[all]
localhost ansible_connection=local
EOF

echo "📄 Writing site.yml playbook..."
cat > site.yml <<'EOF'
---
- name: Zabbix Proxy and Agent on Localhost
  hosts: localhost
  become: true
  collections:
    - community.zabbix
  vars:
    zabbix_proxy_database: mysql
    zabbix_proxy_create_db: false
    zabbix_proxy_skip_db_setup: true
  tasks:

    - name: Ensure MariaDB is running
      service:
        name: mariadb
        state: started
        enabled: true

    - name: Install Zabbix Repo
      import_role:
        name: zabbix_repo

    - name: Install Zabbix Proxy
      import_role:
        name: zabbix_proxy
      vars:
        zabbix_proxy_mode: active
        zabbix_server_host: 127.0.0.1
        zabbix_proxy_dbhost: 127.0.0.1
        zabbix_proxy_dbname: zabbix_proxy
        zabbix_proxy_dbuser: zabbix
        zabbix_proxy_dbpassword: zabbix
        zabbix_proxy_dbport: 3306

    - name: Install Zabbix Agent
      import_role:
        name: zabbix_agent
      vars:
        zabbix_agent_server: 127.0.0.1
        zabbix_agent_listenport: 10050
        zabbix_agent_hostname: localhost
EOF

echo "🚀 Running Ansible playbook (Proxy + Agent only)..."
ansible-playbook -i inventory.ini site.yml --skip-tags=zabbix_database

echo "✅ Zabbix Proxy + Agent installation complete on localhost!"
