terraform {
	backend "s3" {}

	required_providers {
		aws = {
			source = "hashicorp/aws"
			version = "~> 4.64"
		}

		kubernetes = {
			source = "hashicorp/kubernetes"
			version = "~> 2.19.0"
		}

		cloudflare = {
			source = "cloudflare/cloudflare"
			version = "~> 3.0"
		}
	}
}

provider "aws" {
	region = data.external.env.result["AWS_REGION"]
}

provider "cloudflare" {
}

provider "kubernetes" {
	config_path = "~/.kube/config"
}
