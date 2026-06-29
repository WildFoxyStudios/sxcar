class TokenPair {
  final String access;
  final String refresh;

  TokenPair({required this.access, required this.refresh});

  factory TokenPair.fromJson(Map<String, dynamic> json) {
    return TokenPair(
      access: json['access'] as String,
      refresh: json['refresh'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'access': access,
        'refresh': refresh,
      };
}

class RegisterData {
  final String email;
  final String password;
  final String dob;
  final List<String> consents;

  RegisterData({
    required this.email,
    required this.password,
    required this.dob,
    required this.consents,
  });

  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
        'dob': dob,
        'consents': consents,
      };
}

class LoginData {
  final String email;
  final String password;

  LoginData({required this.email, required this.password});

  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
      };
}

class AuthException implements Exception {
  final String message;
  final int? statusCode;

  AuthException(this.message, {this.statusCode});

  @override
  String toString() => 'AuthException: $message';
}
