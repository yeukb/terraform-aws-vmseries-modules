### eu-west-3 ###

provider "aws" {
  region = "eu-west-3"
}

module "transit_gateway" {
  source = "../../modules/transit_gateway"

  name = "west-tgw"
  asn  = 65001
  route_tables = {
    "from_security_vpc" = {
      create = true
      name   = "${var.prefix_name_tag}from_security"
    }
    "from_spoke_vpc" = {
      create = true
      name   = "${var.prefix_name_tag}from_spokes"
    }
  }
}

### eu-north-1 ###

provider "aws" {
  alias  = "north"
  region = "eu-north-1"
}

module "transit_gateway_north" {
  source = "../../modules/transit_gateway"
  providers = {
    aws = aws.north
  }

  name = "north-tgw"
  asn  = 65000
  route_tables = {
    "from_spoke_vpc" = {
      create = true
      name   = "${var.prefix_name_tag}from_spokes"
    }
  }
}

### cross-region ###

module "transit_gateway_peering" {
  source = "../../modules/transit_gateway_peering"
  providers = {
    aws      = aws
    aws.peer = aws.north
  }

  local_transit_gateway_id = module.transit_gateway.transit_gateway.id
  peer_transit_gateway_id  = module.transit_gateway_north.transit_gateway.id

  local_attachment_tags  = { Name = "west-attach" }
  local_route_table_tags = { Name = "west-route-table" }
  peer_route_table_tags  = { Name = "north-route-table" }
}
