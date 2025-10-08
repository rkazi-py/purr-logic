# Key Pair for MongoDB EC2 access
resource "aws_key_pair" "mongodb" {
  key_name   = "${var.project_name}-mongodb-key"
  public_key = var.mongodb_public_key
  
  tags = {
    Name        = "${var.project_name}-mongodb-key"
    Environment = var.environment
  }
}

# IAM role for MongoDB backup to S3
resource "aws_iam_role" "mongodb_backup" {
  name = "${var.project_name}-mongodb-backup-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
  
  tags = {
    Name        = "${var.project_name}-mongodb-backup-role"
    Environment = var.environment
  }
}

resource "aws_iam_policy" "mongodb_backup" {
  name        = "${var.project_name}-mongodb-backup-policy"
  description = "Policy for MongoDB backup to S3"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:PutObjectAcl"
        ]
        Resource = [
          aws_s3_bucket.backups.arn,
          "${aws_s3_bucket.backups.arn}/*"
        ]
      }
    ]
  })
  
  tags = {
    Name        = "${var.project_name}-mongodb-backup-policy"
    Environment = var.environment
  }
}


resource "aws_iam_role_policy_attachment" "mongodb_backup" {
  role       = aws_iam_role.mongodb_backup.name
  policy_arn = aws_iam_policy.mongodb_backup.arn
}

# Overly permissive policy
resource "aws_iam_role_policy_attachment" "mongodb_ec2_full_access" {
  role       = aws_iam_role.mongodb_backup.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_instance_profile" "mongodb_backup" {
  name = "${var.project_name}-mongodb-backup-profile"
  role = aws_iam_role.mongodb_backup.name
  
  tags = {
    Name        = "${var.project_name}-mongodb-backup-profile"
    Environment = var.environment
  }
}

# MongoDB EC2 Instance
resource "aws_instance" "mongodb" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.mongodb_instance_type
  key_name               = aws_key_pair.mongodb.key_name
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.mongodb.id]
  iam_instance_profile   = aws_iam_instance_profile.mongodb_backup.name
  
  user_data = base64encode(templatefile("${path.module}/scripts/mongodb-setup.sh", {
    s3_bucket = aws_s3_bucket.backups.bucket
    region    = var.aws_region
  }))
  
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = false
    
    tags = {
      Name        = "${var.project_name}-mongodb-root"
      Environment = var.environment
    }
  }
  
  # Additional EBS volume for MongoDB data
  ebs_block_device {
    device_name           = "/dev/xvdf"
    volume_type           = "gp3"
    volume_size           = 50
    delete_on_termination = true
    encrypted             = false
    
    tags = {
      Name        = "${var.project_name}-mongodb-data"
      Environment = var.environment
    }
  }
  
  tags = {
    Name        = "${var.project_name}-mongodb"
    Environment = var.environment
    Type        = "Database"
  }
  
  lifecycle {
    ignore_changes = [ami]
  }
}