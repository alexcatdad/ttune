# ttune

Transcode Tuner CLI (`ttune`) is a hardware-aware transcoding profiler and recommendation tool.

## Commands

- `ttune detect [--json] [--diff]`
- `ttune benchmark [--json] [--duration N] [--encoders list] [--no-cache]`
- `ttune optimize -i <file> [--codec hevc|av1|h264] [--target-vmaf N]`
- `ttune generate tdarr|k8s-labels|docker-labels|unmanic-plugin|ci-gate-script`
- `ttune verify --source <src> --transcoded <out> [--target-vmaf 95] [--ci]`
- `ttune fleet-config --hosts host1,host2 [--ssh-user user] [--json]`

## Dependencies

Required:

- bash 4+
- ffmpeg / ffprobe
- jq

Optional:

- `ttune-bench` (Rust companion) or `ab-av1`
- `nvidia-smi`, `vainfo`, `fio`, `mediainfo`

## Quick Start

```bash
chmod +x ./ttune
./ttune detect --json | jq .
./ttune benchmark --json > benchmark.json
./ttune optimize -i /path/to/movie.mkv --codec hevc --output-format ffmpeg-cmd
./ttune generate tdarr --node-name gpu-node-01
```

## Config

Default config lives at `config/default.toml`.
User config path is `~/.config/ttune/config.toml`.

## Roadmap

See:

- `docs/architecture.md`
- `docs/roadmap.md`
