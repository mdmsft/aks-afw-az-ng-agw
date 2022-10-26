terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~>2.0"
    }
  }
  backend "azurerm" {
    use_azuread_auth = true
    container_name   = "tfstate"
  }
}

locals {
  resource_suffix = "${var.project}-${var.environment}-${var.region}"
  context_name    = "${var.project}-${var.environment}"
}

provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  features {}
}

provider "azuread" {
  tenant_id     = var.tenant_id
  client_id     = var.client_id
  client_secret = var.client_secret
}
