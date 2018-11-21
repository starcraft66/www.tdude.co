---
title: "Configuring IPv6 access for docker containers on OVH"
date: 2018-11-21T11:08:42-05:00
---

As of recent years, I have been playing around with [Docker](https://docker.com) quite a bit and use it in production to run quite a few services.
So far, in every docker deployment, I have done, I have only used IPv4, however, now that IPv6 is gaining a lot of traction I thought it would be a good idea to make all of my docker services accessible via IPv6!
For about 8 months now I have been running a [[matrix]](https://matrix.org) chat server using docker. The server has so far attracted about 100 users around the globe and I thought it would be a good idea to make this service more accessible to users stuck behind an IPv4 [Carrier-Grade NAT (CG-NAT)](https://en.wikipedia.org/wiki/Carrier-grade_NAT) or to users using a [translation mechanism](https://en.wikipedia.org/wiki/IPv6_transition_mechanism) such as [NAT64](https://en.wikipedia.org/wiki/NAT64) to access the IPv4 internet over IPv6 networks.

Now, of course, to provide an IPv6-accessible service, we need a server with IPv6 internet access. I am a long time OVH customer and am glad that they offer IPv6 connectivity to most if not all of the servers they sell. Although I am a bit unhappy with the small number of addresses they provide, I've had a mostly positive experience with OVH in general.

After reading lots of docker documentation about IPv6 configuration, I concluded that it took more tinkering that was written in the docs to get IPv6 working properly in docker and docker-compose on OVH due to their small IPv6 allocations so I thought I would document my working procedure here.

Now about the OVH IPv6 allocation: every single one of the dedicated servers I rent at OVH only has a single /64 allocated to them. I find this very disappointing because a /64 is supposed to be the smallest allocation you can give to a subscriber according to [RFC6177](https://tools.ietf.org/html/rfc6177). That is only a single subnet! That same RFC also recommends giving customers a /56 or a /48 instead in order to accommodate for growth and additional subnets on the network. Having to deal with a single /64 is particularly bad if you want to start installing virtual machines on your server, or in this case docker containers because it will require subnetting the network into smaller segments which is not recommended and [breaks things](https://slash64.net/). I find this especially dumb coming from OVH considering that I can find [this post dating back to 2009](http://linux-attitude.fr/post/proxy-ndp-ipv6) saying OVH was allocating /56es to servers back then... and now they reverted to only assigning single /64s? Ridiculous, especially when considering the fact that one of their large competitors, [Online.net](https://online.net) is offering a /48 block with every dedicated server purchase...

Anyway enough ranting. Let's get to the good stuff!

The first step is to enable IPv6 support in the docker daemon and give docker a fixed subnet to allocate addresses from to all containers that are created directly via `docker` commands (not `docker-compose`!). Before we can even do that, we need to break up our server's /64 subnet into smaller chunks and allocate a part of that subnet to docker. I found this representation of IPv6 subnet mask lengths very useful to understand how exactly we are breaking the subnet up.

```
2001:0db8:0123:4567:89ab:cdef:1234:5678
|||| |||| |||| |||| |||| |||| |||| ||||
|||| |||| |||| |||| |||| |||| |||| |||128     Single end-points and loopback
|||| |||| |||| |||| |||| |||| |||| |||127   Point-to-point links (inter-router)
|||| |||| |||| |||| |||| |||| |||| ||124
|||| |||| |||| |||| |||| |||| |||| |120
|||| |||| |||| |||| |||| |||| |||| 116
|||| |||| |||| |||| |||| |||| |||112
|||| |||| |||| |||| |||| |||| ||108
|||| |||| |||| |||| |||| |||| |104
|||| |||| |||| |||| |||| |||| 100
|||| |||| |||| |||| |||| |||96
|||| |||| |||| |||| |||| ||92
|||| |||| |||| |||| |||| |88
|||| |||| |||| |||| |||| 84
|||| |||| |||| |||| |||80
|||| |||| |||| |||| ||76
|||| |||| |||| |||| |72
|||| |||| |||| |||| 68
|||| |||| |||| |||64   Single LAN; default prefix size for SLAAC
|||| |||| |||| ||60   Some (very limited) 6rd deployments (/60 = 16 /64)
|||| |||| |||| |56   Minimal end sites assignment; e.g. home network (/56 = 256 /64)
|||| |||| |||| 52   /52 block = 4096 /64 blocks
|||| |||| |||48   Typical assignment for larger sites (/48 = 65536 /64)
|||| |||| ||44
|||| |||| |40
|||| |||| 36   possible future local Internet registry (LIR) extra-small allocations
|||| |||32   LIR minimum allocations
|||| ||28   LIR medium allocations
|||| |24   LIR large allocations
|||| 20   LIR extra large allocations
|||16
||12   Regional Internet registry (RIR) allocations from IANA[15]
|8
4
```

It is important to note that the minimum subnet mask (or [CIDR](https://en.wikipedia.org/wiki/Classless_Inter-Domain_Routing) to be precise) we can allocate to the docker daemon is a /80 because docker generates addresses for its containers based on the MAC address of the container's network interface. Since MAC addresses are precisely 48 bits in size and IPv6 addresses are 128 bits, that leave a maximum of 80 bits for the IPv6 prefix. I chose to go right with a /80 for docker because the prefix is aligned right with a 32-bit boundary which makes addresses easier to remember and shorten. For example, if my server has `2001:db8:dead:beef::/64` as its allocated block, any prefix in `2001:db8:dead:beef:XXXX::/80` where `XXXX` ranges from `0000` to `ffff` is a valid /80 subnet. For demonstration purposes, I will use `2001:db8:dead:beef:face::/80` as the subnet dedicated to docker.

Now let's get to actually editing the docker config. First, edit `/etc/docker/daemon.json` (create it if it doesn't exist, it does not exist by default) and add the following configuration nodes inside the file. Replace my example subnet with a subnet derived from your server's prefix as I did above.

```json
{
    "ipv6": true,
    "fixed-cidr-v6": "2001:db8:dead:beef:face::/80"
}
```

Then restart the docker engine (with systemd in this case).

```
systemctl restart docker
```

We can confirm that docker has an IPv6 address by running `ip a sh docker0` and verifying that the docker0 interface has the correct addresses. The output should look something like this.

```
$ ip a sh docker0
4: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default 
    link/ether 02:42:9a:b0:fc:d9 brd ff:ff:ff:ff:ff:ff
    inet 172.17.0.1/16 brd 172.17.255.255 scope global docker0
       valid_lft forever preferred_lft forever
    inet6 2001:db8:dead:beef:face::/80 scope global 
       valid_lft forever preferred_lft forever
    inet6 fe80::1/64 scope link 
       valid_lft forever preferred_lft forever
    inet6 fe80::42:9aff:feb0:fcd9/64 scope link 
       valid_lft forever preferred_lft forever
```

The line `inet6 2001:db8:dead:beef:face::/80 scope global` indicates that the configuration has been successful.

From now on, any container you create using a `docker` command will obtain an IPv6 address by default. We can test this by running the following command which will pull a small image and simply run `ip` commands that print out the container's ip addresses and its routing table.

```
docker run --rm -it ajeetraina/ubuntu-iproute bash -c "ip a; ip -6 route"
```

Here's my sample output.

```
$ docker run --rm -it ajeetraina/ubuntu-iproute bash -c "ip a; ip -6 route"
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
66: eth0@if67: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default 
    link/ether 02:42:ac:11:00:03 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 172.17.0.3/16 brd 172.17.255.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 2001:db8:dead:beef:face:242:ac11:3/80 scope global nodad 
       valid_lft forever preferred_lft forever
    inet6 fe80::42:acff:fe11:3/64 scope link tentative 
       valid_lft forever preferred_lft forever
2001:db8:dead:beef:face::/80 dev eth0  proto kernel  metric 256  pref medium
fe80::/64 dev eth0  proto kernel  metric 256  pref medium
default via 2001:db8:dead:beef:face::1 dev eth0  metric 1024  pref medium
```

As we can see, the container's network interface has the MAC address `02:42:ac:11:00:03` and therefore it has been allocated the ip address `2001:db8:dead:beef:face:242:ac11:3`. Additionally, it has a default route via `2001:db8:dead:beef:face::1` which goes through a docker-created bridge. It looks like we're done, right? Our containers have an IPv6 address and we can even ping them! Not so fast... While we can ping docker0 and any created containers from the docker host machine, this only works because our local routing table knows how to route this traffic to docker. If you try pinging `2001:db8:dead:beef:face::1` from the exterior, it won't work at all!

```
$ ping6 2001:db8:dead:beef:face::1
PING 2001:db8:dead:beef:face::1(2001:db8:dead:beef:face::1) 56 data bytes
^C
--- 2001:db8:dead:beef:face::1 ping statistics ---
7 packets transmitted, 0 received, 100% packet loss, time 6125ms
```

Why is this happening and how can we fix it? Well to dig into this problem we need to dig a bit deeper and the answer lies within the IPv6 [Neighbor Discovery Protocol](https://en.wikipedia.org/wiki/Neighbor_Discovery_Protocol) or NDP. NDP is a replacement for what is known as [Address Resolution Protocol](https://en.wikipedia.org/wiki/Address_Resolution_Protocol) or ARP in IPv4. What happens when you ping your docker container's IP address? In short, the packets make it to the OVH router which then sends NDP "Neighbor Solicitation" packages through the switch port connected to your server. If you run a traceroute to your docker container IP, you will notice that it makes its way through a few routers until the last one where it just times out. To see what exactly is going on, (while actively pinging a container's IP) we can use `tcpdump(8)` to sniff for NDP packets on the host's network interface with the following very useful filter.

```
tcpdump -i <NAME OF YOUR HOST NETWORK INTERFACE> 'ip6 && icmp6 && (ip6[40] == 133 || ip6[40] == 134 || ip6[40] == 135 || ip6[40] == 136)'
```

```
# tcpdump -i eno1 'ip6 && icmp6 && (ip6[40] == 133 || ip6[40] == 134 || ip6[40] == 135 || ip6[40] == 136)'
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on eno1, link-type EN10MB (Ethernet), capture size 262144 bytes
12:52:22.096301 IP6 fe80::6e9c:edff:feba:ec40 > ff02::1:ff00:0: ICMP6, neighbor solicitation, who has 2001:db8:dead:beef:face:242:ac11:3, length 32
12:52:23.094659 IP6 fe80::6e9c:edff:feba:ec40 > ff02::1:ff00:0: ICMP6, neighbor solicitation, who has 2001:db8:dead:beef:face:242:ac11:3, length 32
12:52:24.099226 IP6 fe80::6e9c:edff:feba:ec40 > ff02::1:ff00:0: ICMP6, neighbor solicitation, who has 2001:db8:dead:beef:face:242:ac11:3, length 32
12:52:45.442193 IP6 fe80::6e9c:edff:feba:eb40 > ff02::1:ff00:0: ICMP6, neighbor solicitation, who has 2001:db8:dead:beef:face:242:ac11:3, length 32
12:52:46.442006 IP6 fe80::6e9c:edff:feba:eb40 > ff02::1:ff00:0: ICMP6, neighbor solicitation, who has 2001:db8:dead:beef:face:242:ac11:3, length 32
12:52:47.682698 IP6 fe80::6e9c:edff:feba:eb40 > ff02::1:ff00:0: ICMP6, neighbor solicitation, who has 2001:db8:dead:beef:face:242:ac11:3, length 32
12:52:50.475475 IP6 fe80::6e9c:edff:feba:ec40 > ff02::1:ff00:0: ICMP6, neighbor solicitation, who has 2001:db8:dead:beef:face:242:ac11:3, length 32
12:52:51.471019 IP6 fe80::6e9c:edff:feba:ec40 > ff02::1:ff00:0: ICMP6, neighbor solicitation, who has 2001:db8:dead:beef:face:242:ac11:3, length 32
12:52:52.471363 IP6 fe80::6e9c:edff:feba:ec40 > ff02::1:ff00:0: ICMP6, neighbor solicitation, who has 2001:db8:dead:beef:face:242:ac11:3, length 32
12:53:12.057579 IP6 fe80::6e9c:edff:feba:ec40 > ff02::1:ff00:0: ICMP6, neighbor solicitation, who has 2001:db8:dead:beef:face:242:ac11:3, length 32
12:53:13.065634 IP6 fe80::6e9c:edff:feba:ec40 > ff02::1:ff00:0: ICMP6, neighbor solicitation, who has 2001:db8:dead:beef:face:242:ac11:3, length 32
12:53:14.139442 IP6 fe80::6e9c:edff:feba:ec40 > ff02::1:ff00:0: ICMP6, neighbor solicitation, who has 2001:db8:dead:beef:face:242:ac11:3, length 32
12:53:40.748607 IP6 fe80::6e9c:edff:feba:eb40 > ff02::1:ff00:0: ICMP6, neighbor solicitation, who has 2001:db8:dead:beef:face:242:ac11:3, length 32
```

As we can see, the on-link router is sending the packets to our server's network interface because the router knows that the IP we are pinging is inside the /64 subnet allocated to our server. The problem, however, is that we see tons of neighbor solicitations but no neighbor advertisements in response. The reason for this is that the IPv6 addresses we assigned to docker are part of virtual bridge interfaces and not directly allocated to the host's network interface, thus it is not responding to the neighbor solicitations.

The solution? Enter proxy NDP. Proxy NDP does exactly what you think it would guessing by its name. Proxy NDP will listen for solicitations on any interface, in this case, our host's network interface, and then forward those messages to a specific other interface (our docker bridge) which will then respond with its own advertisements. Proxy NDP will then proxy that response back through the original interface and thus through the router and like magic, our containers will now be able to communicate with the outside world!

To set up proxy NDP, we first need to enable IPv6 packet forwarding and proxy ARP on the interfaces we want in the kernel. For most people, enabling these on all interfaces will be sufficient and shouldn't cause any problems but these features can be individually enabled on selected interfaces if desired. We also add an iptables rule for forwarding which may be necessary if you have iptables enabled (make sure to save this with ip6tables-save afterward).

```
# sysctl -w net.ipv6.conf.all.forwarding=1
# sysctl -w net.ipv6.conf.all.proxy_ndp=1
# echo net.ipv6.conf.all.forwarding=1 >> /etc/sysctl.d/70-docker-ipv6.conf
# echo net.ipv6.conf.all.proxy_ndp=1 >> /etc/sysctl.d/70-docker-ipv6.conf
# ip6tables -P FORWARD ACCEPT
```

Now, normally, you would need to manually add rules for every single address to proxy using a command like `ip -6 neigh add proxy $ext_ip dev $int_if`. This is a tedious process and thankfully there are very useful tools like `ndppd(1)` that greatly facilitate and automate this process. Start by installing `ndppd` using the package manager of your choice and then edit or create if it does not exist the file `/etc/ndppd.conf` according to the sample configuration below.

```
proxy <NAME OF YOUR HOST NETWORK INTERFACE> {
    rule 2001:db8:dead:beef:face::/80 {
        iface docker0
    }
}
```

On my server the configuration looks something like this.

```
proxy eno1 {
    rule 2001:db8:dead:beef:face::/80 {
        iface docker0
    }
}
```

Then finally, start the proxy NDP daemon.

```
systemctl start ndppd
```

If you start pinging your container again, it will start responding and if you are still running `tcpdump`, you will see neighbor advertisements in response to the neighbor solicitations the OVH router is sending to your server.

```
13:24:49.966684 IP6 fe80::6e9c:edff:feba:ec40 > ff02::1:ff00:0: ICMP6, neighbor solicitation, who has 2607:5300:60:2dff:ff:ff:ff:ff, length 32
13:24:49.967387 IP6 fe80::7254:d2ff:fe19:c075 > fe80::6e9c:edff:feba:ec40: ICMP6, neighbor advertisement, tgt is 2001:db8:dead:beef:face:242:ac11:3, length 24
```

```
64 bytes from 2001:db8:dead:beef:face:242:ac11:3: icmp_seq=1 ttl=42 time=154 ms
64 bytes from 2001:db8:dead:beef:face:242:ac11:3: icmp_seq=2 ttl=42 time=151 ms
64 bytes from 2001:db8:dead:beef:face:242:ac11:3: icmp_seq=3 ttl=42 time=152 ms
64 bytes from 2001:db8:dead:beef:face:242:ac11:3: icmp_seq=4 ttl=42 time=153 ms
64 bytes from 2001:db8:dead:beef:face:242:ac11:3: icmp_seq=5 ttl=42 time=152 ms
```

Success!

Success for `docker`, that is... There are a bunch of additional gotchas that need to be covered if you use `docker-compose` as I do.

The biggest gotcha right off the bat is that according to the [docker-compose v3 file format documentation](https://docs.docker.com/compose/compose-file/), "If IPv6 addressing is desired, the `enable_ipv6` option must be set, and you must use a version 2.x Compose file". That's right, docker-compose v3 is completely incompatible with IPv6... anyway so we want to start out with a version "2.x" configuration file like this one.

```yaml
version: 2
networks:
  demo:
    enable_ipv6: true
```

Because docker-compose files define their own network for the containers to use, traffic does not flow through the `docker0` bridge we configured above so the `fixed-cidr-v6` we configured in the docker daemon's configuration file will be ignored. Instead of using `docker0`, docker-compose creates a new bridge with a random name by default which the containers using that network are then a part of. This means we need to choose a new /80 subnet for the containers defined in this compose file. For this demonstration I will choose `2001:db8:dead:beef:f00d::/80`, and since the gateway is usually the first network on the subnet I will use `2001:db8:dead:beef:f00d::1/80` as the gateway. Once these parameters are added to the driver's ipam config, our compose file will look like this.

```yaml
version: 2
networks:
  demo:
    enable_ipv6: true
    ipam:
      driver: default
      config:
        - subnet: "2001:db8:dead:beef:f00d::/80"
          gateway: "2001:db8:dead:beef:f00d::1"
```

We can see immediately that a randomly-generated bridge name will be problematic: we won't be able to predict its name when we add it to `ndppd.conf`. To work around this, it is possible to set the `com.docker.network.bridge.name` option on the bridge network driver to give it a name which for this demonstration will be called `br-demo`. Our compose file then looks like this.

```yaml
version: 2
networks:
  demo:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: br-demo
    enable_ipv6: true
    ipam:
      driver: default
      config:
        - subnet: "2001:db8:dead:beef:f00d::/80"
          gateway: "2001:db8:dead:beef:f00d::1"
```

It's quite possible you'll probably also want IPv4 networking for your containers so I went and added a random free subnet in `172.16.0.0/12`.

```yaml
version: 2
networks:
  demo:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: br-demo
    enable_ipv6: true
    ipam:
      driver: default
      config:
        - subnet: 172.24.0.0/16
          gateway: 172.24.0.1
        - subnet: "2001:db8:dead:beef:f00d::/80"
          gateway: "2001:db8:dead:beef:f00d::1"
```

 I mentioned `ndppd.conf` because, just like we did with `bridge0`, we need to add an entry for `br-demo` in `/etc/ndppd.conf` under the same host network interface as we put docker0. This is what my config now looks like.

 ```
proxy eno1 {
    rule 2001:db8:dead:beef:face::/80 {
        iface docker0
    }
    rule 2001:db8:dead:beef:f00d::/80 {
        iface br-test
    }
}
```

Almost done! The last step is to add some container(s) to your docker-compose file and assign them static IPv6 (and IPv4 if desired) addresses, here's my final IPv6-capable docker-compose file with an nginx instance! 

```yaml
version: 2
services:
  nginx:
    container_name: demo_nginx
    image: nginx:alpine
    networks:
      matrix:
        ipv6_address: "2001:db8:dead:beef:f00d::2"
    restart: always
networks:
  demo:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: br-demo
    enable_ipv6: true
    ipam:
      driver: default
      config:
        - subnet: "2001:db8:dead:beef:f00d::/80"
          gateway: "2001:db8:dead:beef:f00d::1"
```

And there you have it! A world-reachable ipv6-only nginx web server with its own IPv6 address! **Note**: Unlike the usual docker workflow of exposing ports via the `-p` section or `ports:` configuration in docker-compose, all ports are in your container are exposed to the internet by default so it is a good idea to firewall your containers like you would on a regular host using `iptables`. The significant advantage of this is that there is no NATing involved and therefore each and every one of your containers can have its own or even multiple public addresses. If you host many sites inside a single nginx container, you could assign a different IP address to every site all in the same container for example and since there is no NAT involved, your containers are not stealing an IP addresses or ports from your docker host network.