# Distroless flexisip-proxy Docker image

[![CI](https://github.com/m-pilia/flexisip-distroless/actions/workflows/ci.yml/badge.svg)](https://github.com/m-pilia/flexisip-distroless/actions/workflows/ci.yml)

A Docker image to run Flexisip focused on security and minimal footprint.

# Motivation

I created this project because I needed a production-quality image with
hardened security, and I was not satisfied with any of the pre-existing
open-source container images.

# Features

- Distroless runtime, no shell nor package manager, minimal attack surface inside the container.
- Non-root container user.
- Small size: 38.2 MB (14.8 MB gzip).
- Release build binaries with hardened config.
- No hard-coded config.
- Compiler (ccache) and apt caching for fast rebuilds.

# Build

Pin versions via build argument. Note that build and runtime base images can also be set.

```sh
docker buildx build --load \
  --build-arg FLEXISIP_VERSION=2.6.2 \
  --build-arg FLEXISIP_COMMIT=68ba0e8a51227acbb7e88f2d2f90fb2afee5bee4 \
  -t flexisip:2.6.2 .
```

The compiler and apt caches rely on BuildKit's built-in cache. To clear it:
```sh
docker buildx prune --filter type=exec.cachemount
```

# License

MIT
