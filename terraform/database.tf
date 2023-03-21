resource "random_password" "exch-gr" {
	length = 64
	special = false
}

resource "aws_db_subnet_group" "exch-gr" {
	name = "exch-gr"

	subnet_ids = [
		aws_subnet.exch-gr-private-us-east-1a.id,
		aws_subnet.exch-gr-private-us-east-1b.id,
	]
}

resource "aws_rds_cluster" "exch-gr" {
	cluster_identifier = "exch-gr"
	engine = "aurora-postgresql"
	storage_encrypted = true
	apply_immediately = true

	# credentials
	database_name = "exchgr"
	master_username = "root"
	master_password = random_password.exch-gr.result

	# logs
	enabled_cloudwatch_logs_exports = ["postgresql"]

	# networking
	db_subnet_group_name = aws_db_subnet_group.exch-gr.name
	vpc_security_group_ids = [aws_security_group.exch-gr.id]

	availability_zones = [
		"us-east-1a",
		"us-east-1b",
	]
}

resource "aws_rds_cluster_instance" "exch-gr" {
	count = 2
	identifier = "exch-gr-${count.index}"
	cluster_identifier = aws_rds_cluster.exch-gr.id
	instance_class = "db.t4g.medium"
	engine = aws_rds_cluster.exch-gr.engine
	engine_version = aws_rds_cluster.exch-gr.engine_version
}
