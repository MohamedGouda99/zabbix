#!/bin/bash
set -e

echo "� Cleaning up old MariaDB list files..."
sudo rm -f /etc/apt/sources.list.d/mariadb.list.old_* || true

echo "� Installing Ansible and system dependencies..."
sudo apt update -y
sudo apt install -y software-properties-common curl gnupg2 lsb-release ca-certificates apt-transport-https python3-pymysql openssh-client

echo "➕ Adding Ansible PPA..."
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt update -y
sudo apt install -y ansible

echo "⬇️ Installing Ansible Galaxy collection: community.zabbix"
ansible-galaxy collection install community.zabbix

echo "� Installing MariaDB 11.4 from official MariaDB repo..."
curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | sudo bash -s -- --mariadb-server-version=11.4
sudo apt update -y
sudo apt install -y mariadb-server mariadb-client

echo "� Starting and enabling MariaDB..."
sudo systemctl enable mariadb
sudo systemctl start mariadb

echo "� Installing Zabbix Proxy 7.0 and Agent..."
wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-1+ubuntu$(lsb_release -rs)_all.deb
sudo dpkg -i zabbix-release_7.0-1+ubuntu$(lsb_release -rs)_all.deb
sudo apt update
sudo apt install -y zabbix-proxy-mysql zabbix-sql-scripts zabbix-agent

echo "�️ Recreating Zabbix Proxy DB and user..."
sudo mariadb -uroot <<EOF
DROP DATABASE IF EXISTS zabbix_proxy;
DROP USER IF EXISTS 'zabbix'@'localhost';
CREATE DATABASE zabbix_proxy CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER 'zabbix'@'localhost' IDENTIFIED BY 'zabbixDBpass';
GRANT ALL PRIVILEGES ON zabbix_proxy.* TO 'zabbix'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "� Verifying Zabbix DB connection..."
sudo mariadb -uzabbix -pzabbixDBpass -e "SHOW TABLES;" zabbix_proxy || { echo "❌ Zabbix user/password invalid"; exit 1; }

echo "� Importing Zabbix proxy schema..."
cat /usr/share/zabbix-sql-scripts/mysql/proxy.sql | mariadb -uzabbix -pzabbixDBpass zabbix_proxy

echo "� Preparing Ansible project structure..."
mkdir -p ~/zabbix-local-setup/{roles/{zabbix-proxy,user-management}/tasks,templates}
mkdir -p /opt/zabbix-ssh-keys
cd ~/zabbix-local-setup

echo "� Generating SSH keys..."
declare -A USER_KEYS
for username in devops analyst; do
  key_path="/opt/zabbix-ssh-keys/${username}.key"
  ssh-keygen -t rsa -b 2048 -f "${key_path}" -N "" -C "${username}@localhost"
  pubkey=$(cat "${key_path}.pub")
  USER_KEYS["$username"]="$pubkey"
done

echo "� Creating inventory.ini..."
cat > inventory.ini <<EOF
[all]
localhost ansible_connection=local
EOF

echo "� Creating Zabbix proxy config template..."
cat > templates/zabbix_proxy.conf.j2 <<EOF
Server=10.7.44.235
Hostname=Zabbix proxy 01
DBName=zabbix_proxy
DBUser=zabbix
DBPassword=zabbixDBpass
LogFile=/var/log/zabbix/zabbix_proxy.log
ConfigFrequency=100
TLSConnect=psk
TLSAccept=psk
TLSPSKFile=/etc/zabbix/zabbix_proxy.psk
TLSPSKIdentity=ZBX-PSK-01
EOF

echo "� Creating PSK encryption key..."
openssl rand -hex 32 | sudo tee /etc/zabbix/zabbix_proxy.psk >/dev/null
chmod 644 /etc/zabbix/zabbix_proxy.psk
chown zabbix:zabbix /etc/zabbix/zabbix_proxy.psk

echo "� Creating site.yml playbook..."
cat > site.yml <<EOF
---
- name: Setup Zabbix Agent, Proxy, and users
  hosts: localhost
  become: true
  collections:
    - community.zabbix

  vars:
    zabbix_agent_server: 127.0.0.1
    zabbix_agent_hostname: localhost
    zabbix_agent_listenport: 10050

    users_to_add:
      - name: devops
        groups: sudo
        ssh_key: "${USER_KEYS[devops]}"
      - name: analyst
        groups: ""
        ssh_key: "${USER_KEYS[analyst]}"

    users_to_remove:
      - name: tempuser

    users_to_disable:
      - name: hruser

  pre_tasks:
    - name: Comment out TLSPSKFile in agent config
      lineinfile:
        path: /etc/zabbix/zabbix_agentd.conf
        regexp: '^TLSPSKFile='
        line: '#TLSPSKFile='
      notify: Restart Zabbix Agent

  roles:
    - zabbix-proxy
    - user-management

  handlers:
    - name: Restart Zabbix Agent
      service:
        name: zabbix-agent
        state: restarted

    - name: Restart Zabbix Proxy
      service:
        name: zabbix-proxy
        state: restarted
EOF

echo "� Creating zabbix-proxy role tasks..."
cat > roles/zabbix-proxy/tasks/main.yml <<'EOF'
- name: Deploy Zabbix Proxy configuration
  template:
    src: zabbix_proxy.conf.j2
    dest: /etc/zabbix/zabbix_proxy.conf
    owner: root
    group: root
    mode: 0644
  notify: Restart Zabbix Proxy
EOF

echo "� Creating user-management role tasks..."
cat > roles/user-management/tasks/main.yml <<'EOF'
- name: Add users
  user:
    name: "{{ item.name }}"
    groups: "{{ item.groups }}"
    shell: /bin/bash
    state: present
    create_home: yes
  loop: "{{ users_to_add | default([]) }}"

- name: Add SSH keys
  authorized_key:
    user: "{{ item.name }}"
    key: "{{ item.ssh_key }}"
    state: present
  loop: "{{ users_to_add | default([]) }}"

- name: Disable users
  user:
    name: "{{ item.name }}"
    shell: /usr/sbin/nologin
  loop: "{{ users_to_disable | default([]) }}"

- name: Remove users and home
  user:
    name: "{{ item.name }}"
    state: absent
    remove: yes
  loop: "{{ users_to_remove | default([]) }}"
EOF

echo "� Running Ansible playbook..."
ansible-playbook -i inventory.ini site.yml

echo "✅ All done! Zabbix Proxy 7.0, Agent, MariaDB 11.4, encryption, and user config set up successfully."
echo "� SSH keys stored in /opt/zabbix-ssh-keys/"
