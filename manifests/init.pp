class incollisionwith (
  $base_domain = 'example.org',
) {
  $required_packages = [
    "python-virtualenv",
    "gcc",
    "python3-dev",
    "libxslt1-dev",
    "libxml2-dev",
    "libxmlsec1-dev",
    "bison",
  ]

  include postgresql::server

  package { $required_packages:
    ensure => installed
  }
  include incollisionwith::broker
  include incollisionwith::firewall
  include incollisionwith::web

  incollisionwith::app {
    incollisionwith:
      app_package => "incollisionwith",
      vcs_url => "https://github.com/incollisionwith/incollisionwith",
      server_name => hiera('incollisionwith::server_name'),
      flower_port => 5555;
  }
}