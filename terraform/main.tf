provider "aws" {}

terraform {
  backend "s3" {
    bucket = "aguterraform.tfstate"
    key    = "webapp/web"
    region = "eu-west-1"
  }
}

data "terraform_remote_state" "core" {
  backend = "s3"
  config {
    bucket = "${var.bucket_name}"
    key    = "${var.bucket_core_infra_key}"
    region = "eu-west-1"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

data "aws_subnet_ids" "all" {
  vpc_id = "${data.terraform_remote_state.core.vpc_core_id}"
}

resource "aws_instance" "webapp" {
  count = 2
  ami           = "${data.aws_ami.ubuntu.id}"
  instance_type = "t2.micro"
  subnet_id = "${element(data.aws_subnet_ids.all.ids, count.index)}"
  associate_public_ip_address = true
  key_name = "key-arnaud"
  user_data = "${data.template_file.Website.rendered}"
  vpc_security_group_ids = ["${aws_security_group.sgWebApp.id}"]
  tags {
    Name = "Appli AGU ${count.index}"
  }
}

resource "aws_elb" "webapp"{
  name = "webapp"
  subnets = ["${data.aws_subnet_ids.all.ids}"]
  security_groups = ["${aws_security_group.sgWebApp.id}"]
  
  listener{
    instance_port = 80
    instance_protocol = "http"
    lb_port = 80
    lb_protocol = "http"
  }
  health_check{
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 2
    target = "HTTP:80/"
    interval = 5
  }
}

data "template_file" "Website"{
  template = "${file("${path.module}/user-data.tpl")}"
  vars{
	username = "web site AGU"
  }
}

resource "aws_security_group" "sgWebApp" {
  name        = "sgWebApp"
  description = "Filter SSH & HTTP"
  vpc_id      = "${data.terraform_remote_state.core.vpc_core_id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
  tags{
	Name = "SG-WebApp"
  }
}

resource "aws_elb_attachment" "webapp" {
  count = 2
  elb      = "${aws_elb.webapp.id}"
  instance = "${element(aws_instance.webapp.*.id, count.index)}"
}
