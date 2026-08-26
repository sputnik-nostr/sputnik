const _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
const _generators = [
  0x3b6a57b2,
  0x26508e6d,
  0x1ea119fa,
  0x3d4233dd,
  0x2a1462b3,
];

const _maxLength = 5000;

final _charsetReverse = () {
  final table = List<int>.filled(128, -1);
  for (var i = 0; i < _charset.length; i++) {
    table[_charset.codeUnitAt(i)] = i;
  }
  return table;
}();

bool _hasOutOfRangeHrpChars(String hrp) {
  return hrp.codeUnits.any((c) => c < 33 || c > 126);
}

bool _isMixedCase(String s) => s != s.toLowerCase() && s != s.toUpperCase();

int _polymod(List<int> values) {
  var chk = 1;
  for (final value in values) {
    final top = chk >> 25;
    chk = ((chk & 0x1ffffff) << 5) ^ value;
    for (var i = 0; i < 5; i++) {
      if ((top >> i) & 1 == 1) chk ^= _generators[i];
    }
  }
  return chk;
}

List<int> _hrpExpand(String hrp) {
  final bytes = hrp.codeUnits;
  return [...bytes.map((b) => b >> 5), 0, ...bytes.map((b) => b & 31)];
}

List<int> _createChecksum(String hrp, List<int> data) {
  final values = [..._hrpExpand(hrp), ...data, 0, 0, 0, 0, 0, 0];
  final mod = _polymod(values) ^ 1;
  return [for (var i = 0; i < 6; i++) (mod >> (5 * (5 - i))) & 31];
}

List<int> convertBits(
  List<int> data,
  int fromBits,
  int toBits, {
  required bool pad,
}) {
  var acc = 0;
  var bits = 0;
  final result = <int>[];
  final maxValue = (1 << toBits) - 1;
  for (final value in data) {
    if (value < 0 || (value >> fromBits) != 0) return const [];
    acc = (acc << fromBits) | value;
    bits += fromBits;
    while (bits >= toBits) {
      bits -= toBits;
      result.add((acc >> bits) & maxValue);
    }
  }
  if (pad) {
    if (bits > 0) result.add((acc << (toBits - bits)) & maxValue);
  } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxValue) != 0) {
    return const [];
  }
  return result;
}

String bech32Encode(String hrp, List<int> data) {
  assert(hrp.isNotEmpty && !_hasOutOfRangeHrpChars(hrp) && !_isMixedCase(hrp));

  final checksum = _createChecksum(hrp, data);
  final combined = [...data, ...checksum];
  return '${hrp}1${combined.map((d) => _charset[d]).join()}';
}

({String hrp, List<int> data})? bech32Decode(String input) {
  if (input.isEmpty || input.length > _maxLength || _isMixedCase(input)) {
    return null;
  }
  final lower = input.toLowerCase();
  final separator = lower.lastIndexOf('1');
  if (separator < 1 || separator + 7 > lower.length) return null;

  final hrp = lower.substring(0, separator);
  if (_hasOutOfRangeHrpChars(hrp)) return null;

  final data = <int>[];
  for (final codeUnit in lower.substring(separator + 1).codeUnits) {
    final index = codeUnit < 128 ? _charsetReverse[codeUnit] : -1;
    if (index == -1) return null;
    data.add(index);
  }
  if (_polymod([..._hrpExpand(hrp), ...data]) != 1) return null;

  return (hrp: hrp, data: data.sublist(0, data.length - 6));
}
