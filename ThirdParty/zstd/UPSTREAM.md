# Zstandard Decoder

Vendored from the official https://github.com/facebook/zstd release v1.5.7,
commit f8745da6ff1ad1e7bab384bd1f9d742439278e99, under its BSD license.

`zstddeclib.c` is generated, unmodified, by running
`build/single_file_libs/create_single_file_decoder.sh` in that release.
`zstd.h`, `zstd_errors.h`, and `LICENSE` are copied from `lib/zstd.h`,
`lib/zstd_errors.h`, and `LICENSE`.

SHA-256:

```text
5eb38abe0a7eea13674b312a006df72002d4192f0f0b4d09e6f03fb927a1f3d0  zstddeclib.c
9b4bc8245565c98ccfc61c07749928b57e7c0f6fddb0530c4f6aa1971893d88b  zstd.h
66a8c3f71d12ea6e797e4f622f31f3f8f81c41b36f48cad4f5de7d8bfb6aac0a  zstd_errors.h
```

The decoder is statically linked into both Mac architectures. No Homebrew,
external executable, network access, or extracted log files are required.
The BSD notice is also included in the app's Resources/ThirdPartyNotices.txt.
