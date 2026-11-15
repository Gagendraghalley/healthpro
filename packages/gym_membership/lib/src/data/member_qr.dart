import 'package:health_pro_core/health_pro_core.dart';

/// A member's QR code: their Health Pro QR code, `healthpro:member:<token>`
/// (one for every gym: on their phone, and on the card the desk sends); or,
/// from before that, `sportshub:gym-member:<card token>` on a gym's card or
/// `sportshub:member:<their account id>` on an account member's phone. Staff
/// can also type the member code printed under it ('4K7P9Q').
abstract final class MemberQr {
  static const prefix = 'sportshub:member:';
  static const cardPrefix = 'sportshub:gym-member:';

  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  static final _code = RegExp(r'^[A-Z0-9]{6}$');
  static final _token = RegExp(r'^[0-9a-f]{32}$');

  static String encode(String memberId) => '$prefix$memberId';

  /// What a gym's card held before personal QR codes.
  static String encodeCard(String qrToken) => '$cardPrefix$qrToken';

  /// A person's Health Pro QR code, on their card and their phone.
  static String encodePerson(String qrToken) => PersonQr.encode(qrToken);

  /// Who a scanned or typed [raw] points to; null when it's neither a
  /// member's QR code nor a member code.
  static MemberRef? parse(String raw) {
    final text = raw.trim();
    // A personal QR code and a gym's card both check in by their token.
    final person = PersonQr.tokenIn(text);
    if (person != null) return MemberRef.card(person);
    if (text.toLowerCase().startsWith(PersonQr.prefix)) return null;
    if (text.toLowerCase().startsWith(cardPrefix)) {
      final token = text.substring(cardPrefix.length).toLowerCase();
      return _token.hasMatch(token) ? MemberRef.card(token) : null;
    }
    if (text.toLowerCase().startsWith(prefix)) {
      final id = text.substring(prefix.length);
      return _uuid.hasMatch(id) ? MemberRef.id(id.toLowerCase()) : null;
    }
    if (_uuid.hasMatch(text)) return MemberRef.id(text.toLowerCase());
    final code = text.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    return _code.hasMatch(code) ? MemberRef.code(code) : null;
  }
}

/// A member: by account id (an account's QR code from before), by token (a
/// Health Pro QR code, or a gym's card) or by member code (typed).
class MemberRef {
  final String? id;
  final String? code;
  final String? cardToken;

  const MemberRef.id(String this.id)
      : code = null,
        cardToken = null;
  const MemberRef.code(String this.code)
      : id = null,
        cardToken = null;
  const MemberRef.card(String this.cardToken)
      : id = null,
        code = null;

  @override
  bool operator ==(Object other) =>
      other is MemberRef && other.id == id && other.code == code && other.cardToken == cardToken;

  @override
  int get hashCode => Object.hash(id, code, cardToken);

  @override
  String toString() => id != null
      ? 'MemberRef.id($id)'
      : cardToken != null
          ? 'MemberRef.card($cardToken)'
          : 'MemberRef.code($code)';
}
