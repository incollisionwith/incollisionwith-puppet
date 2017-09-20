class incollisionwith::firewall {
   stage { 'fw_pre':  before  => Stage['main']; }
   stage { 'fw_post': require => Stage['main']; }

   class { 'incollisionwith::firewall::pre':
     stage => 'fw_pre',
   }

   class { 'incollisionwith::firewall::post':
     stage => 'fw_post',
   }

  resources { "firewall":
     purge => true
  }
}
