Zabbix Deployment with [Ansible](http://docs.ansible.com/playbooks.html)
========================================================================

Automate the installation of Zabbix server, agents and plugins:

* Zabbix server
* Zabbix proxy
* Zabbix agent
* JMX gateway

### Preparation

1. Install Ansible ([instructions](http://docs.ansible.com/intro_installation.html))
1. Get the playbook from the GitHub repository
1. Create [inventory](http://docs.ansible.com/intro_inventory.html) file from [this template](hosts.empty) and add the Zabbix hosts

```
> cat hosts

...
[zabbix-server]
zabbix-server.example.com

[zabbix-client:children]

[zabbiz-client-only]
zabbix-client-1.example.com
zabbix-client-2.example.com
zabbix-client-3.example.com
```

### Zabbix server deployment

The procedure consists of 3 steps of which the 2nd one is manual and executes by you:

1. Install server software packages
1. Connect to server with browser and complete the configuration
1. Install agent on the server host

The deployment is split into 2 phases because you have to connect to the server with browser and input some config parameters, as per server installation instruction. If there is a way to get around it please share it.

```bash
$ ansible-playbook -v -i hosts site.yml --limit zabbix-server -t server
...

# now switch to your browser and connect to the server
# and complete the configuration, then come back here

$ ansible-playbook -v -i hosts site.yml --limit zabbix-server -t agent
```

Options can be set at runtime to change the playbook actions:

* _zabbix_remove_stale_version_ -- uninstall packages, drop database, remove files (default=false)

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

### Note

* If [passwordless login](http://linuxconfig.org/passwordless-ssh) is not enabled on the target hosts, use the "-k" option
* If your user account on the target hosts requires password to execute _sudo_, then "-K" option is needed

### Issues

* Creating MySQL schema will fail due to [bug](http://stackoverflow.com/questions/36770317/why-is-my-mysql-import-failing-w-ansible) in the __mysql_db__ Ansible module. The workaround is to extract the sql file from the compressed gz file, place it in the home directory and change this [roles/zabbix-server/vars/main.yml](var file) and point it to the extracted file.

### TODOs

* [LDAP authenticaiton setup](https://github.com/CumulusNetworks/ansible-role-activedirectory-auth-client) on the server
* Add support to run the playbook on RedHat, Fedora amd Ubuntu 16
* Deployment of Zabbix proxy server
* Fix the bug that breaks the MySQL schema creation and submit PR to Ansible
* Create host screen after registering an agent host with Zabbix server
* ~~Deployment of JMX Gateway~~
