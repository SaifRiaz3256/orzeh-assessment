environment = "dev"
location    = "koreacentral"

address_space                  = ["10.10.0.0/16"]
workload_subnet_prefix         = "10.10.1.0/24"
private_endpoint_subnet_prefix = "10.10.2.0/24"

storage_replication_type   = "LRS"
storage_soft_delete_days   = 7
key_vault_soft_delete_days = 7
key_vault_purge_protection = false # lets dev be destroyed and recreated freely
