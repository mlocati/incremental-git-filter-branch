## Introduction

[`git filter-branch`](https://git-scm.com/docs/git-filter-branch) is a really nice git feature.
For instance, it allows fancy stuff like subtree-splitting.

Problems may arise when the repository contains a lot of commits: this operation can take a lot of time.

Luckily recent versions of git allow us to perform this operation in an incremental way:
the first time `filter-branch` still requires some time, but following calls can be very fast.


## Requirements

- recent bash shell
- git 2.5.0 or newer.

## Usage

Get the script, and customize the variables you can find at its beginning.


## Legal stuff

Use at your own risk.
[MIT License](https://github.com/mlocati/incremental-git-filter-branch/blob/master/LICENSE).


## Credits

Special thanks to [Ian Campbell](https://github.com/ijc) for the implementation of the `--state-branch` option of git,
and his hints about how it can be used.
This script works only thanks to him (and if it doesn't work I'm the only person to blame).
