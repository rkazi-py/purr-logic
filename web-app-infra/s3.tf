# Random suffix for bucket name uniqueness
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 Bucket for MongoDB backups
resource "aws_s3_bucket" "backups" {
  bucket        = "${var.project_name}-mongodb-backups-${random_id.bucket_suffix.hex}"
  force_destroy = true
  
  tags = {
    Name        = "${var.project_name}-mongodb-backups"
    Environment = var.environment
    Purpose     = "Database Backups"
  }
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket lifecycle configuration (FIXED)
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  
  rule {
    id     = "backup_lifecycle"
    status = "Enabled"
    
    # ADD THIS: Filter is required
    filter {}
    
    expiration {
      days = var.backup_retention_days
    }
    
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
    
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# S3 Bucket public access block (intentionally disabled for insecure setup)
resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id
  
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 Bucket policy (insecure - allows public read)
resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.backups.arn}/*"
      }
    ]
  })
  
  depends_on = [aws_s3_bucket_public_access_block.backups]
}