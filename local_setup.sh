#!/bin/bash
set -e

echo "📦 Installing Ansible and dependencies..."
sudo apt-get update -y
sudo apt-get install -y software-properties-common curl gnupg2 lsb-release ca-certificates apt-transport-https python3-pymysql

echo "📦 Adding Ansible PPA..."
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt-get update -y
sudo apt-get install -y ansible

echo "⬇️ Installing Ansible Galaxy Zabbix collection..."
ansible-galaxy collection install community.zabbix

echo "📁 Creating Ansible project directory..."
mkdir -p ~/zabbix-local-setup
cd ~/zabbix-local-setup

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
    zabbix_proxy_dbhost: 127.0.0.1
    zabbix_proxy_dbport: 3306
    zabbix_proxy_dbname: zabbix_proxy
    zabbix_proxy_dbuser: zabbix
    zabbix_proxy_dbpassword: zabbix
    zabbix_proxy_manage_database: true
  tasks:
    - name: Install Zabbix Repo
      import_role:
        name: zabbix_repo

    - name: Install Zabbix Proxy
      import_role:
        name: zabbix_proxy
      vars:
        zabbix_proxy_mode: active
        zabbix_server_host: 127.0.0.1

    - name: Install Zabbix Agent
      import_role:
        name: zabbix_agent
      vars:
        zabbix_agent_server: 127.0.0.1
        zabbix_agent_listenport: 10050
        zabbix_agent_hostname: localhost
EOF

echo "🚀 Running Ansible playbook..."
ansible-playbook -i inventory.ini site.yml

echo "✅ Zabbix Proxy + Agent (with DB) setup completed via Ansible!"
