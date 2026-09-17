# Feature roadmap

- [x] Add more good default relay options
- [x] Allow clicking on URLs
- [x] Show followers/following lists on profiles
- [x] Show actual reaction data for posts (read-only - see below)
- [x] Allow searching for `nprofile` keys (rather than just `npub`)
- [x] Allow searching for post IDs
- [x] Show full profile pictures/banners when clicked
- [x] Add support for crypto addresses on profiles (payment targets)
- [x] Add UI for compose button
- [x] Publish notes to relays (signed, with a confirm step)
- [x] Publish profile edits to relays (name/bio only so far)
- [x] Publish follow/unfollow to relays (was previously a stub)
- [x] Allow copying text
- [ ] Separate posts and replies on profiles
- [ ] Add support for profile URLs
- [ ] Add support for Blossom and other media types
- [ ] Show relay lists on profiles
- [ ] Add recovery seed phrase support

## Posting and interaction (current state)

- [x] Compose and publish a top-level note
- [x] Follow/unfollow (instant UI, published in the background)
- [ ] Reply to a post (threads are readable, but there's no way to post into one)
- [ ] Repost a note (repost counts are shown, but read-only)
- [ ] React to a note, e.g. a like (like counts are shown, but read-only)
- [ ] Real notifications (the Notifications tab is still a placeholder)

## Other things:

- [ ] Make sure crypto logic is secure
- [x] Fix build on Android with crypto libraries
- [ ] Add desktop support for macOS
- [ ] Rewrite doc comments
- [x] Rewrite unit tests, improve coverage
- [x] Show follow buttons directly in a followers/following/reactions list
- [ ] Let editing a profile cover more fields than name/bio (picture, banner, NIP-05, website)
- [ ] Add an option to hide specific crypto address types from being shown on a profile
- [ ] Add an option to hide/show client ID string

# Ideas to improve performance

- Use `LazyBox` for Hive, if that's preferable
- Use Dart isolates to offload JSON parsing
- Lazy-loading of Hive keys
