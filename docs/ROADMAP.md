# Feature roadmap

- [x] Add more good default relay options
- [x] Allow clicking on URLs
- [x] Show followers/following lists on profiles
- [x] Show actual reaction data for posts
- [x] Allow searching for `nprofile` keys (rather than just `npub`)
- [x] Allow searching for post IDs
- [x] Show full profile pictures/banners when clicked
- [ ] Allow copying text
- [ ] Separate posts and replies on profiles
- [ ] Add support for profile URLs
- [ ] Add support for crypto addresses on profiles (payment targets)
- [ ] Add support for Blossom and other media types
- [ ] Show relay lists on profiles
- [ ] Add UI for compose button
- [ ] Add recovery seed phrase support

## Other things:

- [ ] Make sure crypto logic is secure
- [ ] Fix build on Android with crypto libraries
- [ ] Add desktop support for macOS
- [ ] Rewrite doc comments
- [ ] Rewrite unit tests, improve coverage

# Ideas to improve performance

- Use `LazyBox` for Hive, if that's preferable
- Use Dart isolates to offload JSON parsing
- Lazy-loading of Hive keys

## Longer-term (not now):

- Use something like Drift or Isar instead of Hive for caching
