Zabbix Deployment with [Ansible](http://docs.ansible.com/playbooks.html)
========================================================================

This repository contains a minimal set of roles that install and
configure a complete Zabbix environment on Ubuntu 24.04 hosts.  Zabbix 7.2
packages are available for Noble under the "release" repository.  The
`zabbix-repository` role installs the `zabbix-release` package to enable the
official apt repository.  MariaDB packages still come from the Jammy archive.
It can
deploy the following components:

* Zabbix server
* Zabbix proxy
* Zabbix agent
* JMX gateway

Hosts are also configured with a systemd timer that periodically runs
`ansible-pull` so configuration changes pushed to your Git repository are
applied automatically.

### Preparation

1. Install Ansible ([instructions](http://docs.ansible.com/intro_installation.html))
2. Clone this repository
   ```bash
   git clone https://github.com/example/zabbix-ansible.git
   cd zabbix-ansible
   ```
3. Edit **group_vars/all.yml** to match your environment.  Important variables include
   - `ansible_pull_repo` – Git URL used by `ansible-pull`
   - `ansible_pull_branch` – branch name to track
   - `zabbix_proxy_server` – hostname or IP of the Zabbix server
   - `users_present` / `users_absent` / `users_disabled` – user management lists
   - `mariadb_version` – MariaDB version to install (default 11.4)
4. Adjust the **hosts** file with the inventory of servers, proxies and clients.
5. The CI workflow runs the playbook with `ci_testing=true` so package installations are skipped during automated tests.

```
> cat hosts

[all:vars]
ansible_connection=local

[zabbix-server]
localhost

[zabbix-client]
localhost

[zabbix-proxy]
localhost
```

Edit this file to point to your actual hosts before running the playbook.

### Zabbix server deployment

Installing the server requires a short manual step to finish the web
installer. Run the playbook twice as shown below:

The `mariadb` role will configure the MariaDB 11.4 repository and ensure
the database server is installed before Zabbix packages are deployed.

1. Install the packages and create the database
2. Open the Zabbix web interface and complete the configuration wizard
3. Run the playbook again to configure the local agent

```bash
$ ansible-playbook -v -i hosts site.yml --limit zabbix-server -t server
...
# Complete the web installer in your browser and then run
$ ansible-playbook -v -i hosts site.yml --limit zabbix-server -t agent
```

Options can be set at runtime to change the playbook actions:

* _zabbix_remove_stale_version_ -- uninstall packages, drop database, remove files (default=false)

### Zabbix proxy deployment

Deploy a proxy along with MariaDB 11.4 and the Zabbix agent. The `mariadb`
role configures the official repository and installs the database server:

```bash
$ ansible-playbook -v -i hosts site.yml --limit zabbix-proxy
```

### Zabbix agent deployment

The playbook will register the remote hosts with the Zabbix server at the end of the installation.

```bash
$ ansible-playbook -v -i hosts site.yml -t agent --limit zabbix-client
...
```

Options can be set at runtime to change the playbook actions:

* _zabbix_remove_stale_version_ -- uninstall packages and remove remove files (default=false)
* _zabbix_register_with_server_ -- register hosts with Zabbix server (default=yes)
* _zabbix_api_connection_method_ -- make Zabbix server REST api calls from your laptop (default=local)

### User management

The `user-management` role uses three variables to control accounts:

```yaml
users_present:
  - name: alice
    ssh_key: "ssh-ed25519 AAA..."
users_disabled:
  - bob
users_absent:
  - olduser
```

Run the playbook after editing these lists to ensure accounts are created,
disabled or removed accordingly.

After all roles run the `verify-services` role checks that the Zabbix services
are active, enabled and writing logs. Any failures will stop the playbook with
an error.

### Note

* If [passwordless login](http://linuxconfig.org/passwordless-ssh) is not enabled on the target hosts, use the "-k" option
* If your user account on the target hosts requires password to execute _sudo_, then "-K" option is needed

### Issues

* The Ansible `mysql_db` module cannot import the gzipped schema shipped with the package. The playbook now extracts `create.sql` automatically so the database schema loads without manual steps.

### TODOs

* [LDAP authenticaiton setup](https://github.com/CumulusNetworks/ansible-role-activedirectory-auth-client) on the server
* Add support to run the playbook on RedHat, Fedora amd Ubuntu 16
* ~~Deployment of Zabbix proxy server~~
* Fix the bug that breaks the MySQL schema creation and submit PR to Ansible
* Create host screen after registering an agent host with Zabbix server
* ~~Deployment of JMX Gateway~~

### Automated management with ansible-pull

This repository includes a role that installs an `ansible-pull` systemd timer.
After the first run of `site.yml` each host will periodically execute
`ansible-pull` and apply any changes committed to your repository.  The
timer interval is controlled by the `ansible_pull_frequency` variable in
`group_vars/all.yml` (default `1h`).

Make sure `ansible_pull_repo` points at your Git repository before you
bootstrap a host.

### Continuous integration

The repository ships with a simple GitHub Actions workflow.  Every pull
request runs `ansible-playbook` with `ci_testing=true` to verify the
playbook syntax without attempting to download packages.
