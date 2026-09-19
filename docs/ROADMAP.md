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
- [x] Publish profile edits to relays
- [x] Publish follow/unfollow to relays (was previously a stub)
- [x] Allow copying text
- [x] Separate posts and replies on profiles
- [x] Separate following and global feeds on the home page
- [x] Keep replies out of the home feeds (they stay on profiles and in threads)
- [x] Show a cited npub or nprofile as the person's name, linking to their profile
- [x] Show a cited note or nevent as a short link that opens the post
- [x] Infinite scroll on the home feeds and profiles (up to 1000 posts loaded per list)
- [ ] Add support for profile URLs
- [ ] Add support for Blossom and other media types
- [x] Show relay lists on profiles
- [ ] Add recovery seed phrase support

## Posting and interaction (current state)

- [x] Compose and publish a top-level note
- [x] Follow/unfollow (instant UI, published in the background)
- [x] Reply to a post (with the full thread: ancestors and nested replies)
- [ ] Repost a note (repost counts are shown, but read-only)
- [ ] React to a note, e.g. a like (like counts are shown, but read-only)
- [ ] Real notifications (the Notifications tab is still a placeholder)

## Other things:

- [x] Fix build on Android with crypto libraries
- [x] Rewrite unit tests, improve coverage
- [x] Show follow buttons directly in a followers/following/reactions list
- [x] Add an option to hide specific crypto address types from being shown on a profile
- [ ] Make sure crypto logic is secure
- [ ] Add desktop support for macOS
- [ ] Rewrite doc comments
- [x] Let editing a profile cover more fields than name/bio (picture, banner, NIP-05, website)
- [x] Publish your own relay list (NIP-65) and use it to set your relays
- [x] Edit your own payment targets
- [ ] Route posts by relay lists (outbox model), instead of only the selected relays
- [ ] Add an option to hide/show client ID string
- [ ] Add payment targets support for Zano and Firo
- [ ] Have some visual indication that there are more payment target chips to scroll to

# Ideas to improve performance

- Use `LazyBox` for Hive, if that's preferable
- Lazy-loading of Hive keys
