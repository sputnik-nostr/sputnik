/// Whole code points, so an emoji is not split into a lone surrogate.
String avatarInitial(String name) =>
    name.isEmpty ? '' : String.fromCharCode(name.runes.first).toUpperCase();
