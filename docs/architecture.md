# Architecture

```mermaid
flowchart LR
  cli[ttuneCLI] --> detect[DetectorModule]
  cli --> bench[BenchmarkModule]
  cli --> optimize[OptimizerModule]
  cli --> gen[IntegrationModule]
  cli --> verify[VerifyModule]
  cli --> fleet[FleetModule]

  detect --> probes[SystemProbes]
  bench --> ffmpeg[ffmpeg_ffprobe]
  bench --> cache[BenchmarkCache]
  optimize --> cache
  optimize --> rust[ttuneBenchOptional]
  optimize --> learn[LearningCache]
  gen --> tdarr[TdarrOutputs]
  gen --> orch[OrchestrationExports]
  verify --> vmaf[VmafOrProxyChecks]
  fleet --> ssh[SshNodeDiscovery]
```

## Modules

- `lib/detect.sh`: CPU/GPU/encoder probing + fingerprints
- `lib/benchmark.sh`: sample clip benchmark + cache
- `lib/optimize.sh`: recommendations, VMAF search fallback path, content profile, learning cache
- `lib/generate.sh`: Tdarr outputs, flow/plugin templates, k8s/docker/unmanic/CI artifacts
- `lib/verify.sh`: quality gate output (`--ci`)
- `lib/fleet.sh`: node profile aggregation and label output
