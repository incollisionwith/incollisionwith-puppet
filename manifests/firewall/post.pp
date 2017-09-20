class incollisionwith::firewall::post {
  hiera("firewall::allow_ssh_from").each |Integer $index, String $source| {
    firewall {
      "100 allow SSH $index":
        dport  => 22,
        proto  => "tcp",
        action => "accept",
        source => $source;
    }
  }

  hiera("firewall::allow_http_from").each |Integer $index, String $source| {
    firewall {
      "100 allow HTTP and HTTPS $index":
        dport  => [80, 443],
        proto  => "tcp",
        action => "accept",
        source => $source;
    }
  }

  firewall { "999 drop all other requests":
    action => "drop",
  }
}
