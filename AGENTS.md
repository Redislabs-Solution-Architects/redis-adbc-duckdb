# Project instructions

The native DuckDB extension embeds the driver pinned by `driver/`. Read README.md
before building. Keep exact DuckDB ABI and Go toolchain pins. Test live Redis
only on disposable Redis Software with active, verified 4x QPF via
`make -C driver/go redis-up`; use the setup runner to verify policy before tests.
Do not support or test Valkey, ElastiCache or Memorystore. Keep credentials,
fixture artifacts, infrastructure identifiers and Redis license files private.
Preserve Arrow ownership, cleanup, streaming and SELECT-only behavior.
