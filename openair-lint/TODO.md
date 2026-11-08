# openair-lint: open tasks

These tasks must be done before the first public release.

## pub.dev

- [ ] Reserve the package name `openair_lint` on pub.dev. Publish it from
      Naviter's verified publisher account, so that nobody else takes the name.
- [ ] Set up automated publishing from GitHub Actions on pub.dev
      (package admin page, "Automated publishing", repository
      `naviter/seeyou_file_formats`, tag pattern `openair-lint-v{{version}}`).

## Release setup

- [ ] Windows code signing: add these repository secrets:
      `WINDOWS_CERTIFICATE_BASE64` (the .pfx file, base64) and
      `WINDOWS_CERTIFICATE_PASSWORD`. See
      `.github/workflows/openair-lint-release.yml`.
- [ ] macOS code signing and notarization: add these repository secrets:
      `MACOS_CERTIFICATE_BASE64` (the Developer ID Application .p12 file,
      base64), `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGNING_IDENTITY`,
      `MACOS_NOTARY_APPLE_ID`, `MACOS_NOTARY_PASSWORD` (an app-specific
      password) and `MACOS_NOTARY_TEAM_ID`.
- [ ] GitHub Pages: in the repository settings, set the Pages source to
      "GitHub Actions". In the `github-pages` environment, allow deployments
      from tags that match `openair-lint-v*`.
- [ ] Make a test release with a pre-release tag (for example
      `openair-lint-v3.0.0-dev.1`) and check the assets, the checksums, the
      web page and the GitHub Action.
- [ ] Check that the linter release is not marked as "latest", so the PDF
      links in the repository README still work.
