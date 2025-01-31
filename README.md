# go-bootstrap

[![build](https://github.com/verifiable-builds/go-bootstrap/actions/workflows/build.yml/badge.svg)](https://github.com/verifiable-builds/go-bootstrap/actions/workflows/build.yml)
[![license](https://img.shields.io/github/license/verifiable-builds/go-bootstrap?labelColor=3a3a3a&color=00ADD8&logo=github&logoColor=959da5)](https://github.com/verifiable-builds/go-bootstrap/blob/master/LICENSE)
[![upstream-license](https://img.shields.io/github/license/golang/go?labelColor=3a3a3a&color=00ADD8&logo=github&logoColor=959da5&label=upstream-license)](https://github.com/verifiable-builds/go-bootstrap/blob/master/LICENSE)
[![version](https://img.shields.io/github/v/tag/verifiable-builds/go-bootstrap?label=version&sort=semver&labelColor=3a3a3a&color=CE3262&logo=semver&logoColor=959da5)](https://github.com/verifiable-builds/go-bootstrap/releases)

This repository is used for building go bootstrap toolchain with SLSA provenance.
This repository uses git submodules to point to go source repositories.

Bootstrap toolchain is **only built for linux/amd64**. It does not build for
_any_ other architectures, as go1.21 or later can be easily cross compiled
without any issues in a _fully reproducible_ manner.

This project and its release assets SHOULD ONLY be used for bootstrapping the
go toolchain.

**IT MUST NOT BE USED TO BUILD GO APPLICATIONS, ONLY THE TOOLCHAIN**

For LICENSE details of Go toolchain please consult the LICENSE file(s)
inside the bootstrap archive. Alternatively refer to Go upstream repository.
LICENSE file within this repository only applies to build scripts and build
ci configuration and not necessarily the artifacts included in the release.

Tags in this repository intentionally have a prefix `bootstrap-*` to avoid
being used directly by scripts or any unintended developers.

This repository _does not_ make use of `slsa-framework/slsa-github-generator`
to ensure that this repository _only depends on official GitHub actions_
and no third party actions are involved. While SLSA build provenance is
only L2 (due to signing workflow being within same repo) any issues from
lower isolation are mitigated as go toolchains are bit-for-bit reproducible.
Bootstrap script also _does not_ make use of any tools or actions written in Go.
