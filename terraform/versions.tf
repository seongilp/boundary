terraform {
  required_version = ">= 1.5"

  required_providers {
    boundary = {
      source  = "hashicorp/boundary"
      version = "~> 1.2"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
