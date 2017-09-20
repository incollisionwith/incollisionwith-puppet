# incollisionwith-puppet, a Puppet module for incollisionwith

This puppet module installs and configures incollisionwith.


## Getting started

First, install Puppet (`apt-get install puppet`) and then follow the instructions for setting up
[librarian-puppet](https://github.com/voxpupuli/librarian-puppet). In summary:

```shell
apt-get install librarian-puppet git pwgen iptables-persistent -y
cd /usr/share/puppet
librarian-puppet init
```

Your `Puppetfile` (`/usr/share/puppet/Puppetfile`) should contain something like:

```
forge 'https://forgeapi.puppetlabs.com'

mod 'incollisionwith', :git => 'https://github.com/incollisionwith/incollisionwith-puppet.git'
```

You'll need to make sure there's no `metadata` line.

This puppet module uses hiera to provide deployment-specific configuration data. Edit
`/etc/puppet/code/hiera/common.yaml` to contain:

```yaml
incollisionwith::secret_key: [secret]
incollisionwith::amqp_password: [secret]

# Firewall rules
firewall::allow_ssh_from: ['163.1.124.0/23', '129.67.100.0/22']
firewall::allow_http_from: ['163.1.0.0/16', '129.67.0.0/16']


incollisionwith::server_name: incollisionwith.uk
```

You'll want to replace each `[secret]` with a randomly-generated secret (using e.g. `pwgen 32`). You can do this with the following script:

```bash
while grep "\[secret\]" /etc/puppet/code/hiera/common.yaml; do
    sed -i "0,/\[secret]/{s/\[secret\]/$(pwgen 32 1)/}" /etc/puppet/code/hiera/common.yaml ;
done
```

Finally, create your main Puppet manifest, `/etc/puppet/manifests/site.pp`:

```puppet
node default {
    include incollisionwith
}
```

When this is all done, run:

```shell
cd /usr/share/puppet/
librarian-puppet install
puppet apply /etc/puppet/manifests/site.pp
```

(`librarian-puppet` needs to be run in `/usr/share/puppet/` as it works relative to the current directory)

And on subsequent runs:

```shell
cd /usr/share/puppet/
librarian-puppet update incollisionwith
puppet apply /etc/puppet/manifests/site.pp
```

If it doesn't succeed first time, create an issue with the error, and try it another time or two.

You'll want to configure DNS (or your VM host's `/etc/hosts` file) to resolve the server names given in the hiera data
above to the machine on which you've installed the IdM.
