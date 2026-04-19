# =============================================================================
# VPC Module — hermes networking baseline
#
# Creates:
#   - VPC with DNS support (required for VPC Interface Endpoints)
#   - Public subnets (NAT GW, future load balancers) in 2 AZs
#   - Private subnets (ROSA worker nodes, RDS) in 2 AZs
#   - One NAT Gateway per AZ (HA; same-AZ routing eliminates cross-AZ data charges)
#   - Elastic IPs for NAT GWs (output for sharing with customer Solace ops team)
#   - Per-AZ private route tables (AZ isolation on NAT GW failure)
#   - Single public route table
#   - VPC Flow Logs → S3 (90-day lifecycle, enforced TLS, optional KMS CMK)
#   - Route 53 Resolver Query Logging → same S3 bucket
# =============================================================================

terraform {
  required_version = ">= 1.14.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id            = data.aws_caller_identity.current.account_id
  region                = data.aws_region.current.name
  flow_logs_bucket_name = "hermes-vpc-logs-${local.account_id}-${local.region}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
    Destination = "platform"
  }
}

# =============================================================================
# VPC
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "hermes-vpc-${var.environment}"
  })
}

# =============================================================================
# Internet Gateway
# =============================================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "hermes-igw-${var.environment}"
  })
}

# =============================================================================
# Subnets
# =============================================================================

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name                     = "hermes-public-${var.availability_zones[count.index]}-${var.environment}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(local.common_tags, {
    Name                              = "hermes-private-${var.availability_zones[count.index]}-${var.environment}"
    Tier                              = "private"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

# =============================================================================
# Elastic IPs — one per AZ for NAT Gateways
# EIP public IPs are outputs — shared with customer Solace ops team for
# allowlisting on the Solace broker firewall.
# =============================================================================

resource "aws_eip" "nat" {
  count = length(var.availability_zones)

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "hermes-nat-eip-${var.availability_zones[count.index]}-${var.environment}"
  })

  depends_on = [aws_internet_gateway.main]
}

# =============================================================================
# NAT Gateways — one per AZ, placed in public subnets
# Per-AZ placement prevents cross-AZ NAT data transfer charges and ensures
# private subnets survive a single NAT GW failure.
# =============================================================================

resource "aws_nat_gateway" "main" {
  count = length(var.availability_zones)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "hermes-nat-${var.availability_zones[count.index]}-${var.environment}"
  })

  depends_on = [aws_internet_gateway.main]
}

# =============================================================================
# Route Tables
# =============================================================================

# Public — single table shared by all public subnets; routes to IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "hermes-rt-public-${var.environment}"
    Tier = "public"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private — one table per AZ, each routes to the same-AZ NAT Gateway
resource "aws_route_table" "private" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "hermes-rt-private-${var.availability_zones[count.index]}-${var.environment}"
    Tier = "private"
  })
}

resource "aws_route" "private_nat" {
  count = length(var.availability_zones)

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[count.index].id
}

resource "aws_route_table_association" "private" {
  count = length(var.private_subnet_cidrs)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# =============================================================================
# VPC Flow Logs — S3 bucket
# KMS encryption applied when var.flow_logs_kms_key_arn is provided.
# Before the KMS module (US-E1-004) is applied, this falls back to SSE-S3.
# =============================================================================

resource "aws_s3_bucket" "vpc_logs" {
  bucket = local.flow_logs_bucket_name

  tags = merge(local.common_tags, {
    Name = local.flow_logs_bucket_name
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vpc_logs" {
  bucket = aws_s3_bucket.vpc_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.flow_logs_kms_key_arn != "" ? "aws:kms" : "AES256"
      kms_master_key_id = var.flow_logs_kms_key_arn != "" ? var.flow_logs_kms_key_arn : null
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "vpc_logs" {
  bucket = aws_s3_bucket.vpc_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "vpc_logs" {
  bucket = aws_s3_bucket.vpc_logs.id

  rule {
    id     = "expire-flow-logs"
    status = "Enabled"

    expiration {
      days = var.flow_logs_retention_days
    }
  }
}

resource "aws_s3_bucket_policy" "vpc_logs" {
  bucket = aws_s3_bucket.vpc_logs.id

  # Public access block must be applied before a bucket policy that references ACLs
  depends_on = [aws_s3_bucket_public_access_block.vpc_logs]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonTLSAccess"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.vpc_logs.arn,
          "${aws_s3_bucket.vpc_logs.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
      {
        Sid       = "AWSLogDeliveryWrite"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.vpc_logs.arn}/AWSLogs/${local.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = local.account_id
          }
        }
      },
      {
        Sid       = "AWSLogDeliveryAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.vpc_logs.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
        }
      }
    ]
  })
}

# =============================================================================
# VPC Flow Log
# =============================================================================

resource "aws_flow_log" "main" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = aws_s3_bucket.vpc_logs.arn

  destination_options {
    file_format        = "plain-text"
    per_hour_partition = true
  }

  tags = merge(local.common_tags, {
    Name = "hermes-flow-log-${var.environment}"
  })
}

# =============================================================================
# Route 53 Resolver Query Logging
# Logs all DNS queries from resources in this VPC to the same S3 bucket.
# The AWSLogDeliveryWrite bucket policy statement above covers both VPC
# flow logs and DNS query logs (both use delivery.logs.amazonaws.com).
# =============================================================================

resource "aws_route53_resolver_query_log_config" "main" {
  name            = "hermes-dns-query-logs-${var.environment}"
  destination_arn = aws_s3_bucket.vpc_logs.arn

  tags = merge(local.common_tags, {
    Name = "hermes-dns-query-logs-${var.environment}"
  })
}

resource "aws_route53_resolver_query_log_config_association" "main" {
  resolver_query_log_config_id = aws_route53_resolver_query_log_config.main.id
  resource_id                  = aws_vpc.main.id
}
