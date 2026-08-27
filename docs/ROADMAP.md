# Feature roadmap

- [x] Add more good default relay options
- [x] Allow clicking on URLs
- [x] Show followers/following lists on profiles
- [x] Show actual reaction data for posts
- [ ] Allow copying text
- [ ] Separate posts and replies on profiles
- [ ] Allow searching for `nprofile` keys (rather than just `npub`)
- [ ] Add support for profile URLs
- [ ] Add support for crypto addresses on profiles
- [ ] Allow searching for post IDs
- [ ] Add support for Blossom and other media types
- [ ] Show relay lists on profiles
- [ ] Show full profile pictures/banners when clicked
- [ ] Add UI for compose button

# Ideas to improve performance

- Use `LazyBox` for Hive, if that's preferable
- Use Dart isolates to offload JSON parsing
- Lazy-loading of Hive keys

## Less-relevant optimizations:

- Use `StringBuffer` instead of `String`
- Declare all `RegExp` instances as `static final`
- Use `ListView.builder` with `itemExtent` or `SliverFixedExtentList` for list items with a fixed height
- Wrap lists in `RepaintBoundary` to prevent re-rendering
- Ensure list item widgets use `const` layouts wherever possible

## Longer-term (not now):

- Use Drift or Isar instead of Hive for caching
