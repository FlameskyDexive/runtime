# OpenHarmony NativeAOT Build Inputs

The runtime is built against the API15 SDK compatibility baseline. API18, API20,
API23, and API26 SDKs are accepted by `build-runtime.ps1` for compile and
verification coverage, while the staged OpenSSL and ICU libraries remain API15
artifacts.

`prepare-dependencies.ps1` downloads and hashes the pinned OpenSSL and ICU
sources. OpenSSL is built by the script. ICU must be supplied as an externally
cross-built directory because ICU's upstream build requires a host build and a
target data build; this keeps the repository free of generated ICU build trees.
Pass that directory with `-IcuBuildRoot`. It must contain `lib/` with
`libicuuc.so.78`, `libicui18n.so.78`, and `libicudata.so.78`, plus an
`openharmony-icu-provenance.json` file with this schema:

```json
{
  "name": "icu",
  "version": "78.3",
  "source": "https://github.com/unicode-org/icu/releases/download/release-78.3/icu4c-78.3-sources.zip",
  "sha256": "20B295E2C23C541AEC17F35C546E4D3136B7AB7D58E3A5FC4E479958A69B1A2C",
  "license": "Unicode-3.0",
  "sdkApiLevel": 15,
  "sdkPackageVersion": "5.0.3.135",
  "architecture": "arm64",
  "targetTriple": "aarch64-linux-ohos"
}
```

For x86_64, use `architecture: "x64"` and
`targetTriple: "x86_64-linux-ohos"`. The metadata is compared before any
library is copied, so a build produced for another SDK, architecture, or ICU
source cannot be reused silently.

On Windows, OpenSSL configuration requires an MSYS/Cygwin Perl, GNU Make, and
`sh.exe`. The script discovers the shell, copies the tracked Perl compatibility
modules, and generates a wrapper under `artifacts/`; no machine-specific path
is part of the source tree.
