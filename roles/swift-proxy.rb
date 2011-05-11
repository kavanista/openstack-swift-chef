name "swift-proxy"
description "A Swift Proxy server"
run_list(
      "recipe[swift::default]",
      "recipe[swift::proxy]"
)

