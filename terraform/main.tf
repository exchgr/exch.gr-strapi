terraform {
	backend "s3" {}

	required_providers {
		aws = {
			source = "hashicorp/aws"
			version = "~> 4.64"
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
