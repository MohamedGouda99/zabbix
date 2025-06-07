# Local Zabbix Installation with Ansible

This repository installs a complete Zabbix environment on a single host using
the `community.zabbix` collection from [Ansible Galaxy](https://galaxy.ansible.com/).
The provided `local_setup.sh` script installs Ansible from its official PPA,
adds the MariaDB 11.4 repository, creates the Zabbix databases and then runs an
Ansible playbook that deploys the Zabbix server, web UI, proxy and agent
components on `localhost`.

## Usage

```
./local_setup.sh
```

The script installs Ansible, verifies that `ansible-galaxy` is available,
downloads the Zabbix collection, generates an inventory and playbook and then
executes it. The playbook uses MariaDB on the same host for both the server and
proxy databases.

## Continuous Integration

A GitHub Actions workflow runs the playbook on every commit to ensure the
installation succeeds.  This provides basic verification that the Galaxy collection
and playbook continue to work.
