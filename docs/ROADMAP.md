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
- [x] Show relay lists on profiles
- [ ] Add support for Blossom and other media types (see below)
- [ ] Add recovery seed phrase support

## Posting and interaction (current state)

- [x] Compose and publish a top-level note
- [x] Follow/unfollow (instant UI, published in the background)
- [x] Reply to a post (with the full thread: ancestors and nested replies)
- [ ] Repost a note (repost counts are shown, but read-only)
- [ ] React to a note, e.g. a like (like counts are shown, but read-only)
- [ ] Real notifications (the Notifications tab is still a placeholder)

## Media (current state)

- [x] Show images in notes (tap to load by default)
- [x] Show videos in notes (always tap to play)
- [x] Check media against its SHA-256 and fall back to the author's Blossom servers
- [ ] Attach images and videos when composing a note (with `imeta` tags)
- [ ] Upload media to Blossom servers
- [ ] Edit your own Blossom server list (kind 10063)
- [ ] Strip location and other metadata (EXIF) from images before uploading
- [ ] Show upload progress, and let an upload be cancelled
- [ ] Hide notes with a content warning (NIP-36) behind a tap, including their media
- [ ] Add a content warning when composing a note
- [ ] Show audio in notes
- [x] Show video posters and blurhash placeholders (`image`, `thumb`, `blurhash`)
- [x] Play only one video at a time
- [x] Show a note's images and videos side by side in a row that scrolls sideways
- [x] Swipe between the images in a note in the viewer
- [x] Save an image or copy its link from the viewer
- [ ] Pause a video that has scrolled out of view
- [ ] Let the viewer swipe to the next image while zoomed in (paging is locked while zoomed)
- [ ] Verify video fullscreen, seeking, and portrait layout
- [ ] Test media on Android (the video lockdown options, the prebuilt `media_kit` libraries, saving to the gallery)
- [ ] Check the hash rule against real hosts (e.g. nostr.build) so no existing notes break
- [ ] Load profile pictures and banners with the same size cap, redirect, and hash rules
- [ ] Bundle libmpv in the Linux AppImage, and document that Linux needs it

## Other things:

- [x] Fix build on Android with crypto libraries
- [x] Rewrite unit tests, improve coverage
- [x] Show follow buttons directly in a followers/following/reactions list
- [x] Add an option to hide specific crypto address types from being shown on a profile
- [x] Let editing a profile cover more fields than name/bio (picture, banner, NIP-05, website)
- [x] Publish your own relay list (NIP-65) and use it to set your relays
- [x] Edit your own payment targets
- [x] Add payment targets support for Zano and Firo
- [ ] Make sure crypto logic is secure
- [ ] Add desktop support for macOS
- [ ] Rewrite doc comments
- [ ] Route posts by relay lists (outbox model), instead of only the selected relays
- [ ] Add an option to hide/show client ID string
- [ ] Have some visual indication that there are more payment target chips to scroll to
