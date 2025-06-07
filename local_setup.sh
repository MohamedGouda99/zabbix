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

echo "🔐 Creating Zabbix databases and user..."
sudo mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE DATABASE IF NOT EXISTS zabbix_proxy CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY 'zabbix';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
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
- name: Full Zabbix Stack on Localhost
  hosts: localhost
  become: true
  collections:
    - community.zabbix
  vars:
    zabbix_server_database: mysql
    zabbix_proxy_database: mysql
  tasks:

    - name: Install Zabbix Repo
      import_role:
        name: zabbix_repo

    - name: Install Zabbix Server
      import_role:
        name: zabbix_server
      vars:
        zabbix_server_dbhost: localhost
        zabbix_server_dbname: zabbix
        zabbix_server_dbuser: zabbix
        zabbix_server_dbpassword: zabbix
        zabbix_server_dbport: 3306
        zabbix_server_create_db: false
        zabbix_server_skip_db_setup: true

    - name: Install Zabbix Web UI
      import_role:
        name: zabbix_web
      vars:
        zabbix_web_server: apache
        zabbix_web_dbhost: localhost
        zabbix_web_dbname: zabbix
        zabbix_web_dbuser: zabbix
        zabbix_web_dbpassword: zabbix
        zabbix_web_dbport: 3306
        zabbix_web_timezone: Europe/Cairo
        zabbix_web_language: en_US
        zabbix_web_dbtype: mysql
        zabbix_web_database_type: mysql

    - name: Install Zabbix Proxy
      import_role:
        name: zabbix_proxy
      vars:
        zabbix_proxy_mode: active
        zabbix_server_host: localhost
        zabbix_proxy_dbhost: localhost
        zabbix_proxy_dbname: zabbix_proxy
        zabbix_proxy_dbuser: zabbix
        zabbix_proxy_dbpassword: zabbix
        zabbix_proxy_dbport: 3306
        zabbix_proxy_create_db: false
        zabbix_proxy_skip_db_setup: true

    - name: Install Zabbix Agent
      import_role:
        name: zabbix_agent
      vars:
        zabbix_agent_server: localhost
        zabbix_agent_listenport: 10050
        zabbix_agent_hostname: localhost
EOF

echo "🚀 Running Ansible playbook..."
ansible-playbook -i inventory.ini site.yml

echo "✅ Zabbix all-in-one local setup complete!"
