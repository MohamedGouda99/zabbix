#!/bin/bash

set -e

echo "📦 Installing Ansible..."
sudo apt update -y
sudo apt install -y ansible

echo "📁 Creating Ansible project directory..."
mkdir -p ~/zabbix-local-setup
cd ~/zabbix-local-setup

echo "📄 Writing requirements.yml..."
cat > requirements.yml <<'R'
roles:
  - name: community.zabbix.zabbix_repo
  - name: community.zabbix.zabbix_server
  - name: community.zabbix.zabbix_web
  - name: community.zabbix.zabbix_proxy
  - name: community.zabbix.zabbix_agent
R

echo "⬇️ Installing Ansible Galaxy roles..."
ansible-galaxy install -r requirements.yml

echo "📄 Writing inventory.ini..."
cat > inventory.ini <<'R'
[all]
localhost ansible_connection=local
R

echo "📄 Writing site.yml playbook..."
cat > site.yml <<'R'
---
- name: Setup Zabbix Repositories
  hosts: localhost
  become: true
  roles:
    - community.zabbix.zabbix_repo

- name: Install Zabbix Server
  hosts: localhost
  become: true
  vars:
    zabbix_server_dbhost: localhost
    zabbix_server_dbname: zabbix
    zabbix_server_dbuser: zabbix
    zabbix_server_dbpassword: zabbix
    zabbix_server_dbport: 3306
    zabbix_server_create_db: true
    zabbix_server_dbtype: mysql
  roles:
    - community.zabbix.zabbix_server

- name: Install Zabbix Web UI
  hosts: localhost
  become: true
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
  roles:
    - community.zabbix.zabbix_web

- name: Install Zabbix Proxy
  hosts: localhost
  become: true
  vars:
    zabbix_proxy_mode: active
    zabbix_server_host: localhost
    zabbix_proxy_dbhost: localhost
    zabbix_proxy_dbname: zabbix_proxy
    zabbix_proxy_dbuser: zabbix
    zabbix_proxy_dbpassword: zabbix
    zabbix_proxy_dbport: 3306
    zabbix_proxy_create_db: true
    zabbix_proxy_dbtype: mysql
  roles:
    - community.zabbix.zabbix_proxy

- name: Install Zabbix Agent
  hosts: localhost
  become: true
  vars:
    zabbix_agent_server: localhost
    zabbix_agent_listenport: 10050
    zabbix_agent_hostname: localhost
  roles:
    - community.zabbix.zabbix_agent
R

echo "🚀 Running Ansible playbook..."
ansible-playbook -i inventory.ini site.yml

echo "✅ Zabbix installation complete on localhost!"
