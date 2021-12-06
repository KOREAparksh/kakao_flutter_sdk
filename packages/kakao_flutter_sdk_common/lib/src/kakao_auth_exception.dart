import 'package:json_annotation/json_annotation.dart';
import 'package:kakao_flutter_sdk_common/src/kakao_error.dart';

part 'kakao_auth_exception.g.dart';

/// 카카오 OAuth API 호출 시 에러 응답
@JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: false)
class KakaoAuthException extends KakaoException {
  /// @nodoc
  KakaoAuthException(this.error, this.errorDescription)
      : super(errorDescription);

  /// invalid_grant 등 어떤 에러인지 나타내주는 스트링 값
  @JsonKey(unknownEnumValue: AuthErrorCause.UNKNOWN)
  final AuthErrorCause error;

  /// 자세한 에러 설명
  final String? errorDescription;

  /// @nodoc
  factory KakaoAuthException.fromJson(Map<String, dynamic> json) =>
      _$KakaoAuthExceptionFromJson(json);

  /// @nodoc
  Map<String, dynamic> toJson() => _$KakaoAuthExceptionToJson(this);

  @override
  String toString() => toJson().toString();
}

/// [KakaoAuthException]의 발생 원인
enum AuthErrorCause {
  /// 요청 파라미터 오류
  @JsonValue("invalid_request")
  INVALID_REQUEST,

  /// 유효하지 않은 앱
  @JsonValue("invalid_client")
  INVALID_CLIENT,

  /// 유효하지 않은 scope ID
  @JsonValue("invalid_scope")
  INVALID_SCOPE,

  /// 인증 수단이 유효하지 않아 인증할 수 없는 상태
  @JsonValue("invalid_grant")
  INVALID_GRANT,

  /// 설정이 올바르지 않음 (android key hash 또는 redirect uri).
  @JsonValue("misconfigured")
  MISCONFIGURED,

  /// 앱이 요청 권한이 없음
  @JsonValue("unauthorized")
  UNAUTHORIZED,

  /// 접근이 거부 됨 (동의 취소)
  @JsonValue("access_denied")
  ACCESS_DENIED,

  /// 서버 내부 에러
  @JsonValue("server_error")
  SERVER_ERROR,

  /// 기타 에러
  UNKNOWN
}
