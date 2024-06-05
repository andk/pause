# GitHub Actions Workflows

This directory contains workflow definitions for GitHub actions.

## Local Testing

The easiest way to end to end test them is wih a tool such as
https://github.com/nektos/act (https://nektosact.com/).

```
$ act --artifact-server-path=/tmp/artifacts
... actions run here! ...
```

You can use the `--reuse` flag to reuse information between runs,
which can speed things up.  `--action-offline-mode` and `--pull=false`
can be used to test local copies of container images instead.

IMPORTANT: You need a version of act from 2024-05-20 or later.
(e.g. newer than v0.2.62) to support `actions/upload-artifact@v4`.
