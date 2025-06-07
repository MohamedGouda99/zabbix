#!/bin/bash
set -e

echo "� Installing Ansible and dependencies..."
sudo apt-get update -y
sudo apt-get install -y software-properties-common curl gnupg2 lsb-release ca-certificates apt-transport-https python3-pymysql python3-netaddr openssh-client

echo "➕ Adding Ansible PPA..."
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt-get update -y
sudo apt-get install -y ansible

echo "⬇️ Installing Ansible Galaxy collection: community.zabbix"
ansible-galaxy collection install community.zabbix

echo "�️ Installing MariaDB 11.4..."
curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | sudo bash -s -- --mariadb-server-version=11.4
sudo apt-get update -y
sudo apt-get install -y mariadb-server

echo "� Starting MariaDB..."
sudo systemctl enable mariadb
sudo systemctl start mariadb

echo "�️ Creating Zabbix DB and user..."
sudo mysql -uroot <<EOF
CREATE DATABASE IF NOT EXISTS zabbix_proxy CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY 'zabbix';
GRANT ALL PRIVILEGES ON zabbix_proxy.* TO 'zabbix'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "� Preparing local Ansible project..."
mkdir -p ~/zabbix-local-setup/roles/user-management/tasks
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

echo "� Creating inventory..."
cat > inventory.ini <<EOF
[all]
localhost ansible_connection=local
EOF

echo "� Creating site.yml playbook..."
cat > site.yml <<EOF
---
- name: Setup Zabbix Agent and local users
  hosts: localhost
  become: true
  collections:
    - community.zabbix
  tasks:
    - name: Install Zabbix Agent via role
      include_role:
        name: community.zabbix.zabbix_agent
      vars:
        zabbix_agent_server: 127.0.0.1
        zabbix_agent_hostname: localhost
        zabbix_agent_listenport: 10050

    - name: Disable TLSPSKFile in Zabbix agent config
      lineinfile:
        path: /etc/zabbix/zabbix_agentd.conf
        regexp: '^TLSPSKFile='
        line: '#TLSPSKFile='
        state: present

    - name: Restart Zabbix Agent safely
      systemd:
        name: zabbix-agent
        state: restarted
        enabled: true

  roles:
    - user-management

  vars:
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
EOF

echo "�️ Creating user-management role..."
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

echo "� Running final playbook..."
ansible-playbook -i inventory.ini site.yml

echo "✅ Done! MariaDB, Zabbix Agent, and SSH users are configured."
echo "� SSH private keys saved to /opt/zabbix-ssh-keys/"
