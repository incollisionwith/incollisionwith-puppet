define incollisionwith::app (
  $vcs_url,
  $app_package,
  $server_name,
  $flower_port,
  $additional_environment = [],
) {
  $home = "/srv/${name}"
  $user = "${name}"
  $repo = "${home}/repo"
  $venv = "${home}/venv"
  $docroot = "${home}/docroot"
  $wsgi = "${home}/app.wsgi"
  $static_root = "${home}/static"
  $manage_py = "${home}/manage.py"
  $python = "${venv}/bin/python"
  $celery_vhost = "${name}-celery"
  $env_file = "$home/env.sh"
  $keytab = "$home/krb5.keytab"
  $systemd_celery_service = "/etc/systemd/system/$name-celery.service"
  $systemd_flower_service = "/etc/systemd/system/$name-flower.service"

  $ssl_cert = "/etc/letsencrypt/live/${server_name}/cert.pem"
  $ssl_key = "/etc/letsencrypt/live/${server_name}/privkey.pem"

  $fixture = "$home/fixture.yaml"

  # Let's Encrypt
  $get_cert_initial = "/usr/bin/letsencrypt certonly --standalone -d ${server_name}"
  $get_cert_renew = "/usr/bin/letsencrypt certonly --webroot -w ${docroot} -d ${server_name}"
  exec { "letsencrypt-initial":
    command => $get_cert_initial,
    creates => $ssl_cert,
    before => Apache::Vhost["${name}-ssl"];
  }
  cron { "letsencrypt-renew":
    command => $get_cert_renew,
    minute => 45,
    hour => 9,
    monthday => 5,
    month => "*/2";
  }

  # Principal names
  $client_principal_name = "api/$server_name"
  $kadmin_principal_name = "$server_name/admin"

  # Secrets
  $django_secret_key = hiera("${name}::secret_key")
  $amqp_password = hiera("${name}::amqp_password")

  # Other hiera values
  $django_debug = hiera("${name}::debug", false) ? { true => "on", default => "off" }

  $application_environment = [
    "CELERY_BROKER_URL=amqp://${user}:${amqp_password}@localhost/$celery_vhost",
    "DJANGO_ALLOWED_HOSTS=$server_name",
    "DJANGO_DEBUG=$django_debug",
    "DJANGO_SETTINGS_MODULE=${app_package}.settings",
    "DJANGO_SECRET_KEY=$django_secret_key",
    "DJANGO_STATIC_ROOT=$static_root",
    "DJANGO_EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend",
    "BROKER_SSL=no",
    "BROKER_USERNAME=$user",
    "BROKER_PASSWORD=$amqp_password",
    "KRB5_KTNAME=$keytab",
    "KRB5_CLIENT_KTNAME=$keytab",
    "CELERYD_NODES=4",
    "CELERYD_PID_FILE=$home/celery.pid",
    "CELERYD_LOG_FILE=/var/log/${name}-celery.log",
    "CELERYD_LOG_LEVEL=info",
  ] + $additional_environment + hiera_array("${name}::additional_environment", [])

  user {
    $user:
      ensure => present,
      home => $home,
      managehome => true;
  }

  rabbitmq_user { $user:
    password => $amqp_password,
  }

  rabbitmq_vhost { $celery_vhost:
    ensure => present,
  }

  rabbitmq_user_permissions { "${user}@${celery_vhost}":
    configure_permission => '.*',
    read_permission      => '.*',
    write_permission     => '.*',
  }

  vcsrepo { $repo:
    ensure => present,
    provider => git,
    source => $vcs_url,
  }

  apache::vhost {
    "${name}-non-ssl":
      servername => $server_name,
      port => 80,
      docroot => "$docroot",
      redirect_status => 'permanent',
      redirect_dest   => "https://${server_name}/";
    "${name}-ssl":
      servername => $server_name,
      port => 443,
      docroot => "$docroot",
      ssl => true,
      ssl_cert => $ssl_cert,
      ssl_key => $ssl_key,
      wsgi_daemon_process => $name,
      wsgi_daemon_process_options => {
        processes => '2',
        threads => '15',
        display-name => '%{GROUP}',
        python-home => $venv,
        user => $user,
        group => $user,
      },
      wsgi_process_group => $name,
      wsgi_script_aliases  => { '/' => $wsgi },
      aliases => [
        { alias => '/static', path => $static_root },
        { alias => '/.well-known/acme-challenge', path => "$docroot/.well-known/acme-challenge" },
      ],
      directories => [
        { path => $static_root },
        { path => $docroot },
      ],
      proxy_pass => [
        { path => '/flower/', url => "http://localhost:$flower_port/"}
      ];
  }

  anchor {"${name}-ready":
    require => Exec["${name}-install-requirements"]
  }

  exec {
    "${name}-create-virtualenv":
      unless  => "/usr/bin/test -d $venv",
      command => "/usr/bin/virtualenv $venv --python=/usr/bin/python3",
      require => Package["python-virtualenv"];
    "${name}-install-requirements":
      command   => "$venv/bin/pip install -r $repo/requirements.txt",
      require   => Vcsrepo[$repo],
      refreshonly => true,
      subscribe => Exec["${name}-create-virtualenv"];
    "${name}-install-additional":
      command   => "$venv/bin/pip install flower",
      require   => Vcsrepo[$repo],
      refreshonly => true,
      subscribe => Exec["${name}-create-virtualenv"];
      "${name}-collectstatic":
        command => "$manage_py collectstatic --no-input",
        require => [Exec["${name}-install-requirements"],
                    File[$manage_py],
                    Class["rabbitmq"]];
    "${name}-migrate":
      command => "$manage_py migrate",
      user    => $user,
      require => [Exec["${name}-install-requirements"],
                  Postgresql::Server::Database[$user],
                  File[$manage_py],
                  Class["rabbitmq"]],
      before => Anchor["${name}-ready"];
    "${name}-initial-fixtures":
      command => "$manage_py loaddata initial",
      returns => [0, 1], # Don't worry if there are actually no such fixtures
      user    => $user,
      require => Exec["${name}-migrate"],
      before => Anchor["${name}-ready"];
  }

  file {
    $wsgi:
      content => template('incollisionwith/env.py.erb', 'incollisionwith/app.wsgi.erb'),
      notify  => Apache::Vhost["${name}-ssl"];
  }

  file {
    $manage_py:
      content => template('incollisionwith/venv-python-hashbang.erb', 'incollisionwith/env.py.erb', 'incollisionwith/manage.py.erb'),
      mode => '755';
    $static_root:
      ensure => directory;
    $systemd_celery_service:
      content => template("incollisionwith/celery.service.erb");
    $systemd_flower_service:
      content => template("incollisionwith/flower.service.erb");
    $env_file:
      content => template("incollisionwith/env.sh.erb");
    "/var/log/${name}-celery.log":
      ensure => present,
      content => '',
      replace => 'no',
      owner => $user,
      group => $user,
      mode => "600";
  }

  service {
    "$name-celery":
      ensure => running,
      require => [File[$systemd_celery_service], Anchor["${name}-ready"]];
    "$name-flower":
      ensure => running,
      require => [File[$systemd_flower_service], Anchor["${name}-ready"]];
  }

  postgresql::server::database { $user:
    owner => $user,
  }

  postgresql::server::role { $user:
  }

}
