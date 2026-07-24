---
name: high-system-usage
description: Investigate high CPU (and related resource) usage on the local machine, including tracing it into Docker containers. Use when the user says the machine/fans are running hot, something is "eating CPU", the system is slow, or asks what's using CPU/Docker CPU. macOS-focused.
---

# High System Usage

Diagnose what is burning CPU on the local machine and, when the culprit is Docker, drill into the specific container and root cause.

> Scope: this skill currently covers the host-CPU → Docker → container-investigation path. Other resources (memory, disk I/O, network, non-Docker culprits, Linux specifics) are only lightly touched and will be added as more cases come up. Don't assume a path exists here — fall back to general reasoning when it doesn't.

## 1. Find the host culprit first

Don't assume Docker. Identify the top process:

```bash
ps -Ao pcpu,pmem,comm -r | head -20
```

Read the top line. If it's an ordinary app, you're done — report it. Key macOS tell for Docker: the top consumer is `com.apple.Virtualization.VirtualMachine` (Docker Desktop runs all containers inside this Apple VM), so its CPU is the *sum* of container load. That means go to step 2.

## 2. Attribute load to a container

```bash
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
```

- One hot container → investigate it (step 3).
- A whole *stack* hot at once (e.g. a DB plus every service around it) → usually one root cause cascading. Suspect the busiest dependency (often the database or a logging/analytics pipeline) rather than each service.

## 3. Root-cause the container

Check state and history before logs:

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}"   # note (unhealthy), long uptime
docker inspect --format '{{.Name}} restarts={{.RestartCount}}' $(docker ps -q)   # crash/restart loops
docker logs --tail 30 <container>   # tight error loops, floods, retry storms
```

For a hot database, list active work instead of guessing:

```bash
docker exec <db> psql -U postgres -c "SELECT pid, state, wait_event_type, now()-query_start AS runtime, substring(query,1,90) FROM pg_stat_activity WHERE state <> 'idle' AND pid <> pg_backend_pid() ORDER BY runtime DESC NULLS LAST LIMIT 25;"
```

Common findings: an error/retry loop flooding logs (which spins the log/analytics pipeline), an unhealthy service being polled hard, a degraded state after many days of uptime, or a runaway query.

## 4. Act (get the user's call before changing state)

Stopping/removing containers is state-changing and is the user's decision — confirm first. Prefer the least-destructive fix that resolves it:

- Restart only the degraded container(s) to clear a bad state, keeping the stack up.
- `docker stop <names>` — preserves containers so they can be restarted later. Use when the stack isn't needed now.
- `docker rm -f <names>` — only when the user explicitly wants them removed.

After acting, re-run steps 1-2 to confirm CPU actually dropped, and report the before/after.
