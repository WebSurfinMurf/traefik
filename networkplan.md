# Docker Network Plan

## Problem Statement

Docker's default address pool is exhausted with 32+ networks. Need to:
1. Expand available address space
2. Right-size networks based on actual usage
3. Establish standards for future network creation

---

## Current Network Inventory (2025-12-02)

| Network | Driver | Current Subnet | Containers | Proposed Size |
|---------|--------|----------------|------------|---------------|
| traefik-net | bridge | 172.25.0.0/16 | 50 | XLarge |
| keycloak-net | bridge | 172.19.0.0/16 | 22 | Large |
| mcp-net | bridge | 192.168.112.0/20 | 18 | Medium |
| postgres-net | bridge | 172.27.0.0/16 | 17 | Medium |
| redis-net | bridge | 172.30.0.0/16 | 8 | Small |
| loki-net | bridge | 192.168.208.0/20 | 6 | Small |
| monitoring-net | bridge | 172.21.0.0/16 | 5 | Small |
| qdrant-net | bridge | 172.26.0.0/16 | 4 | Small |
| mongodb-net | bridge | 172.29.0.0/16 | 3 | Small |
| minio-net | bridge | 192.168.128.0/20 | 3 | Small |
| litellm-net | bridge | 192.168.224.0/20 | 3 | Small |
| arangodb-net | bridge | 192.168.48.0/20 | 3 | Small |
| stirling-pdf_stirling-pdf-net | bridge | 192.168.80.0/20 | 2 | Micro |
| obsidian_obsidian-net | bridge | 192.168.192.0/20 | 2 | Micro |
| netdata-net | bridge | 192.168.176.0/20 | 2 | Micro |
| n8n-net | bridge | 192.168.144.0/20 | 2 | Micro |
| microbin_microbin-net | bridge | 192.168.160.0/20 | 2 | Micro |
| mcp-ib-live-net | bridge | 172.20.0.0/16 | 2 | Micro |
| mcp-ib-paper-net | bridge | 172.40.0.0/16 | 0 | Micro |
| guacamole-net | bridge | 192.168.16.0/20 | 2 | Micro |
| grafana-net | bridge | 172.23.0.0/16 | 2 | Micro |
| dozzle-net | bridge | 172.18.0.0/16 | 2 | Micro |
| dashy-net | bridge | 192.168.240.0/20 | 2 | Micro |
| alist_alist-net | bridge | 192.168.64.0/20 | 2 | Micro |
| alist-net | bridge | 172.31.0.0/16 | 1 | Micro |
| timescaledb-net | bridge | 172.22.0.0/16 | 1 | Micro |
| playwright_default | bridge | 192.168.96.0/20 | 1 | Micro |
| mailserver-net | bridge | 172.28.0.0/16 | 1 | Micro |
| gitlab-net | bridge | 192.168.32.0/20 | 1 | Micro |
| filesystem_default | bridge | 172.24.0.0/16 | 1 | Micro |

**Summary:**
- XLarge: 1 network (traefik-net)
- Large: 1 network (keycloak-net)
- Medium: 2 networks (mcp-net, postgres-net)
- Small: 8 networks
- Micro: 18+ networks

---

## Proposed Subnet Sizing

| Size | CIDR | Total IPs | Usable Hosts | Use Case |
|------|------|-----------|--------------|----------|
| **Micro** | /29 | 8 | 5 | Isolated services, 1-4 containers |
| **Small** | /28 | 16 | 13 | Small apps, 5-10 containers |
| **Medium** | /27 | 32 | 29 | Multi-service apps, 11-25 containers |
| **Large** | /26 | 64 | 61 | Major infrastructure, 26-50 containers |
| **XLarge** | /25 | 128 | 125 | Core networks (traefik), 50-100 containers |

---

## Address Pool Allocation Plan

Using 10.0.0.0/8 private range for maximum flexibility:

| Pool | Base | Size | Networks Available | Purpose |
|------|------|------|-------------------|---------|
| XLarge | 10.0.0.0/16 | /25 | 512 | traefik, future core |
| Large | 10.1.0.0/16 | /26 | 1,024 | keycloak, major infra |
| Medium | 10.2.0.0/16 | /27 | 2,048 | postgres, mcp, redis |
| Small | 10.3.0.0/16 | /28 | 4,096 | Standard services |
| Micro | 10.4.0.0/16 | /29 | 8,192 | Isolated single-service |

**Total capacity: 15,872 networks**

---

## Implementation Plan

### Phase 1: Update Docker Daemon Configuration

Create/update `/etc/docker/daemon.json`:

```json
{
  "default-address-pools": [
    {"base": "10.4.0.0/16", "size": 29}
  ]
}
```

Note: Docker auto-assigns from default pool. For specific sizes, use explicit IPAM in docker-compose.

### Phase 2: Network Size Standards

Add to docker-compose files for explicit sizing:

**Micro (/29):**
```yaml
networks:
  myapp-net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.4.X.0/29
```

**Small (/28):**
```yaml
networks:
  myapp-net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.3.X.0/28
```

**Medium (/27):**
```yaml
networks:
  myapp-net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.2.X.0/27
```

**Large (/26):**
```yaml
networks:
  myapp-net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.1.X.0/26
```

**XLarge (/25):**
```yaml
networks:
  myapp-net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.0.X.0/25
```

### Phase 3: Migration Strategy

**Option A: Gradual (Recommended)**
- New networks use new addressing
- Existing networks continue working
- Migrate during next service restart

**Option B: Full Migration**
- Stop all containers
- Prune all networks
- Restart Docker
- Recreate all networks with new subnets
- Start all containers

---

## Naming Convention Update

Add to naming-validator skill:

| Network Type | Naming Pattern | Subnet Pool |
|--------------|----------------|-------------|
| Core infrastructure | `{service}-net` | 10.0.X.0/25 (XLarge) |
| Major shared | `{service}-net` | 10.1.X.0/26 (Large) |
| Multi-container app | `{service}-net` | 10.2.X.0/27 (Medium) |
| Standard service | `{service}-net` | 10.3.X.0/28 (Small) |
| Isolated service | `{service}-net` | 10.4.X.0/29 (Micro) |

---

## Quick Reference

```
Sizing Guide:
  1-4 containers   → Micro  (/29, 5 hosts)
  5-10 containers  → Small  (/28, 13 hosts)
  11-25 containers → Medium (/27, 29 hosts)
  26-50 containers → Large  (/26, 61 hosts)
  50+ containers   → XLarge (/25, 125 hosts)

Pool Ranges:
  10.0.X.X = XLarge networks
  10.1.X.X = Large networks
  10.2.X.X = Medium networks
  10.3.X.X = Small networks
  10.4.X.X = Micro networks (default)
```

---

## Implementation Status

- [x] Create /etc/docker/daemon.json ✅ (2025-12-02)
- [x] Restart Docker daemon ✅ (2025-12-02)
- [x] Verify new networks use 10.4.0.0/16 pool ✅ (Tested: 10.4.0.8/29)
- [ ] Update naming-validator skill with network sizing
- [ ] Document in AINotes/network.md
- [ ] Migrate existing networks to new scheme (gradual)

---

*Created: 2025-12-02*
*Author: administrator*
