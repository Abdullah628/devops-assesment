# Network module — a custom VPC with a 3-tier subnet design across 2 AZs.
#
#   public       -> ALB + NAT gateway (internet-facing)
#   private_app  -> EKS worker nodes / pods (egress via NAT only)
#   private_db   -> RDS (NO internet route at all)
#
# No third-party modules — every resource is declared directly.

locals {
  az_count = length(var.azs)

  # Derive non-overlapping /20 subnets from the VPC CIDR so the caller only has
  # to supply one CIDR block. Offsets keep the three tiers well separated.
  public_cidrs      = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_app_cidrs = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 4)]
  private_db_cidrs  = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 8)]
}

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr
  # Required so the RDS endpoint resolves to a PRIVATE IP inside the VPC
  # (see docs/database-connectivity.md).
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-igw" })
}

# ---------- Public subnets ----------
resource "aws_subnet" "public" {
  count                   = local.az_count
  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-${var.azs[count.index]}"
    # EKS discovers public subnets for internet-facing load balancers here.
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# ---------- Private app subnets (EKS nodes) ----------
resource "aws_subnet" "private_app" {
  count             = local.az_count
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_app_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-app-${var.azs[count.index]}"
    # EKS uses these for internal load balancers and schedules nodes here.
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# ---------- Private DB subnets (isolated: no internet route) ----------
resource "aws_subnet" "private_db" {
  count             = local.az_count
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_db_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags              = merge(var.tags, { Name = "${var.name_prefix}-private-db-${var.azs[count.index]}" })
}

# ---------- NAT (single, in the first public subnet — cost-conscious) ----------
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name_prefix}-nat-eip" })
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = merge(var.tags, { Name = "${var.name_prefix}-nat" })
  depends_on    = [aws_internet_gateway.this]
}

# ---------- Route tables ----------
# Public: default route to the internet gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = merge(var.tags, { Name = "${var.name_prefix}-public-rt" })
}

resource "aws_route_table_association" "public" {
  count          = local.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private app: default route to the NAT gateway (outbound internet for image pulls).
resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }
  tags = merge(var.tags, { Name = "${var.name_prefix}-private-app-rt" })
}

resource "aws_route_table_association" "private_app" {
  count          = local.az_count
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app.id
}

# Private DB: NO default route. Only the implicit local VPC route exists, so the
# database cannot reach (or be reached from) the internet.
resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-private-db-rt" })
}

resource "aws_route_table_association" "private_db" {
  count          = local.az_count
  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db.id
}
