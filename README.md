# go-bootstrap

[![build](https://github.com/verifiable-builds/go-bootstrap/actions/workflows/build.yml/badge.svg)](https://github.com/verifiable-builds/go-bootstrap/actions/workflows/build.yml)
[![version](https://img.shields.io/github/v/tag/verifiable-builds/go-bootstrap?label=version&sort=semver&labelColor=3a3a3a&color=CE3262&logo=semver&logoColor=959da5)](https://github.com/verifiable-builds/go-bootstrap/releases)
[![license](https://img.shields.io/github/license/verifiable-builds/go-bootstrap?labelColor=3a3a3a&color=00ADD8&logo=github&logoColor=959da5)](https://github.com/verifiable-builds/go-bootstrap/blob/master/LICENSE)


This repository is used for building go bootstrap toolchain with SLSA provenance.

Bootstrap toolchain is **only built for linux/amd64**. It is not built for
any other architectures, as go1.21 or later can be easily cross compiled
without any issues in a fully reproducible manner.

This project and its release assets/artifacts SHOULD ONLY be used for bootstrapping
the go toolchain.

**IT MUST NOT BE USED TO BUILD GO APPLICATIONS, ONLY THE TOOLCHAIN**

For LICENSE details of Go toolchain please consult the LICENSE file(s)
inside the bootstrap archive. Alternatively refer to Go upstream repository.
LICENSE file within this repository only applies to build scripts and build
ci configuration and not necessarily the artifacts included in the release.
