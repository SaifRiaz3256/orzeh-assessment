# Partial configuration - values come from env/<env>.backend.hcl:
#   terraform init -backend-config=env/dev.backend.hcl
# State locking is native to the azurerm backend (blob lease on the state file).
terraform {
  backend "azurerm" {}
}
