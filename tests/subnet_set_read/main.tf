# Core tests:
#   - Do all the combinations of known inputs produce expected outputs?
#   - Can we discover pre-existing subnets together with their route tables?
#   - Can we create a shared route table?
#   - Can we discover a pre-existing shared route table?
#
# Boilerplate tests:
#   - Can we call each module twice?

variable "switchme" {}

# The code below fetches Availability Zones but leaves out the Local Zones and Wavelength Zones.
data "aws_availability_zones" "this" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  az_a = data.aws_availability_zones.this.names[0]
  az_b = data.aws_availability_zones.this.names[1]
  az_c = data.aws_availability_zones.this.names[2]
}

locals {
  vpcname = "test4-vpc"
  subnets_main = {
    "10.0.10.0/24" = { az = local.az_a, set = "my" }
    "10.5.20.0/24" = { az = local.az_b, set = "my" }
    "10.5.30.0/24" = { az = local.az_a, set = "second", route_table_name = "test4-rt" } # TODO no need for a shared route if we test it in the tgw_read or similar
    "10.0.40.0/24" = { az = local.az_b, set = "second", route_table_name = "test4-rt" }
  }
  subnets_read_main = {
    "one"     = { az = local.az_a, create_subnet = false, set = "my" }
    "eleven"  = { az = local.az_b, create_subnet = false, set = "my" }
    "sixteen" = { az = local.az_a, create_subnet = false, set = "second", create_route_table = false, route_table_name = "test4-rt" }
    "cat"     = { az = local.az_b, create_subnet = false, set = "second", create_route_table = false, route_table_name = "test4-rt" }
  }
  added_subnets_rt_read = {
    "10.0.50.0/24" = { az = local.az_a, set = "third", name = "test4-s1", create_route_table = false, route_table_name = "test4-rt" }
    "10.0.60.0/24" = { az = local.az_b, set = "third", name = "test4-s2", create_route_table = false, route_table_name = "test4-rt" }
  }
  subnets_read_rt_read = {
    "c"            = { az = local.az_a, create_subnet = false, name = "test4-s1", route_table_name = "test4-rt" }
    "d"            = { az = local.az_b, create_subnet = false, name = "test4-s2", route_table_name = "test4-rt" }
    "10.0.90.0/24" = { az = local.az_c } # minor test: while reading some existing subnets, can we add a new one?
  }
}

module "vpc" {
  for_each = toset([local.vpcname, "second"])
  source   = "../../modules/vpc"

  create_vpc              = true
  name                    = each.key
  cidr_block              = "10.0.0.0/16"
  secondary_cidr_blocks   = var.switchme ? ["10.5.0.0/16"] : ["10.4.0.0/16", "10.5.0.0/16", "10.6.0.0/16"]
  create_internet_gateway = false
  enable_dns_hostnames    = var.switchme
  global_tags             = { "Is DNS Enabled" = var.switchme }
}

module "subnet_sets" {
  for_each = toset(distinct([for _, v in local.subnets_main : v.set]))
  source   = "../../modules/subnet_set"

  name                = each.key
  vpc_id              = module.vpc[local.vpcname].id
  has_secondary_cidrs = module.vpc[local.vpcname].has_secondary_cidrs
  cidrs               = { for k, v in local.subnets_main : k => v if v.set == each.key }

  create_shared_route_table = each.key == "second" # the "second" gets true, all the others get false
}

### Reuse Existing Resources ###

module "vpc_read" {
  for_each = module.vpc
  source   = "../../modules/vpc"

  create_vpc              = false
  name                    = each.value.name
  create_internet_gateway = var.switchme # minor test: can we add an igw
}

module "added_subnet_sets_rt_read" {
  for_each = toset(distinct([for _, v in local.added_subnets_rt_read : v.set]))
  source   = "../../modules/subnet_set"

  name                = each.key
  vpc_id              = module.vpc_read[local.vpcname].id # test: can vpc_read module detect a vpc_id
  has_secondary_cidrs = module.vpc_read[local.vpcname].has_secondary_cidrs
  cidrs               = { for k, v in local.added_subnets_rt_read : k => v if v.set == each.key }

  depends_on = [module.subnet_sets]
}

module "subnet_set_read_main" {
  for_each = toset(distinct([for _, v in local.subnets_read_main : v.set]))
  source   = "../../modules/subnet_set"

  name                = each.key
  vpc_id              = module.vpc_read[local.vpcname].id # test: can vpc_read module detect a vpc_id
  has_secondary_cidrs = module.vpc_read[local.vpcname].has_secondary_cidrs
  cidrs               = { for k, v in local.subnets_read_main : k => v if v.set == each.key }

  depends_on = [module.subnet_sets]
}

module "subnet_set_read" {
  source = "../../modules/subnet_set"

  name                = "their" # Minor test case: can we discover subnets by individual names, not depending on a module-level `name = "my"`
  vpc_id              = module.vpc_read[local.vpcname].id
  has_secondary_cidrs = module.vpc_read[local.vpcname].has_secondary_cidrs
  cidrs               = local.subnets_read_rt_read

  depends_on = [module.subnet_sets, module.added_subnet_sets_rt_read]
}

module "subnet_set_read_sharedrt" {
  source = "../../modules/subnet_set"

  name                = "sharedrt"
  vpc_id              = module.vpc_read[local.vpcname].id
  has_secondary_cidrs = module.vpc_read[local.vpcname].has_secondary_cidrs
  cidrs = {
    "c" = { az = local.az_a, create_subnet = false, name = "test4-s1", route_table_name = "test4-rt" }
    "d" = { az = local.az_b, create_subnet = false, name = "test4-s2", route_table_name = "test4-rt" }
  }

  depends_on = [module.subnet_sets, module.added_subnet_sets_rt_read]
}

module "added_subnet_set" {
  source = "../../modules/subnet_set"

  name                = "added-"
  vpc_id              = module.vpc_read[local.vpcname].id
  has_secondary_cidrs = module.vpc_read[local.vpcname].has_secondary_cidrs
  cidrs = {
    "10.0.70.0/24" = { az = local.az_a }
    "10.0.80.0/24" = { az = local.az_b }
  }
}

### Test Results ###

output "is_subnet_cidr_correct" {
  value = (try(module.subnet_set_read.subnets[local.az_a].cidr_block, null) == "10.0.50.0/24")
}

output "is_subnet_name_correct" {
  value = (try(module.added_subnet_set.subnet_names[local.az_b], null) == "added-b")
}

output "is_subnet_id_not_null" {
  value = module.subnet_set_read.subnets[local.az_a].id != null
}

output "is_subnet_id_correct" {
  value = module.subnet_set_read.subnets[local.az_a].id == module.added_subnet_sets_rt_read["third"].subnets[local.az_a].id
}
