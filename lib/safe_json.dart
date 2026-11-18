// Parse an toan tu JSON mang / luu tru: KHONG BAO GIO throw vi sai kieu.
//
// Loi crash v1.2.0 (mo app, 17/11): code ep kieu truc tiep `as num?` /
// `as List<dynamic>?` len du lieu JSON. Mot so nguon tra so duoi dang
// CHUOI (Binance tra price "65000.00", Kraken OHLC tra OHLCV dang chuoi,
// Kraken ticker tra 'o' la chuoi), hoac khi nguon loi thi truong chua
// chuoi bao loi thay vi danh sach/so -> ep kieu no ngay khi mo app.
//
// Quy tac o day:
//  - So nhan ca dang so lan chuoi so (tryParse).
//  - List/Map chi nhan sau khi kiem tra `is`.
//  - Chuoi thi chuyen qua '$v' thay vi ep `as String?`.
//  - Khong parse duoc -> null / mac dinh, de caller fallback (mock /
//    "DANG TAI" / "DU LIEU CU"), khong throw.

/// So thuc tu JSON: nhan num hoac chuoi so ("65000.00", "3882.50").
double? numD(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

/// So nguyen tu JSON: nhan num hoac chuoi so ("1763419200", "42").
int? numI(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  if (v is String) {
    final String s = v.trim();
    final int? i = int.tryParse(s);
    if (i != null) return i;
    return double.tryParse(s)?.toInt();
  }
  return null;
}

/// Danh sach tu JSON: chi nhan khi dung la List, neu khac (chuoi bao loi,
// null, ...) thi tra null thay vi throw.
List<dynamic>? asList(Object? v) => v is List ? v : null;

/// Map tu JSON: chi nhan khi dung la Map.
Map<String, dynamic>? asMap(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

/// Chuoi tu JSON: null -> mac dinh; so/bool/... -> toString().
/// Dung thay cho `(v as String? ?? '')` (no neu v la so).
String strOf(Object? v, [String dflt = '']) => v == null ? dflt : '$v';
