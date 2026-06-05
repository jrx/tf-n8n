terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "jrxhc"

    workspaces {
      name = "n8n"
    }
  }
}
