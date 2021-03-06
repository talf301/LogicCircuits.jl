[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://juice-jl.github.io/LogicCircuits.jl/dev)

# LogicCircuits.jl for Developers

Follow these instructions to install and use LogicCircuits.jl as a developer of the package.

## Installation

Install the Julia package in development mode by running

    julia -e 'using Pkg; Pkg.develop(PackageSpec(url="https://github.com/Juice-jl/LogicCircuits.jl.git"))'

By default this will install the package at `~/.julia/dev` and allow you to change the code there. See the [Pkg manual](https://julialang.github.io/Pkg.jl/v1/managing-packages/#Developing-packages-1) for more details. One can adjust the development directory using environment variables or simply create a symbolic link to/from your favorite development directory.

## Testing


### Prerequisite
Set the following environment variable, to automatically download data artifacts needed during tests without user input. Otherwise the tests would fail if the artifact is not already downloaded.

    export DATADEPS_ALWAYS_ACCEPT=1

Additionally, if you want the tests to run faster, you can use more cores by setting the following variable. The default value is 1.

    export JIVE_PROCS=8

### Running the tests:
Make sure to run the tests before commiting new code.

To run all the tests:

    julia --project=test --color=yes test/runtests.jl

You can also run any specific test:

    julia --project=test --color=yes test/_manual_/aqua_test.jl
    
## Releasing New Versions

Only do this for when the repo is in stable position, and we have decent amount of changes from previous version.

1. Bump up the version in `Project.toml`
2. Use [Julia Registrator](https://github.com/JuliaRegistries/Registrator.jl) to submit a pull request to julia's public registry. 
    - The web interface seems to be the easiest. Follow the instructions in the generated pull request and make sure there is no errors. For example [this pull request](https://github.com/JuliaRegistries/General/pull/15349).
3. Github Release. TagBot is enabled for this repo, so after the registrator merges the pull request, TagBot automatically does a github release in sync with the registrar's new version. 
   - Note: TagBot would automatically include all the closed PRs and issues since the previous version in the release note, if you want to exclude some of them, refer to [Julia TagBot docs](https://github.com/JuliaRegistries/TagBot).
4. As much as possible, make sure to also release a new version for `ProbabilisticCircuits.jl`.


## Troubleshooting

When running tests locally sometimes DataDeps prompts the user for downloading new data and could cause the tests to fail, add the environment variable to avoid the user prompt

```
    export DATADEPS_ALWAYS_ACCEPT=1
```