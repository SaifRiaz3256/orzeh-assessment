environment = "prod"
location    = "koreacentral"

address_space                  = ["10.20.0.0/16"]
workload_subnet_prefix         = "10.20.1.0/24"
private_endpoint_subnet_prefix = "10.20.2.0/24"

storage_replication_type   = "GZRS" # zone-redundant in koreacentral + async copy to the paired region
storage_soft_delete_days   = 30
key_vault_soft_delete_days = 90
key_vault_purge_protection = true # deleted secrets/keys cannot be purged before retention ends
