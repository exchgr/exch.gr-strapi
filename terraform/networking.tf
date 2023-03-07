resource "aws_vpc" "exch-gr" {
	cidr_block = "10.0.0.0/16"

	tags = {
		Name = "exch-gr"
	}
}

resource "aws_subnet" "exch-gr-public" {
	vpc_id = aws_vpc.exch-gr.id
	cidr_block = "10.0.1.0/24"
	availability_zone = "us-east-1a"
	map_public_ip_on_launch = true

	tags = {
		Name = "exch-gr-public"
	}
}

resource "aws_subnet" "exch-gr-private" {
	vpc_id = aws_vpc.exch-gr.id
	cidr_block = "10.0.2.0/24"
	availability_zone = "us-east-1a"
	map_public_ip_on_launch = false

	tags = {
		Name = "exch-gr-private"
	}
}

resource "aws_internet_gateway" "exch-gr" {
	vpc_id = aws_vpc.exch-gr.id

	tags = {
		Name = "exch-gr"
	}
}

resource "aws_eip" "exch-gr" {
	vpc = true
	depends_on = [aws_internet_gateway.exch-gr]

	tags = {
		Name = "exch-gr"
	}
}

resource "aws_nat_gateway" "exch-gr" {
	subnet_id = aws_subnet.exch-gr-public.id
	connectivity_type = "public"
	allocation_id = aws_eip.exch-gr.id
	depends_on = [aws_internet_gateway.exch-gr]
}
