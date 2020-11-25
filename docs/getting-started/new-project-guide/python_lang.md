---
layout: default
title: Integrating a Python project
parent: Setting up a new project
grand_parent: Getting started
nav_order: 3
permalink: /getting-started/new-project-guide/python-lang/
---

# Integrating a Rust project
{: .no_toc}

- TOC
{:toc}
---


The process of integrating a project written in Python with OSS-Fuzz is very
similar to the general
[Setting up a new project]({{ site.baseurl }}/getting-started/new-project-guide/)
process. The key specifics of integrating a Python project are outlined below.

## Atheris

Python fuzzing in OSS-Fuzz depends on
[Atheris](https://github.com/google/atheris). Fuzzers will depend on the
`atheris` package, and dependencies are pre-installed on the OSS-Fuzz base
docker images.

## Project files

### Example project

We recommending viewing [ujson](https://github.com/google/oss-fuzz/tree/master/projects/ujson) as an
example of a simple Python fuzzing project.

### project.yaml

The `language` attribute must be specified.

```yaml
language: python
```

The only supported fuzzing engine and sanitizer are `libfuzzer` and `address`,
respectively.

```yaml
sanitizers:
  - address
fuzzing_engines:
  - libfuzzer
```

### Dockerfile

Because most dependencies are already pre-installed on the images, no
significant changes are needed in the Dockerfile for Python fuzzing projects.
You should simply clone the project, set a `WORKDIR`, and copy any necessary
files, or install any project-specific dependencies here as you normally would.

### build.sh

For Python projects, `build.sh` does need some more significant modifications
over normal projects. The following is an annotated example build script,
explaining why each step is necessary and when they can be omitted.

```sh
# Build and install project (using current CFLAGS, CXXFLAGS). This is required
# for projects with C extensions so that they're built with the proper flags.
pip3 install .

# Build fuzzers into $OUT. These could be detected in other ways.
for fuzzer in $(find $SRC -name '*_fuzzer.py'); do
  fuzzer_basename=$(basename -s .py $fuzzer)
  fuzzer_package=${fuzzer_basename}.pkg

  # To avoid issues with Python version conflicts, or changes in environment
  # over time on the OSS-Fuzz bots, we use pyinstaller to create a standalone
  # package. Though not necessarily required for reproducing issues, this is
  # required to keep fuzzers working properly in OSS-Fuzz.
  pyinstaller --distpath $OUT --onefile --name $fuzzer_package $fuzzer

  # Create execution wrapper. Atheris requires that certain libraries are
  # preloaded, so this is also done here to ensure compatibility and simplify
  # test case reproduction. Since this helper script is what OSS-Fuzz will
  # actually execute, it is also always required.
  echo "#/bin/sh
# LLVMFuzzerTestOneInput for fuzzer detection.
LD_PRELOAD=\$(dirname "\$0")/libclang_rt.asan-x86_64.so \$(dirname "\$0")/$fuzzer_package \$@" > $OUT/$fuzzer_basename
  chmod u+x $OUT/$fuzzer_basename
done
```
