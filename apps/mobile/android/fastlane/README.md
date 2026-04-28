fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Android

### android internal

```sh
[bundle exec] fastlane android internal
```

Upload the latest release AAB to the Internal Testing track as draft (Play requires draft status until the app has a published production release)

### android alpha

```sh
[bundle exec] fastlane android alpha
```

Promote the latest internal release to Closed / Alpha testing

### android production

```sh
[bundle exec] fastlane android production
```

Promote the latest alpha release to Production

### android validate

```sh
[bundle exec] fastlane android validate
```

Verify the Play service-account JSON has the right scopes

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
