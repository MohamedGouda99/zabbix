# Local Zabbix Installation with Ansible

This repository installs a complete Zabbix environment on a single host using
roles from [Ansible Galaxy](https://galaxy.ansible.com/).
The provided `local_setup.sh` script creates a temporary project directory,
installs the required roles and runs a playbook that deploys
Zabbix server, web, proxy and agent components on `localhost`.

## Usage

```
./local_setup.sh
```

The script installs Ansible, downloads the Galaxy roles, generates an inventory
and playbook and then executes it.  The playbook uses MariaDB on the same host
for both the server and proxy databases.

## Continuous Integration

A GitHub Actions workflow runs the playbook on every commit to ensure the
installation succeeds.  This provides basic verification that the Galaxy roles
and playbook continue to work.
