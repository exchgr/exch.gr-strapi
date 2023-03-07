resource "aws_vpc" "exch-gr" {
	cidr_block = "10.0.0.0/16"

	tags = {
		Name = "exch-gr"
	}
}
