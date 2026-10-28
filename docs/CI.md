# Optional GitHub Actions

`ci-workflow.yml` is a ready-to-enable macOS 26 build/test workflow. It checks out the pinned submodules, builds the app, runs the native regression suite, and verifies its code signature.

To enable it, copy the file to `.github/workflows/ci.yml` and commit it using a GitHub account/token permitted to write workflows. The initial publishing token lacked the `workflow` scope, so this optional configuration is stored as a template rather than requiring broader account permissions for app publication.
