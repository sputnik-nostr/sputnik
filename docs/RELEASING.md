# Releasing

How the release files are built, how to check one, and what the repository settings must be for the signing key to stay safe.

## Building

`make dist` builds the AppImage and the unsigned APKs in the pinned container (`contrib/Dockerfile`), and puts them in `dist/` with their checksums. The image, the build script and the sources all come from the commit that is checked out, so uncommitted changes are not built; `make` warns if there are any. The release workflow (`.github/workflows/build.yml`) runs the same `make dist`, and then signs the APKs. `make check` runs the formatting, analysis and tests in the same container, and checks that the AppImage's libraries resolve (see below).

## Checking a release

- `SHA256SUMS` lists what is installed: the AppImage and the signed APKs. `sha256sum -c --ignore-missing SHA256SUMS` checks the files you downloaded.
- `SHA256SUMS.unsigned` lists the unsigned APKs. They are the build before signing, and cannot be installed. A `make dist` of the same commit gives the same hashes, for these and for the AppImage. It has to be `make dist`: outside the container, the path of the NDK ends up in the build ID of the native libraries.
- A signed APK differs from your unsigned one: signing aligns the files again and adds a signing block. `contrib/verify_apk.sh signed.apk unsigned.apk` signs your unsigned APK with a throwaway key as the release does, cuts the signing block out of both, and checks that what is left is identical to the last byte. It also prints the certificate of the signed APK, to compare with the fingerprint that the project publishes. It needs `apksigner` and `keytool`; use the ones of the build image, as the release does, so that both APKs are signed by the same program. With both APKs in `dist/`:

  ```sh
  docker run --rm -v "$PWD:/w:ro" sputnik-build /w/contrib/verify_apk.sh \
      /w/dist/sputnik-arm64-v8a.apk /w/dist/sputnik-arm64-v8a-unsigned.apk
  ```

- The build provenance, attested for every `sputnik-*.apk` (the unsigned ones too, which are named so) and the AppImage, is checked with `gh attestation verify <file> -R sputnik-nostr/sputnik`.

## The release environment

The job in `build.yml` names the `release` environment, which holds the signing secrets. This protects them only if the following is true. Listing the secrets and changing any of it needs admin rights on the repository, so it is for an admin to check now and then:

- The `ANDROID_*` secrets exist **only** in the `release` environment. A secret at repository or organization level is available to every workflow run, those of other branches and of pull requests from the repository included, and the job takes it in place of a missing environment secret without a sign of it. The environment needs `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD` and `ANDROID_KEY_PASSWORD`; the alias is in `build.yml`, so an `ANDROID_KEY_ALIAS` is not needed anywhere.

  ```sh
  gh secret list -R sputnik-nostr/sputnik                 # nothing named ANDROID_*
  gh secret list --org sputnik-nostr                      # nothing named ANDROID_*
  gh secret list -R sputnik-nostr/sputnik --env release   # the three above
  ```

- The environment lets only `master` deploy (deployment branches: selected branches, `master`), so that only runs on `master` get the secrets.
- The environment has a required reviewer (the other maintainer), "Prevent self-review" is on, and "Allow administrators to bypass configured protection rules" is off. Without a reviewer the bypass setting has no effect, and with one it lets an admin skip the review.
- `master` does not let admins push without the required check or review: anything on `master` can change `build.yml`, and runs in the environment.

Without admin rights, the settings of the environment can still be read:

```sh
gh api repos/sputnik-nostr/sputnik/environments/release \
    --jq '{can_admins_bypass, protection_rules, deployment_branch_policy}'
gh api repos/sputnik-nostr/sputnik/environments/release/deployment-branch-policies \
    --jq '.branch_policies[].name'
```

These settings protect against writers who are not admins and against tokens of narrow scope. They do not protect against a leaked admin token, which can change them.

## Bundled libraries

The AppImage carries well over a hundred libraries from the build container, nearly all of them what libmpv needs, among them FFmpeg, GnuTLS, OpenSSL, libxml2 and libarchive. They are loaded every time the application starts, whether a video is played or not. They are the versions in the Ubuntu snapshot named in the Dockerfile (`UBUNTU_SNAPSHOT`), and a user's machine does not update them: the AppImage is as current as that snapshot.

So the snapshot has to move: update it and rebuild at every release, at least once a month in between, and whenever a security notice covers one of the bundled libraries. Which libraries are bundled follows from `contrib/appimage_hostlibs.sh`: everything the application needs is bundled, except the AppImage project's list of libraries to assume on every system, the GTK stack and the graphics, windowing and audio libraries of the machine. `contrib/check_appimage_libs.sh` prints what is left to the machine, and fails if the AppImage needs anything else.

## Updating a pin

- **BuildKit image** (`driver-opts` in both workflows, which must stay the same; Dependabot does not update it). The digest of a tag:

  ```sh
  token=$(curl -s 'https://auth.docker.io/token?service=registry.docker.io&scope=repository:moby/buildkit:pull' | jq -r .token)
  curl -sI -H "Authorization: Bearer $token" -H 'Accept: application/vnd.oci.image.index.v1+json' \
      https://registry-1.docker.io/v2/moby/buildkit/manifests/v0.33.1 | grep -i docker-content-digest
  ```

- **Android SDK package** (`contrib/Dockerfile`). Take the zip's name from the `<url>` of the package in <https://dl.google.com/android/repository/repository2-3.xml>, download it from the same directory, compare its SHA-1 with the one in that file, and put its SHA-256 in the Dockerfile. Gradle may not download anything else, so a package that the build starts to need makes it fail (with "Failed to find target with hash string", for a platform), and is added the same way.
- **Libraries to leave to the machine** (`contrib/appimage_excludelist`). Replace the file with a newer copy of the AppImage project's list, and change the commit and hash in `contrib/appimage_hostlibs.sh`.
