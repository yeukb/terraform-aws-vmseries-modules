# AWS Transit Gateway Peering

## Usage

This module creates both sides of a TGW Peering thus it needs two different AWS providers specified in the `providers` meta-argument.
The local side requires the provider entry named `aws`, the remote peer side requires the provider entry named `aws.peer`.

```hcl2
module transit_gateway_peering {
  source = "../../modules/transit_gateway_peering"
  providers = {
    aws      = aws.east
    aws.peer = aws.west
  }

  FIXME local_ = module.transit_gateway_east.route_table["traffic_from_west"]
  FIXME peer_  = module.transit_gateway_west.route_table["traffic_from_east"]
}
```
