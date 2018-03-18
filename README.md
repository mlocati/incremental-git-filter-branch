[![TravisCI Build Status](https://travis-ci.org/mlocati/incremental-git-filter-branch.svg?branch=master)](https://travis-ci.org/mlocati/incremental-git-filter-branch)

## Introduction

[`git filter-branch`](https://git-scm.com/docs/git-filter-branch) is a really nice git feature.
For instance, it allows fancy stuff like subtree-splitting.

Problems may arise when the repository contains a lot of commits: this operation can take a lot of time.

Luckily recent versions of git allow us to perform this operation in an incremental way:
the first time `filter-branch` still requires some time, but following calls can be very fast.


## Requirements

- git 2.16.0 or newer
- common commands (`sed`, `grep`, `md5sum`, `cut`, ...)


## Usage

Get the script and read the syntax using the `--help` option.


## Examples

```sh
./bin/incremental-git-filterbranch \
    --branch-whitelist 'develop master rx:release\/.*' \
    --tag-blacklist 'rx:5\..*' \
    --tags-plan all --tags-max-history-lookup 10 \
    https://github.com/concrete5/concrete5.git \
    '--prune-empty --subdirectory-filter concrete' \
    git@github.com:concrete5/concrete5-core.git
```


## Legal stuff

Use at your own risk.
[MIT License](https://github.com/mlocati/incremental-git-filter-branch/blob/master/LICENSE).


## Credits

Special thanks to [Ian Campbell](https://github.com/ijc) for the implementation of the `--state-branch` option of git,
and his hints about how it can be used.
This script works only thanks to him (and if it doesn't work I'm the only person to blame).
