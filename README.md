# redis_adbc for DuckDB

`redis_adbc` embeds the Redis ADBC driver and Go runtime in one native DuckDB
extension. It provides a streaming table function:

```sql
SELECT * FROM redis_adbc_scan(
    'redis://localhost:6379/0',
    'SELECT id, country FROM public.orders WHERE id > 100'
);
```

The [registry submission](https://github.com/duckdb/community-extensions/pull/3157)
has merged for DuckDB 2.0. `INSTALL redis_adbc FROM community` requires a
successful registry build and publication for your exact engine/platform.
Release CI also attaches versioned, checksummed unsigned binaries for the pinned
DuckDB version; see [release installation](https://github.com/Redislabs-Solution-Architects/redis-adbc-duckdb/releases).
For local development, build from source and load the resulting file with
unsigned extensions enabled in your DuckDB client.

**Recommended Redis configuration:** Redis Search (Query Engine) enabled
and query performance factor (QPF) set to **4×** where supported.
Search is required; 4× QPF is recommended for concurrent query performance
and needs sufficient server CPU capacity. Configure these on the Redis server;
see [server requirements](https://github.com/redis/redis-adbc-driver/blob/main/docs/driver-reference.md#server-requirements).

## DuckDB 2.0 build

This submission targets DuckDB **2.0**, using the community registry's exact
source commit `d54cbbe3df17e8e5ce68312f483b4155836112aa` and its
`v2.0-cyanoptera` extension tools. The registry descriptor's `repo.ref` selects
its published source; repository migration requires a registry descriptor update. See [community submission #3157](https://github.com/duckdb/community-extensions/pull/3157).

Requires CMake, Ninja or Make, a C/C++17 compiler, Python 3, and network access
to fetch the pinned Go 1.27.4 toolchain and Go modules. Linux amd64/arm64 and
macOS amd64/arm64 are build targets; Windows and WebAssembly are excluded.
macOS requires version 15 or newer. No Go installation is required: CMake
downloads a platform-specific archive from go.dev and verifies its SHA-256.

```sh
git clone https://github.com/Redislabs-Solution-Architects/redis-adbc-duckdb.git
cd redis-adbc-duckdb
git submodule update --init --depth 1 driver duckdb extension-ci-tools
git submodule update --init --recursive --depth 1 duckdb extension-ci-tools
OVERRIDE_GIT_DESCRIBE=v2.0.0 GEN=ninja make release
```

Output: `build/release/extension/redis_adbc/redis_adbc.duckdb_extension`.
Use the matching DuckDB 2.0 engine built from the pinned `duckdb` submodule.
The extension needs no ADBC driver manager, separate driver library, driver
manifest, or `adbc_scanner` extension at runtime.

Linux builds use the system allocator. Combining jemalloc's large TLS block
with Go's initial-exec TLS in the same loadable binary exceeds glibc's default
static-TLS budget; `extension_config.cmake` disables jemalloc to allow normal
extension loading without preloading libraries or changing loader settings.

For a quick build against an existing DuckDB checkout:

```sh
cmake -S /path/to/duckdb -B build/duckdb -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DOVERRIDE_GIT_DESCRIBE=v2.0.0 \
  -DDUCKDB_EXTENSION_CONFIGS="$PWD/extension_config.cmake" \
  -DBUILD_UNITTESTS=OFF -DBUILD_SHELL=OFF -DEXTENSION_STATIC_BUILD=OFF
cmake --build build/duckdb --target redis_adbc_loadable_extension
```

This quick build resolves DuckDB symbols from the host process. Distributable
builds should use the standard `make release` path, which embeds DuckDB's
required symbols as configured by its extension build tools.

## Behavior and limits

- Requires Redis Search, including for constant queries. Redis Cloud, Redis
  Software and Redis 8.x with Search are supported by the driver; Redis Flex,
  Valkey and Redis 7.2 derivatives are unsupported.
- The query must be exactly one SELECT. SELECT CTEs and set operations work;
  DDL, DML, transaction commands, and scripts are rejected before connecting.
  The Redis driver's parser and supported SQL determine accepted syntax.
- Schema discovery connects to Redis and describes the query without executing
  it. Execution opens a fresh connection and checks that the result schema
  still matches. A prepared statement can execute repeatedly. There is no
  snapshot spanning schema discovery and execution.
- Arrow batches are streamed, including NULLs and supported decimal/date types.
  Each scan has one consumer thread and owns its connection. LIMIT/close and
  errors release the Arrow stream, statement, connection, and database.
- SQL inside the function runs in the Redis driver and may use Search pushdown.
  DuckDB applies surrounding filters, projections, joins and aggregates locally.
  Put predicates in the remote SQL when remote execution matters.
- This is a read interface, with no ATTACH catalogs, writes, ingestion API,
  bound query parameters, or transaction support. For those integration APIs,
  see the existing [adbc_scanner workflow](https://github.com/redis/redis-adbc-driver/blob/main/docs/duckdb.md).
- `rediss://` uses the driver's TLS verification. Credentials in URI literals
  can appear in DuckDB query history/profiling. Use client parameters and Redis
  ACLs appropriate to the data. `enable_external_access=false` rejects scans.

## Tests

Use disposable Redis Software with active, verified 4x QPF; tests create and drop unique tables.
The test fixture uses a separately built ADBC library only to seed test data.
The extension reads through its embedded driver.

```sh
make -C driver/go redis-up build
python -m pip install pyarrow adbc-driver-manager
REDIS_DUCKDB_CLI="$PWD/build/release/duckdb" \
REDIS_ADBC_EXTENSION="$PWD/build/release/extension/redis_adbc/redis_adbc.duckdb_extension" \
REDIS_ADBC_LIBRARY="$PWD/driver/go/build/libadbc_driver_redis.so" \
bash driver/go/software-setup.sh --exec python "$PWD/duckdb-extension/verify_cli.py"
```

Use `.dylib` for the fixture library on macOS. Offline argument-validation
SQLLogicTests are in `test/sql/redis_adbc.test` and run through `make test`.

The CLI harness checks 13 runtime scenarios, physical column types and every
value in 10,003 rows against the matching 2.0 engine. CI runs it on Linux
amd64/arm64 and builds/tests the extension offline on macOS arm64. It does not
depend on the availability of a matching Python DuckDB wheel. The separate
`test/test_native.py` tests can also be run when a Python DuckDB wheel matching
the extension's engine version is available.

## Driver source and releases

The `driver` submodule pins the exact Redis ADBC source used for both the embedded
archive and runtime fixtures. Update that pin deliberately and run this repo's
CI before releasing. Builds never follow a floating driver branch. The source
was extracted from `redis/redis-adbc-driver` at
`cacae16c637bd5459a43f9e794e8c80f7fafa08f`; existing Apache-2.0 notices are retained.
Initialize driver without recursively checking out its historical submodules.

Publishing a GitHub release in this repository builds Linux amd64/arm64 and
macOS arm64 artifacts and uploads them after all platform jobs succeed. Each
archive includes engine/platform, extension and driver revisions, and an adjacent
SHA-256 checksum. Driver releases in the upstream repository are independent.
The upstream Query.Farm `adbc_scanner` integration remains in the driver repo.
