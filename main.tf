provider "aws" {
  region = "eu-central-1"
}


data "aws_availability_zones" "available" {
  state = "available"
}
data "aws_ecr_image" "service_image" {
  repository_name = "server-repo"
  image_tag       = "latest"
}
data "aws_ami" "latest_amazon_linux" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
data "aws_iam_policy_document" "instance-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}
data "aws_iam_policy" "AmazonECSServiceRolePolicy" {
  arn = "arn:aws:iam::aws:policy/aws-service-role/AmazonECSServiceRolePolicy"
}
data "aws_iam_policy" "AmazonECSTaskExecutionRolePolicy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
data "aws_iam_policy" "AmazonEC2ContainerServiceforEC2Role" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}


resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

resource "aws_iam_service_linked_role" "AWSServiceRoleForECS" {
  aws_service_name = "ecs.amazonaws.com"
}


resource "aws_iam_role" "AmazonEC2ContainerServiceforEC2Role" {
  name = "ecs-instance"
  path = "/"

  assume_role_policy = <<EOF
{
    "Version": "2008-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
}
EOF
}


resource "aws_iam_role" "ecsTaskExecutionRole" {
  assume_role_policy = data.aws_iam_policy_document.instance-assume-role-policy.json
  description        = "Allows ECS tasks to call AWS services on your behalf."
  name               = "ecsTaskExecutionRole"
  tags               = {}
}



resource "aws_iam_instance_profile" "instance" {
  name = "instance-profile"
  role = aws_iam_role.AmazonEC2ContainerServiceforEC2Role.name
}


resource "aws_iam_role_policy_attachment" "AmazonECSTaskExecutionRolePolicy-attach" {
  role       = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn = data.aws_iam_policy.AmazonECSTaskExecutionRolePolicy.arn
}


resource "aws_iam_policy_attachment" "AmazonEC2ContainerServiceforEC2Role" {
  name       = "ecs-instance"
  roles      = ["${aws_iam_role.AmazonEC2ContainerServiceforEC2Role.name}"]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}


resource "aws_key_pair" "deployer" {
  key_name   = "deployer"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCFAFrw4tYkx+e+sSGXGe7AcxJcY+h4434hbSd3YOTXe2natRvFImW6ziTjFSFaJLMxxEB4npq5UHHbrbhPv3fokIFV6yF58/q6veIfqQrSqDekgH877uobFI3rd+LxcwlpGI8ZQDqilmJczYTEKUX49qsEhcfGMkt01OLe+AU+08mMvwqOGKpLcUA3sDFBsT+Qo+lhOVeRHdHk3EXf0+P/SnL7epW2XfA3I60kCO3+s+CmIaWxtpmsw2vKjiF+MLDduSRwwTVbSwwv+lKUcbu01W4uylwI7S8mBESPDkc5WctJMUzs/DX5q6EHDqLrLct8yYynavwz9h0DuAVNIHlv"
}


resource "aws_default_security_group" "default" {
  vpc_id = aws_default_vpc.default.id

  ingress {
    protocol  = "-1"
    self      = true
    from_port = 0
    to_port   = 0
  }

  ingress {
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    protocol         = "tcp"
    from_port        = 8080
    to_port          = 8080
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_ecr_repository" "server-repo" {
  name                 = "server-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}


resource "aws_ecr_repository_policy" "server-repo-policy" {
  repository = aws_ecr_repository.server-repo.name
  policy     = <<EOF
  {
    "Version": "2008-10-17",
    "Statement": [
      {
        "Sid": "adds full ecr access to the repository",
        "Effect": "Allow",
        "Principal": "*",
        "Action": [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetLifecyclePolicy",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
      }
    ]
  }
  EOF
}


resource "aws_ecs_cluster" "server-cluster" {
  name = "server-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}


resource "aws_ecs_task_definition" "service" {
  family                   = "service"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn
  memory                   = 1024
  cpu                      = 1024
  container_definitions = jsonencode([
    {
      name      = "server"
      image     = "200082615054.dkr.ecr.eu-central-1.amazonaws.com/server-repo:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
        }
      ]
    }
  ])

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_ecs_service" "server" {
  name            = "server"
  cluster         = aws_ecs_cluster.server-cluster.id
  task_definition = aws_ecs_task_definition.service.arn
  iam_role        = aws_iam_service_linked_role.AWSServiceRoleForECS.arn
  desired_count   = 2
  depends_on = [
    data.aws_iam_policy.AmazonECSServiceRolePolicy,
    aws_ecs_task_definition.service
  ]


  load_balancer {
    elb_name       = aws_elb.web.name
    container_name = "server"
    container_port = "8080"
  }


  placement_constraints {
    type       = "memberOf"
    expression = "attribute:ecs.availability-zone in [${data.aws_availability_zones.available.names[0]}, ${data.aws_availability_zones.available.names[1]}]"
  }


  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_launch_template" "web" {
  name_prefix            = "WebServer-Highly-Available-LC-"
  image_id               = data.aws_ami.latest_amazon_linux.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = ["${aws_default_security_group.default.id}"]
  key_name               = aws_key_pair.deployer.key_name
  iam_instance_profile {
    name = aws_iam_instance_profile.instance.name
  }
  instance_market_options {
    market_type = "spot"
  }
}


resource "aws_spot_fleet_request" "fleet" {
  iam_fleet_role       = "arn:aws:iam::200082615054:role/aws-service-role/spotfleet.amazonaws.com/AWSServiceRoleForEC2SpotFleet"
  target_capacity      = 2
  valid_until          = "2023-11-04T20:44:20Z"
  wait_for_fulfillment = "true"
  load_balancers       = [aws_elb.web.name]

  launch_template_config {
    launch_template_specification {
      id      = aws_launch_template.web.id
      version = aws_launch_template.web.latest_version
    }
  }
}


resource "aws_autoscaling_group" "web" {
  name                    = "ASG-${aws_launch_template.web.name}"
  min_size                = 2
  max_size                = 2
  min_elb_capacity        = 2
  health_check_type       = "ELB"
  vpc_zone_identifier     = [aws_default_subnet.default_az1.id, aws_default_subnet.default_az2.id]
  load_balancers          = [aws_elb.web.name]
  service_linked_role_arn = "arn:aws:iam::200082615054:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  depends_on = [
    aws_ecs_task_definition.service,
    aws_ecs_service.server,
    aws_spot_fleet_request.fleet,
    aws_elb.web,
    aws_launch_template.web
  ]

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_elb" "web" {
  name = "WebServer-HA-ELB"
  #availability_zones = [data.aws_availability_zones.available.names[0], data.aws_availability_zones.available.names[1]]
  subnets         = [aws_default_subnet.default_az1.id, aws_default_subnet.default_az2.id]
  security_groups = [aws_default_security_group.default.id]
  listener {
    lb_port           = 8080
    lb_protocol       = "HTTP"
    instance_port     = 8080
    instance_protocol = "HTTP"
  }
  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:8080/ping"
    interval            = 10
  }
  tags = {
    Name = "WebServer-Highly-Available-ELB"
  }
}


resource "aws_default_subnet" "default_az1" {
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_default_subnet" "default_az2" {
  availability_zone = data.aws_availability_zones.available.names[1]
}

#--------------------------------------------------
output "web_loadbalancer_url" {
  value = aws_elb.web.dns_name
}