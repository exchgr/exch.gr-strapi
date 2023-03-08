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

resource "aws_route_table" "exch-gr-public" {
	vpc_id = aws_vpc.exch-gr.id
}

resource "aws_route" "exch-gr-public" {
	destination_cidr_block = "0.0.0.0/0"
	route_table_id = aws_route_table.exch-gr-public.id
	gateway_id = aws_internet_gateway.exch-gr.id
}

resource "aws_route_table_association" "exch-gr-public" {
	route_table_id = aws_route_table.exch-gr-public.id
	subnet_id = aws_subnet.exch-gr-public.id
}

resource "aws_route_table" "exch-gr-private" {
	vpc_id = aws_vpc.exch-gr.id
}

resource "aws_route" "exch-gr-private" {
	destination_cidr_block = "0.0.0.0/0"
	route_table_id = aws_route_table.exch-gr-private.id
	nat_gateway_id = aws_nat_gateway.exch-gr.id
}

resource "aws_route_table_association" "exch-gr-private" {
	route_table_id = aws_route_table.exch-gr-private.id
	subnet_id = aws_subnet.exch-gr-private.id
}

resource "aws_security_group" "exch-gr" {
	name = "exch-gr"
	vpc_id = aws_vpc.exch-gr.id

	ingress {
		protocol  = "tcp"
		from_port = 443
		to_port   = 1337
		cidr_blocks = ["0.0.0.0/0"]
	}

	ingress {
		protocol  = "udp"
		from_port = 443
		to_port   = 1337
		cidr_blocks = ["0.0.0.0/0"]
	}
}
