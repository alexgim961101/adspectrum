locals {
  # AZ 이름을 키로 서브넷을 생성한다. count 인덱스를 쓰면 azs 목록의 순서가 바뀔 때
  # 기존 서브넷이 파괴 후 재생성되므로, 멱등성을 위해 for_each를 쓴다.
  public_subnets  = { for idx, az in var.azs : az => var.public_subnet_cidrs[idx] }
  private_subnets = { for idx, az in var.azs : az => var.private_subnet_cidrs[idx] }
}

# EKS 노드 등록과 파드 DNS 해석에 VPC DNS 기능이 모두 필요하다.
resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-igw" }
}

# 퍼블릭 서브넷: ALB와 NAT Gateway만 배치한다.
# kubernetes.io/role/elb 태그로 AWS Load Balancer Controller가 서브넷을 자동 탐색한다.
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.name}-public-${each.key}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# 프라이빗 서브넷: EKS 노드와 파드가 위치한다.
# VPC CNI가 파드마다 서브넷 IP를 할당하므로 퍼블릭보다 넓은 대역을 준다.
resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = {
    Name                                        = "${var.name}-private-${each.key}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    # Karpenter가 노드를 띄울 서브넷을 이 태그로 찾는다. ID를 매니페스트에 박으면
    # VPC를 다시 만들 때마다 매니페스트를 고쳐야 한다.
    "karpenter.sh/discovery" = var.cluster_name
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "${var.name}-nat" }
}

# 비용 절감을 위해 NAT Gateway는 AZ당 하나가 아니라 전체 1개만 둔다.
# 트레이드오프: 이 AZ 장애 시 프라이빗 서브넷의 아웃바운드가 전부 끊기고,
# 다른 AZ 노드의 아웃바운드 트래픽에는 AZ 간 전송 요금이 붙는다.
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[var.azs[0]].id

  # NAT Gateway는 소속 서브넷이 인터넷에 도달 가능해야 정상 동작한다.
  # 라우팅 테이블만으로는 순서가 보장되지 않아 IGW 의존성을 명시한다.
  depends_on = [aws_internet_gateway.this]

  tags = { Name = "${var.name}-nat" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name}-public" }
}

# NAT가 1개이므로 프라이빗 라우팅 테이블도 1개면 충분하다.
# AZ별 NAT로 전환한다면 이 테이블을 AZ별로 분리해야 한다.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = { Name = "${var.name}-private" }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
